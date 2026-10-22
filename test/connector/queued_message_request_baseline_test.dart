import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

// Настоящие SYNC_NEXT, timeout и dispatch; подменяется физический writer.
// Этот baseline не проверяет политику CPU и полноту счётчиков активности.
class _RequestConnector extends MeshCoreConnector {
  bool connected = true;
  bool disposed = false;
  final frames = <List<int>>[];
  final heldWrites = <Completer<void>>[];
  Future<void> Function()? write;

  _RequestConnector() {
    setFrameWriterForTest((frame) {
      frames.add(List<int>.of(frame));
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

Future<void> _withRequest(
  WidgetTester tester,
  Future<void> Function(_RequestConnector c) check,
) async {
  final c = _RequestConnector();
  try {
    await check(c);
  } finally {
    c.connected = false;
    for (final completion in c.heldWrites) {
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

  testWidgets(
    'baseline: queue deadline starts before the write finishes',
    (tester) async {
      await _withRequest(tester, (c) async {
        final write = c.holdNextWrite();
        final result = _Result(c.syncQueuedMessages());
        await tester.pump(const Duration(seconds: 4));
        expect(result.completed, isFalse);
        expect(c.isSyncingQueuedMessages, isTrue);
        write.complete();
        await tester.pump();
        expect(result.completed, isTrue);
        expect(result.error, isNull);
        expect(c.isSyncingQueuedMessages, isTrue);

        await tester.pump(const Duration(milliseconds: 999));
        expect(c.isSyncingQueuedMessages, isTrue);
        await tester.pump(const Duration(milliseconds: 1));
        expect(c.isSyncingQueuedMessages, isFalse);
        expect(c.frames, [[cmdSyncNextMessage]]);
      });
    },
    timeout: timeout,
  );

  testWidgets(
    'baseline: write failure stops sync without an automatic retry',
    (tester) async {
      await _withRequest(tester, (c) async {
        final write = c.holdNextWrite();
        final result = _Result(c.syncQueuedMessages());
        await tester.pump();
        write.completeError(StateError('synthetic queue write failure'));
        await tester.pump();
        expect(result.completed, isTrue);
        expect(result.error, isNull, reason: 'the queue catches write failures');
        expect(c.isSyncingQueuedMessages, isFalse);
        await tester.pump(const Duration(seconds: 6));
        expect(c.frames, [[cmdSyncNextMessage]]);

        await c.syncQueuedMessages();
        expect(c.isSyncingQueuedMessages, isTrue);
        expect(c.frames, [[cmdSyncNextMessage], [cmdSyncNextMessage]]);
      });
    },
    timeout: timeout,
  );

  testWidgets(
    'baseline: empty response can precede write completion and a new request',
    (tester) async {
      await _withRequest(tester, (c) async {
        final oldWrite = c.holdNextWrite();
        final oldRequest = _Result(c.syncQueuedMessages());
        await tester.pump();
        c.finishQueue();
        expect(c.isSyncingQueuedMessages, isFalse);
        expect(oldRequest.completed, isFalse);

        await c.syncQueuedMessages();
        expect(c.isSyncingQueuedMessages, isTrue);
        oldWrite.complete();
        await tester.pump();
        expect(oldRequest.completed, isTrue);
        expect(oldRequest.error, isNull);
        expect(c.isSyncingQueuedMessages, isTrue);
        expect(c.frames, [[cmdSyncNextMessage], [cmdSyncNextMessage]]);

        c.finishQueue();
        await tester.pump(const Duration(seconds: 6));
        expect(c.isSyncingQueuedMessages, isFalse);
        expect(c.frames, [[cmdSyncNextMessage], [cmdSyncNextMessage]]);
      });
    },
    timeout: timeout,
  );

  testWidgets(
    'baseline: write timeout does not wait for the physical write or retry',
    (tester) async {
      await _withRequest(tester, (c) async {
        final oldWrite = c.holdNextWrite();
        final oldRequest = _Result(c.syncQueuedMessages());
        await tester.pump(const Duration(seconds: 5));
        expect(oldRequest.completed, isTrue);
        expect(oldRequest.error, isNull);
        expect(oldWrite.isCompleted, isFalse);
        expect(c.isSyncingQueuedMessages, isFalse);
        expect(c.frames, [[cmdSyncNextMessage]]);

        await c.syncQueuedMessages();
        expect(c.isSyncingQueuedMessages, isTrue);
        oldWrite.complete();
        await tester.pump();
        expect(c.isSyncingQueuedMessages, isTrue);
        expect(c.frames, [[cmdSyncNextMessage], [cmdSyncNextMessage]]);
      });
    },
    timeout: timeout,
  );

  testWidgets(
    'baseline: sync reset cancels the queue wait while the write is pending',
    (tester) async {
      await _withRequest(tester, (c) async {
        final write = c.holdNextWrite();
        final result = _Result(c.syncQueuedMessages());
        await tester.pump();
        c.resetSyncProgressForTest();
        expect(c.isSyncingQueuedMessages, isFalse);
        expect(result.completed, isFalse);
        write.complete();
        await tester.pump();
        expect(result.completed, isTrue);
        expect(result.error, isNull);
        await tester.pump(const Duration(seconds: 6));
        expect(c.isSyncingQueuedMessages, isFalse);
        expect(c.frames, [[cmdSyncNextMessage]]);
      });
    },
    timeout: timeout,
  );

  for (final response in [respCodeOk, respCodeErr]) {
    testWidgets('baseline: generic response $response does not end a queue wait', (tester) async {
      await _withRequest(tester, (c) async {
        await c.syncQueuedMessages();
        c.handleFrameForTest([response]);
        await tester.pump(const Duration(milliseconds: 4999));
        expect(c.isSyncingQueuedMessages, isTrue);
        await tester.pump(const Duration(milliseconds: 1));
        expect(c.isSyncingQueuedMessages, isFalse);
        expect(c.frames, [[cmdSyncNextMessage]]);
      });
    }, timeout: timeout);
  }

  testWidgets('baseline: dispose does not create another queue request', (tester) async {
    await _withRequest(tester, (c) async {
      await c.syncQueuedMessages();
      c.dispose();
      await tester.pump(const Duration(seconds: 6));
      expect(c.isSyncingQueuedMessages, isFalse);
      expect(c.frames, [[cmdSyncNextMessage]]);
    });
  }, timeout: timeout);

  testWidgets('baseline: a disconnected connector sends no queue request', (tester) async {
    await _withRequest(tester, (c) async {
      c.connected = false;
      await c.syncQueuedMessages();
      expect(c.frames, isEmpty);
      expect(c.isSyncingQueuedMessages, isFalse);
    });
  }, timeout: timeout);
}
