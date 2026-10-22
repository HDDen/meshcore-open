import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

// Проверяется настоящий контроль очереди. Callback ниже заменяет разбор и БД;
// реальные direct/channel history paths покрыты queued_message_notifications_test.
class _QueueConnector extends MeshCoreConnector {
  bool connected = true;
  bool saved = false;
  final storedAtRequest = <bool>[];
  final heldProcessing = <Completer<void>>[];

  @override
  bool get isConnected => connected;

  _QueueConnector() {
    setFrameWriterForTest((frame) async {
      if (frame.isNotEmpty && frame.first == cmdSyncNextMessage) {
        storedAtRequest.add(saved);
      }
    });
  }

  Completer<void> holdProcessing() {
    final completion = Completer<void>();
    heldProcessing.add(completion);
    return completion;
  }

  void finishQueue() => handleFrameForTest([respCodeNoMoreMessages]);
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

Future<void> _withQueue(
  WidgetTester tester,
  Future<void> Function(_QueueConnector connector) check,
) async {
  final connector = _QueueConnector();
  try {
    await check(connector);
  } finally {
    // Завершить исходные Futures даже при упавшем expectation.
    connector.connected = false;
    for (final completion in connector.heldProcessing) {
      if (!completion.isCompleted) {
        completion.complete();
      }
    }
    await tester.pump();
    connector.finishQueue();
    connector.dispose();
    await tester.pump();
  }
}

void main() {
  const timeout = Timeout(Duration(seconds: 30));

  testWidgets('baseline: queue waits five seconds without overlapping requests', (tester) async {
    await _withQueue(tester, (c) async {
      await c.syncQueuedMessages();
      expect(c.storedAtRequest, [false]);
      expect(c.isSyncingQueuedMessages, isTrue);

      await c.syncQueuedMessages(force: true);
      c.handleFrameForTest([pushCodeMsgWaiting]);
      await tester.pump(const Duration(milliseconds: 4999));
      expect(c.storedAtRequest, [false]);
      expect(c.isSyncingQueuedMessages, isTrue);

      await tester.pump(const Duration(milliseconds: 1));
      expect(c.isSyncingQueuedMessages, isFalse);
      expect(c.storedAtRequest, [false]);
    });
  }, timeout: timeout);

  testWidgets('baseline: processing outlives the transport deadline and holds tickles', (tester) async {
    await _withQueue(tester, (c) async {
      await c.syncQueuedMessages();
      final held = c.holdProcessing();
      final result = _Result(c.processQueuedMessageForTest(process: () async {
        await held.future;
        c.saved = true;
      }));

      await tester.pump(const Duration(seconds: 6));
      expect(result.completed, isFalse);
      expect(c.isSyncingQueuedMessages, isTrue);
      expect(c.storedAtRequest, [false]);
      await c.syncQueuedMessages(force: true);
      c.handleFrameForTest([pushCodeMsgWaiting]);
      await tester.pump();
      expect(c.storedAtRequest, [false]);

      held.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.storedAtRequest, [false, true]);
      c.finishQueue();
      await tester.pump(const Duration(seconds: 6));
      expect(c.isSyncingQueuedMessages, isFalse);
      expect(c.storedAtRequest, [false, true]);
    });
  }, timeout: timeout);

  for (final synchronous in [true, false]) {
    testWidgets('baseline: processing error stops the queue, synchronous=$synchronous', (tester) async {
      await _withQueue(tester, (c) async {
        await c.syncQueuedMessages();
        final held = c.holdProcessing();
        final failure = StateError('synthetic persistence failure');
        final result = _Result(c.processQueuedMessageForTest(process: () {
          if (synchronous) {
            throw failure;
          }
          return held.future;
        }));
        if (!synchronous) {
          await tester.pump();
          held.completeError(failure);
        }
        await tester.pump();
        expect(result.completed, isTrue);
        expect(result.error, isNull, reason: 'the queued path catches processing errors');
        expect(c.isSyncingQueuedMessages, isFalse);
        expect(c.storedAtRequest, [false]);
        await tester.pump(const Duration(seconds: 6));
        expect(c.storedAtRequest, [false]);

        // Ошибка не создаёт повтор автоматически; новый явный sync разрешён.
        await c.syncQueuedMessages();
        expect(c.storedAtRequest, [false, false]);
        expect(c.isSyncingQueuedMessages, isTrue);
      });
    }, timeout: timeout);
  }

  testWidgets('baseline: connection loss during processing prevents the next request', (tester) async {
    await _withQueue(tester, (c) async {
      await c.syncQueuedMessages();
      final held = c.holdProcessing();
      final result = _Result(c.processQueuedMessageForTest(process: () => held.future));
      await tester.pump();
      c.connected = false;
      held.complete();
      await tester.pump(const Duration(seconds: 6));
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.storedAtRequest, [false]);
    });
  }, timeout: timeout);

  testWidgets('baseline: local processing does not consume the active queue response', (tester) async {
    await _withQueue(tester, (c) async {
      await c.syncQueuedMessages();
      final held = c.holdProcessing();
      final result = _Result(c.processQueuedMessageForTest(
        localSourceLabel: 'synthetic local source',
        process: () => held.future,
      ));
      await tester.pump(const Duration(seconds: 5));
      expect(result.completed, isFalse);
      expect(c.isSyncingQueuedMessages, isFalse);
      expect(c.storedAtRequest, [false]);

      held.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.storedAtRequest, [false]);
    });
  }, timeout: timeout);

  testWidgets('baseline: processing outside a queue awaits completion without requesting', (tester) async {
    await _withQueue(tester, (c) async {
      final held = c.holdProcessing();
      final result = _Result(c.processQueuedMessageForTest(process: () => held.future));
      await tester.pump(const Duration(seconds: 6));
      expect(result.completed, isFalse);
      expect(c.isSyncingQueuedMessages, isFalse);
      expect(c.storedAtRequest, isEmpty);
      held.complete();
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.storedAtRequest, isEmpty);
    });
  }, timeout: timeout);

  for (final synchronous in [true, false]) {
    testWidgets('baseline: outside a queue the original error propagates, synchronous=$synchronous', (tester) async {
      await _withQueue(tester, (c) async {
        final failure = StateError('synthetic processing failure');
        final result = _Result(c.processQueuedMessageForTest(process: () {
          if (synchronous) {
            throw failure;
          }
          return Future<void>.error(failure);
        }));
        await tester.pump();
        expect(result.completed, isTrue);
        expect(result.error, same(failure));
        expect(c.isSyncingQueuedMessages, isFalse);
        expect(c.storedAtRequest, isEmpty);
      });
    }, timeout: timeout);
  }
}
