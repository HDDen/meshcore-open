import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';

// Реальные request/write/dispatch и отдельные счётчики. Baseline не меняется.
class _RequestConnector extends MeshCoreConnector {
  bool connected = true;
  bool disposed = false;
  final frames = <List<int>>[];
  final held = <Completer<void>>[];
  Future<void> Function()? write;

  _RequestConnector() {
    setFrameWriterForTest((frame) {
      frames.add(List<int>.of(frame));
      return write?.call() ?? Future<void>.value();
    });
  }

  @override
  bool get isConnected => connected;

  Completer<void> hold() {
    final completion = Completer<void>();
    held.add(completion);
    return completion;
  }

  Completer<void> holdNextWrite() {
    final completion = hold();
    write = () {
      write = null;
      return completion.future;
    };
    return completion;
  }

  void finishQueue() => handleFrameForTest([respCodeNoMoreMessages]);

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

void _expectWork(
  _RequestConnector c, {
  int requests = 0,
  int writes = 0,
  int processing = 0,
  bool closed = false,
}) {
  final snapshot = c.backgroundWorkSnapshot;
  expect(snapshot.countFor(BackgroundWorkKind.queuedMessageRequest), requests);
  expect(snapshot.countFor(BackgroundWorkKind.transportWrite), writes);
  expect(snapshot.countFor(BackgroundWorkKind.messageSync), processing);
  expect(snapshot.activeCount, requests + writes + processing);
  expect(snapshot.isBusy, requests + writes + processing > 0);
  expect(snapshot.isClosed, closed);
}

Future<void> _withRequest(
  WidgetTester tester,
  Future<void> Function(_RequestConnector c) check,
) async {
  final c = _RequestConnector();
  try {
    await check(c);
  } finally {
    c.connected = false;
    for (final completion in c.held) {
      if (!completion.isCompleted) {
        completion.complete();
      }
    }
    await tester.pump();
    if (!c.disposed) {
      c.finishQueue();
      c.dispose();
    }
    await tester.pump(const Duration(seconds: 5));
  }
}

void main() {
  const timeout = Timeout(Duration(seconds: 30));

  testWidgets('request starts before write and expires at its original deadline', (tester) async {
    await _withRequest(tester, (c) async {
      final write = c.holdNextWrite();
      final result = _Result(c.syncQueuedMessages());
      _expectWork(c, requests: 1, writes: 1);
      final before = c.backgroundWorkSnapshot;
      await c.syncQueuedMessages(force: true);
      c.handleFrameForTest([pushCodeMsgWaiting]);
      await tester.pump(const Duration(seconds: 4));
      _expectWork(c, requests: 1, writes: 1);
      expect(c.frames, [[cmdSyncNextMessage]]);
      write.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      _expectWork(c, requests: 1);
      c.handleFrameForTest([respCodeOk]);
      c.handleFrameForTest([respCodeErr]);
      await tester.pump(const Duration(milliseconds: 999));
      _expectWork(c, requests: 1);
      await tester.pump(const Duration(milliseconds: 1));
      _expectWork(c);
      expect(c.isSyncingQueuedMessages, isFalse);
      expect(before.countFor(BackgroundWorkKind.queuedMessageRequest), 1);
      expect(before.countFor(BackgroundWorkKind.transportWrite), 1);
    });
  }, timeout: timeout);

  testWidgets('write failure releases the logical wait without retrying', (tester) async {
    await _withRequest(tester, (c) async {
      final write = c.holdNextWrite();
      final result = _Result(c.syncQueuedMessages());
      _expectWork(c, requests: 1, writes: 1);
      write.completeError(StateError('synthetic queue write failure'));
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.isSyncingQueuedMessages, isFalse);
      _expectWork(c);
      await tester.pump(const Duration(seconds: 6));
      expect(c.frames, [[cmdSyncNextMessage]]);
    });
  }, timeout: timeout);

