import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/connector/pending_command_replies.dart';

// Настоящий sendFrame/dispatch ACK; подменён только физический writer.
class _FrameConnector extends MeshCoreConnector {
  bool connected = true;
  final writes = <List<int>>[];
  final heldWrites = <Completer<void>>[];
  Future<void> Function()? write;

  _FrameConnector() {
    setFrameWriterForTest((frame) {
      writes.add(List<int>.of(frame));
      return write?.call() ?? Future<void>.value();
    });
  }

  @override
  bool get isConnected => connected;

  Completer<void> holdNextWrite() {
    final completion = Completer<void>();
    heldWrites.add(completion);
    write = () {
      write = null;
      return completion.future;
    };
    return completion;
  }
}

class _CommandResult {
  _CommandResult(Future<void> operation) {
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

Future<void> _withConnector(
  WidgetTester tester,
  Future<void> Function(_FrameConnector connector) check,
) async {
  final connector = _FrameConnector();
  try {
    await check(connector);
  } finally {
    for (final completion in connector.heldWrites) {
      if (!completion.isCompleted) completion.complete();
    }
    // Сначала завершаются записи и запускаются возможные ACK timeout.
    await tester.pump();
    connector.dispose();
    await tester.pump(const Duration(seconds: 5));
  }
}

void main() {
  const timeout = Timeout(Duration(seconds: 30));

  testWidgets('baseline: untracked frame waits for write and preserves bytes', (tester) async {
    await _withConnector(tester, (c) async {
      final write = c.holdNextWrite();
      final result = _CommandResult(c.sendFrame(buildSyncNextMessageFrame()));
      await tester.pump();
      expect(c.writes, [[cmdSyncNextMessage]]);
      expect(result.completed, isFalse);
      expect(c.pendingCommandReplyCountForTest, 0);
      write.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: OK before write completion is registered and preserved', (tester) async {
    await _withConnector(tester, (c) async {
      final frame = buildSetAdvertNameFrame('synthetic');
      final write = c.holdNextWrite();
      final result = _CommandResult(c.sendFrame(frame, waitForGenericAck: true));
      await tester.pump();
      expect(c.pendingCommandReplyCountForTest, 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(c.pendingCommandReplyCountForTest, 0);
      expect(result.completed, isFalse);
      write.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.writes.single, orderedEquals(frame));
    });
  }, timeout: timeout);

  testWidgets('baseline: early ERR is delivered after write without an unhandled error',
      (tester) async {
    await _withConnector(tester, (c) async {
      final write = c.holdNextWrite();
      final result = _CommandResult(c.sendFrame(
        buildSetAdvertNameFrame('synthetic'), waitForGenericAck: true));
      c.handleFrameForTest([respCodeErr, 6]);
      await tester.pump();
      expect(result.completed, isFalse);
      expect(c.pendingCommandReplyCountForTest, 0);
      write.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isA<CommandFailedException>().having(
        (error) => error.errCode, 'errCode', 6));
    });
  }, timeout: timeout);

  testWidgets('baseline: no-wait command finishes while its reply is still queued', (tester) async {
    await _withConnector(tester, (c) async {
      final result = _CommandResult(c.sendFrame(buildSetAdvertNameFrame('synthetic')));
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.pendingCommandReplyCountForTest, 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(c.pendingCommandReplyCountForTest, 0);
    });
  }, timeout: timeout);

  testWidgets('baseline: write failure removes its entry before the next command', (tester) async {
    await _withConnector(tester, (c) async {
      final failure = StateError('Synthetic write error');
      c.write = () => Future<void>.error(failure);
      final failed = _CommandResult(c.sendFrame(
        buildSetAdvertNameFrame('first'), waitForGenericAck: true));
      await tester.pump();
      expect(failed.error, same(failure));
      expect(c.pendingCommandReplyCountForTest, 0);
      c.write = null;
      final next = _CommandResult(c.sendFrame(
        buildSetAdvertNameFrame('next'), waitForGenericAck: true));
      await tester.pump();
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(next.completed, isTrue);
      expect(next.error, isNull);
      expect(c.pendingCommandReplyCountForTest, 0);
    });
  }, timeout: timeout);

  testWidgets('baseline: write timeout does not cancel I/O or alter the next pending command',
      (tester) async {
    await _withConnector(tester, (c) async {
      final oldWrite = c.holdNextWrite();
      final first = _CommandResult(c.sendFrame(
        buildSetAdvertNameFrame('first'), waitForGenericAck: true));
      await tester.pump(const Duration(seconds: 4));
      expect(first.completed, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(first.error, isA<TimeoutException>());
      expect(oldWrite.isCompleted, isFalse);
      expect(c.pendingCommandReplyCountForTest, 0);
      final next = _CommandResult(c.sendFrame(
        buildSetAdvertNameFrame('next'), waitForGenericAck: true));
      await tester.pump();
      oldWrite.complete();
      await tester.pump();
      expect(next.completed, isFalse);
      expect(c.pendingCommandReplyCountForTest, 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(next.completed, isTrue);
      expect(next.error, isNull);
      expect(c.writes, hasLength(2));
    });
  }, timeout: timeout);

  testWidgets('baseline: ACK timeout starts after write and late OK absorbs its tombstone',
      (tester) async {
    await _withConnector(tester, (c) async {
      final write = c.holdNextWrite();
      final first = _CommandResult(c.sendFrame(
        buildSetAdvertNameFrame('first'), waitForGenericAck: true));
      await tester.pump(const Duration(seconds: 4));
      write.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(first.completed, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(first.error, isA<TimeoutException>());
      expect(c.pendingCommandReplyCountForTest, 1);
      final next = _CommandResult(c.sendFrame(
        buildSetAdvertNameFrame('next'), waitForGenericAck: true));
      await tester.pump();
      expect(c.pendingCommandReplyCountForTest, 2);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(next.completed, isFalse);
      expect(c.pendingCommandReplyCountForTest, 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(next.completed, isTrue);
      expect(next.error, isNull);
      expect(c.pendingCommandReplyCountForTest, 0);
    });
  }, timeout: timeout);

  testWidgets('baseline: a specific response cannot be replaced by generic OK', (tester) async {
    await _withConnector(tester, (c) async {
      final result = _CommandResult(c.sendFrame(
        buildGetDeviceTimeFrame(), waitForGenericAck: true));
      await tester.pump();
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(result.completed, isFalse);
      expect(c.pendingCommandReplyCountForTest, 1);
      c.handleFrameForTest([respCodeCurrTime, 1, 0, 0, 0]);
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.pendingCommandReplyCountForTest, 0);
    });
  }, timeout: timeout);

  testWidgets('baseline: disconnected command fails before tracking or writing', (tester) async {
    await _withConnector(tester, (c) async {
      c.connected = false;
      final result = _CommandResult(c.sendFrame(
        buildSetAdvertNameFrame('synthetic'), waitForGenericAck: true));
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isA<Exception>());
      expect(c.writes, isEmpty);
      expect(c.pendingCommandReplyCountForTest, 0);
    });
  }, timeout: timeout);
}
