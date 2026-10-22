import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/connector/pending_command_replies.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';

// Отдельные регрессии учёта; принятый frame_command_baseline_test не меняется.
class _TrackedConnector extends MeshCoreConnector {
  bool connected = true;
  bool disposed = false;
  final heldWrites = <Completer<void>>[];
  final frames = <List<int>>[];
  Future<void> Function()? writer;

  _TrackedConnector() {
    setFrameWriterForTest((frame) {
      frames.add(List<int>.of(frame));
      return writer?.call() ?? Future<void>.value();
    });
  }

  @override
  bool get isConnected => connected;

  Completer<void> holdWrite() {
    final completion = Completer<void>();
    heldWrites.add(completion);
    writer = () {
      writer = null;
      return completion.future;
    };
    return completion;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Result {
  _Result(Future<void> operation) {
    unawaited(operation.then<void>((_) {
      completed = true;
    }, onError: (Object value, StackTrace stack) {
      error = value;
      completed = true;
    }));
  }

  bool completed = false;
  Object? error;
}

void _expectWork(_TrackedConnector c, {int writes = 0, int replies = 0, bool closed = false}) {
  final snapshot = c.backgroundWorkSnapshot;
  expect(snapshot.countFor(BackgroundWorkKind.transportWrite), writes);
  expect(snapshot.countFor(BackgroundWorkKind.commandReply), replies);
  expect(snapshot.activeCount, writes + replies);
  expect(snapshot.isBusy, writes + replies > 0);
  expect(snapshot.isClosed, closed);
}

Future<void> _withConnector(
  WidgetTester tester,
  Future<void> Function(_TrackedConnector c) check,
) async {
  final c = _TrackedConnector();
  try {
    await check(c);
  } finally {
    for (final write in c.heldWrites) {
      if (!write.isCompleted) write.complete();
    }
    await tester.pump();
    if (!c.disposed) c.dispose();
    await tester.pump(const Duration(seconds: 5));
  }
}

Future<void> _send(_TrackedConnector c, {bool wait = true}) =>
    c.sendFrame(buildSetAdvertNameFrame('synthetic'), waitForGenericAck: wait);

void main() {
  const timeout = Timeout(Duration(seconds: 30));

  testWidgets('write is held before physical writer and passive reply is not held', (tester) async {
    await _withConnector(tester, (c) async {
      final completion = Completer<void>();
      c.heldWrites.add(completion);
      c.writer = () {
        _expectWork(c, writes: 1);
        return completion.future;
      };
      final result = _Result(_send(c, wait: false));
      _expectWork(c, writes: 1);
      expect(c.pendingCommandReplyCountForTest, 1);
      completion.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      _expectWork(c);
      expect(c.pendingCommandReplyCountForTest, 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('awaited command spans write then ACK with immutable snapshots', (tester) async {
    await _withConnector(tester, (c) async {
      final write = c.holdWrite();
      final result = _Result(_send(c));
      _expectWork(c, writes: 1, replies: 1);
      final duringWrite = c.backgroundWorkSnapshot;
      write.complete();
      await tester.pump();
      _expectWork(c, replies: 1);
      expect(result.completed, isFalse);
      expect(duringWrite.countFor(BackgroundWorkKind.transportWrite), 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('early OK cannot finish a command while its write is incomplete', (tester) async {
    await _withConnector(tester, (c) async {
      final write = c.holdWrite();
      final result = _Result(_send(c));
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      _expectWork(c, writes: 1, replies: 1);
      expect(c.pendingCommandReplyCountForTest, 0);
      expect(result.completed, isFalse);
      write.complete();
      await tester.pump();
      _expectWork(c);
      expect(result.completed, isTrue);
      expect(result.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('early ERR drains both leases when the command actually fails', (tester) async {
    await _withConnector(tester, (c) async {
      final write = c.holdWrite();
      final result = _Result(_send(c));
      c.handleFrameForTest([respCodeErr, 6]);
      await tester.pump();
      _expectWork(c, writes: 1, replies: 1);
      write.complete();
      await tester.pump();
      expect(result.error, isA<CommandFailedException>().having(
        (error) => error.errCode, 'errCode', 6));
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('write error releases both leases and preserves the original error', (tester) async {
    await _withConnector(tester, (c) async {
      final write = c.holdWrite();
      final result = _Result(_send(c));
      final failure = StateError('Synthetic write failure');
      write.completeError(failure);
      await tester.pump();
      expect(result.error, same(failure));
      expect(c.pendingCommandReplyCountForTest, 0);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('write timeout leaves original I/O held without releasing a newer command',
      (tester) async {
    await _withConnector(tester, (c) async {
      final oldWrite = c.holdWrite();
      final old = _Result(_send(c));
      await tester.pump(const Duration(seconds: 5));
      expect(old.error, isA<TimeoutException>());
      _expectWork(c, writes: 1);
      expect(c.pendingCommandReplyCountForTest, 0);
      final next = _Result(_send(c));
      await tester.pump();
      _expectWork(c, writes: 1, replies: 1);
      oldWrite.complete();
      await tester.pump();
      _expectWork(c, replies: 1);
      expect(next.completed, isFalse);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(next.error, isNull);
      expect(next.completed, isTrue);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('late I/O failure after caller timeout releases its own remaining lease',
      (tester) async {
    await _withConnector(tester, (c) async {
      final write = c.holdWrite();
      final result = _Result(_send(c));
      await tester.pump(const Duration(seconds: 5));
      final timeoutError = result.error;
      expect(timeoutError, isA<TimeoutException>());
      _expectWork(c, writes: 1);
      write.completeError(StateError('Synthetic late failure'));
      await tester.pump();
      expect(result.error, same(timeoutError));
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('ACK timeout does not keep tombstone busy or release the next command',
      (tester) async {
    await _withConnector(tester, (c) async {
      final old = _Result(_send(c));
      await tester.pump();
      _expectWork(c, replies: 1);
      await tester.pump(const Duration(seconds: 5));
      expect(old.error, isA<TimeoutException>());
      expect(c.pendingCommandReplyCountForTest, 1);
      _expectWork(c);
      final next = _Result(_send(c));
      await tester.pump();
      _expectWork(c, replies: 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(next.completed, isFalse);
      _expectWork(c, replies: 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(next.completed, isTrue);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('generic OK cannot release a command awaiting a specific response', (tester) async {
    await _withConnector(tester, (c) async {
      final result = _Result(c.sendFrame(buildGetDeviceTimeFrame(), waitForGenericAck: true));
      await tester.pump();
      _expectWork(c, replies: 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      _expectWork(c, replies: 1);
      c.handleFrameForTest([respCodeCurrTime, 1, 0, 0, 0]);
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('concurrent commands retain independent write and command leases', (tester) async {
    await _withConnector(tester, (c) async {
      final firstWrite = c.holdWrite();
      final first = _Result(_send(c));
      final secondWrite = c.holdWrite();
      final second = _Result(_send(c));
      _expectWork(c, writes: 2, replies: 2);
      firstWrite.complete();
      await tester.pump();
      _expectWork(c, writes: 1, replies: 2);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(first.completed, isTrue);
      expect(second.completed, isFalse);
      _expectWork(c, writes: 1, replies: 1);
      secondWrite.complete();
      await tester.pump();
      _expectWork(c, replies: 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(second.completed, isTrue);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('dispose closes registration while an existing command and write drain',
      (tester) async {
    await _withConnector(tester, (c) async {
      final write = c.holdWrite();
      final result = _Result(_send(c));
      c.dispose();
      _expectWork(c, writes: 1, replies: 1, closed: true);
      write.complete();
      await tester.pump();
      _expectWork(c, replies: 1, closed: true);
      await tester.pump(const Duration(seconds: 5));
      expect(result.error, isA<TimeoutException>());
      _expectWork(c, closed: true);
    });
  }, timeout: timeout);

  testWidgets('disconnected send creates no work and no physical frames', (tester) async {
    await _withConnector(tester, (c) async {
      c.connected = false;
      final result = _Result(_send(c));
      await tester.pump();
      expect(result.error, isA<Exception>());
      expect(c.frames, isEmpty);
      _expectWork(c);
    });
  }, timeout: timeout);
}