  testWidgets('write timeout leaves physical work and a new wait remains independent', (tester) async {
    await _withRequest(tester, (c) async {
      final oldWrite = c.holdNextWrite();
      final oldRequest = _Result(c.syncQueuedMessages());
      await tester.pump(const Duration(seconds: 5));
      expect(oldRequest.completed, isTrue);
      expect(oldRequest.error, isNull);
      _expectWork(c, writes: 1);
      await c.syncQueuedMessages();
      _expectWork(c, requests: 1, writes: 1);
      oldWrite.complete();
      await tester.pump();
      _expectWork(c, requests: 1);
      expect(c.isSyncingQueuedMessages, isTrue);
      c.finishQueue();
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('early empty reply releases only the wait, not old or new I/O', (tester) async {
    await _withRequest(tester, (c) async {
      final oldWrite = c.holdNextWrite();
      final oldRequest = _Result(c.syncQueuedMessages());
      c.finishQueue();
      _expectWork(c, writes: 1);
      expect(oldRequest.completed, isFalse);
      final newWrite = c.holdNextWrite();
      final newRequest = _Result(c.syncQueuedMessages());
      _expectWork(c, requests: 1, writes: 2);
      oldWrite.complete();
      await tester.pump();
      expect(oldRequest.completed, isTrue);
      expect(oldRequest.error, isNull);
      expect(newRequest.completed, isFalse);
      _expectWork(c, requests: 1, writes: 1);
      expect(c.isSyncingQueuedMessages, isTrue);
      newWrite.complete();
      await tester.pump();
      expect(newRequest.completed, isTrue);
      expect(newRequest.error, isNull);
      _expectWork(c, requests: 1);
      c.finishQueue();
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('received frame transfers the wait to processing and then the next request', (tester) async {
    await _withRequest(tester, (c) async {
      await c.syncQueuedMessages();
      _expectWork(c, requests: 1);
      final completion = c.hold();
      BackgroundWorkSnapshot? duringProcessing;
      final result = _Result(c.processQueuedMessageForTest(process: () {
        duringProcessing = c.backgroundWorkSnapshot;
        return completion.future;
      }));
      _expectWork(c, processing: 1);
      await tester.pump(const Duration(seconds: 6));
      _expectWork(c, processing: 1);
      expect(duringProcessing?.countFor(BackgroundWorkKind.messageSync), 1);
      expect(duringProcessing?.countFor(BackgroundWorkKind.queuedMessageRequest), 0);
      completion.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      _expectWork(c, requests: 1);
      expect(c.frames, [[cmdSyncNextMessage], [cmdSyncNextMessage]]);
      c.finishQueue();
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('local source does not release the unrelated request wait', (tester) async {
    await _withRequest(tester, (c) async {
      await c.syncQueuedMessages();
      final completion = c.hold();
      final result = _Result(c.processQueuedMessageForTest(
        localSourceLabel: 'synthetic local source',
        process: () => completion.future,
      ));
      _expectWork(c, requests: 1, processing: 1);
      await tester.pump(const Duration(seconds: 5));
      _expectWork(c, processing: 1);
      expect(result.completed, isFalse);
      completion.complete();
      await tester.pump();
      expect(result.error, isNull);
      expect(result.completed, isTrue);
      _expectWork(c);
      expect(c.frames, [[cmdSyncNextMessage]]);
    });
  }, timeout: timeout);

  testWidgets('sync reset releases wait while the underlying write remains held', (tester) async {
    await _withRequest(tester, (c) async {
      final write = c.holdNextWrite();
      final result = _Result(c.syncQueuedMessages());
      c.resetSyncProgressForTest();
      _expectWork(c, writes: 1);
      expect(c.isSyncingQueuedMessages, isFalse);
      write.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('dispose preserves the wait until its existing timeout drains it', (tester) async {
    await _withRequest(tester, (c) async {
      await c.syncQueuedMessages();
      c.dispose();
      _expectWork(c, requests: 1, closed: true);
      await tester.pump(const Duration(seconds: 5));
      _expectWork(c, closed: true);
      expect(c.frames, [[cmdSyncNextMessage]]);
    });
  }, timeout: timeout);

  testWidgets('late request after close keeps old execution without a new holding', (tester) async {
    await _withRequest(tester, (c) async {
      c.dispose();
      final revision = c.backgroundWorkSnapshot.revision;
      await c.syncQueuedMessages();
      _expectWork(c, closed: true);
      await tester.pump(const Duration(seconds: 5));
      _expectWork(c, closed: true);
      expect(c.backgroundWorkSnapshot.revision, revision);
      expect(c.frames, [[cmdSyncNextMessage]]);
    });
  }, timeout: timeout);

  testWidgets('accepted fragment continuation replaces the wait for the next request', (tester) async {
    await _withRequest(tester, (c) async {
      await c.syncQueuedMessages();
      _expectWork(c, requests: 1);
      // Только продолжение очереди; FR01 parser/ACK имеют отдельный baseline.
      c.handleQueuedFragmentForTest();
      await tester.pump();
      _expectWork(c, requests: 1);
      expect(c.frames, [[cmdSyncNextMessage], [cmdSyncNextMessage]]);
      c.finishQueue();
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('caller timeout does not release the request or its physical write', (tester) async {
    await _withRequest(tester, (c) async {
      final write = c.holdNextWrite();
      final result = _Result(c.syncQueuedMessages().timeout(const Duration(seconds: 1)));
      await tester.pump(const Duration(seconds: 1));
      expect(result.error, isA<TimeoutException>());
      _expectWork(c, requests: 1, writes: 1);
      write.complete();
      await tester.pump();
      _expectWork(c, requests: 1);
      c.finishQueue();
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('legacy queue abort from a prior write also ends the current logical wait', (tester) async {
    await _withRequest(tester, (c) async {
      final oldWrite = c.holdNextWrite();
      final oldRequest = _Result(c.syncQueuedMessages());
      c.finishQueue();
      await c.syncQueuedMessages();
      _expectWork(c, requests: 1, writes: 1);
      // Старый catch останавливает всю очередь; её поведение здесь не меняется.
      oldWrite.completeError(StateError('synthetic prior write failure'));
      await tester.pump();
      expect(oldRequest.completed, isTrue);
      expect(oldRequest.error, isNull);
      expect(c.isSyncingQueuedMessages, isFalse);
      _expectWork(c);
      expect(c.frames, [[cmdSyncNextMessage], [cmdSyncNextMessage]]);
    });
  }, timeout: timeout);

  testWidgets('disconnected sync creates neither write nor request holding', (tester) async {
    await _withRequest(tester, (c) async {
      c.connected = false;
      await c.syncQueuedMessages();
      _expectWork(c);
      expect(c.frames, isEmpty);
    });
  }, timeout: timeout);
}
