import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/services/message_retry_service.dart';

const _timestamp = 1700000000;
final _sentAt = DateTime.fromMillisecondsSinceEpoch(_timestamp * 1000);
final _selfKey = Uint8List.fromList(List.generate(32, (i) => i + 1));

Contact _contact(int seed, {bool clearRoute = false}) => Contact(
  publicKey: Uint8List.fromList(List.generate(32, (i) => (seed + i) & 255)),
  name: 'synthetic $seed',
  type: advTypeChat,
  pathLength: clearRoute ? 1 : -1,
  path: clearRoute ? Uint8List.fromList([0xAB]) : Uint8List(0),
  pathOverride: clearRoute ? -1 : null,
  lastSeen: _sentAt,
);

typedef _Send = ({String contactKey, String text, int attempt, bool flood});

// Настоящий retry service и его очереди/таймеры, без connector/native/БД.
// Только callbacks радио/маршрута синтетические. Delivery/SENT fallback здесь
// заданы конфигурацией как 1/5 с; backoff, лимит очереди и ACK grace — исходные.
class _Retry {
  final service = MessageRetryService();
  final latest = <String, Message>{};
  final updates = <Message>[];
  final sends = <_Send>[];
  final heldWrites = <Completer<DateTime?>>[];
  final heldRoutes = <Completer<void>>[];
  Future<DateTime?> Function()? transmit;
  Future<void> Function()? clearRoute;
  int routeClears = 0;
  bool disposed = false;

  _Retry() {
    service.setMaxRetries(2);
    service.initialize(RetryServiceConfig(
      sendMessage: (contact, text, attempt, timestamp, {required useFlood}) {
        sends.add((
          contactKey: contact.publicKeyHex,
          text: text,
          attempt: attempt,
          flood: useFlood,
        ));
        return transmit?.call() ?? Future<DateTime?>.value(_sentAt);
      },
      addMessage: (_, message) => latest[message.messageId] = message,
      updateMessage: (message) {
        latest[message.messageId] = message;
        updates.add(message);
      },
      getSelfPublicKey: () => _selfKey,
      clearContactPath: (_) {
        routeClears++;
        return clearRoute?.call();
      },
      calculateTimeout: (_, _, {contactKey, deviceTimeoutMs}) => 1000,
      calculatePhysicsMaxTimeout: (_, _, _, _) => 5000,
    ));
  }

  Future<void> enqueue(String id, {Contact? contact}) =>
      service.sendMessageWithRetry(
        contact: contact ?? _contact(0x40),
        text: id,
        messageId: id,
        timestamp: _sentAt,
        preparedOutboundText: 'wire:$id',
      );

  int hash(String id, {int attempt = 0}) =>
      MessageRetryService.computeExpectedAckHash(
        _timestamp, attempt, 'wire:$id', _selfKey,
      );

  bool sent(String id, {int attempt = 0}) =>
      service.updateMessageFromSent(hash(id, attempt: attempt), 1000);

  AcknowledgedAttempt? ack(String id, {int attempt = 0}) =>
      service.handleAckReceived(hash(id, attempt: attempt), 100);

  Completer<DateTime?> holdWrite() {
    final completion = Completer<DateTime?>();
    heldWrites.add(completion);
    return completion;
  }

  Completer<void> holdRoute() {
    final completion = Completer<void>();
    heldRoutes.add(completion);
    return completion;
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    service.dispose();
  }
}

Future<void> _withRetry(
  WidgetTester tester,
  Future<void> Function(_Retry h) check,
) async {
  final h = _Retry();
  try {
    await check(h);
  } finally {
    if (!h.disposed) {
      h.service.setSendingPaused(true);
    }
    for (final completion in h.heldWrites) {
      if (!completion.isCompleted) {
        completion.complete(_sentAt);
      }
    }
    for (final completion in h.heldRoutes) {
      if (!completion.isCompleted) {
        completion.complete();
      }
    }
    await tester.pump();
    h.dispose();
    await tester.pump(const Duration(seconds: 61));
  }
}

Future<void> _failAfterTwoAttempts(_Retry h, WidgetTester tester, String id) async {
  expect(h.sent(id), isTrue);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  expect(h.sent(id, attempt: 1), isTrue);
  await tester.pump(const Duration(seconds: 1));
  expect(h.latest[id]!.status, MessageStatus.failed);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(seconds: 30));

  testWidgets('baseline: enqueue returns while the underlying radio callback is pending', (tester) async {
    await _withRetry(tester, (h) async {
      final write = h.holdWrite();
      h.transmit = () => write.future;
      await h.enqueue('a');
      await tester.pump();
      expect(h.sends, hasLength(1));
      expect(write.isCompleted, isFalse);
      expect(h.service.pendingMessageCount.value, 1);
      expect(h.latest['a']!.status, MessageStatus.pending);
      write.complete(_sentAt);
      await tester.pump();
      expect(h.service.pendingMessageCount.value, 1);
      expect(h.latest['a']!.sentByRadioAt, _sentAt);
      expect(h.sent('a'), isTrue);
      expect(h.ack('a')?.messageId, 'a');
      expect(h.service.pendingMessageCount.value, 0);
    });
  }, timeout: timeout);

  testWidgets('baseline: one contact serializes messages and ACK starts the next', (tester) async {
    await _withRetry(tester, (h) async {
      await h.enqueue('a');
      await h.enqueue('b');
      await tester.pump();
      expect(h.sends.map((send) => send.text), ['wire:a']);
      expect(h.service.pendingMessageCount.value, 2);
      expect(h.sent('a'), isTrue);
      expect(h.ack('a')?.messageId, 'a');
      await tester.pump();
      expect(h.sends.map((send) => send.text), ['wire:a', 'wire:b']);
      expect(h.service.pendingMessageCount.value, 1);
      expect(h.sent('b'), isTrue);
      expect(h.ack('b')?.messageId, 'b');
      expect(h.service.hasPendingMessages, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: six global slots leave the seventh contact queued', (tester) async {
    await _withRetry(tester, (h) async {
      for (var i = 0; i < 7; i++) {
        await h.enqueue('m$i', contact: _contact(0x40 + i));
      }
      await tester.pump();
      expect(h.sends, hasLength(6));
      expect(h.service.pendingMessageCount.value, 7);
      expect(h.sent('m0'), isTrue);
      expect(h.ack('m0')?.messageId, 'm0');
      await tester.pump();
      expect(h.sends, hasLength(7));
      expect(h.sends.last.text, 'wire:m6');
      expect(h.service.pendingMessageCount.value, 6);
    });
  }, timeout: timeout);

  testWidgets('baseline: delivery deadline is followed by the original one-second backoff', (tester) async {
    await _withRetry(tester, (h) async {
      await h.enqueue('a');
      await tester.pump();
      expect(h.sent('a'), isTrue);
      await tester.pump(const Duration(milliseconds: 999));
      expect(h.latest['a']!.status, MessageStatus.sent);
      expect(h.sends, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.latest['a']!.retryCount, 1);
      expect(h.latest['a']!.status, MessageStatus.pending);
      await tester.pump(const Duration(milliseconds: 999));
      expect(h.sends, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.sends.map((send) => send.attempt), [0, 1]);
      expect(h.sends.map((send) => send.text), ['wire:a', 'wire:a']);
      expect(h.service.pendingMessageCount.value, 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: failed message remains counted for sixty seconds without more sends', (tester) async {
    await _withRetry(tester, (h) async {
      await h.enqueue('a');
      await tester.pump();
      await _failAfterTwoAttempts(h, tester, 'a');
      expect(h.service.pendingMessageCount.value, 1);
      expect(h.service.hasPendingMessages, isTrue);
      expect(h.service.isTracking('a'), isTrue);
      await tester.pump(const Duration(seconds: 59));
      expect(h.service.pendingMessageCount.value, 1);
      expect(h.sends, hasLength(2));
      await tester.pump(const Duration(seconds: 1));
      expect(h.service.pendingMessageCount.value, 0);
      expect(h.service.hasPendingMessages, isFalse);
      expect(h.sends, hasLength(2));
    });
  }, timeout: timeout);

  testWidgets('baseline: failed slot is reusable and a late ACK can still deliver it', (tester) async {
    await _withRetry(tester, (h) async {
      await h.enqueue('a');
      await tester.pump();
      await _failAfterTwoAttempts(h, tester, 'a');
      await h.enqueue('b');
      await tester.pump();
      expect(h.sends.last.text, 'wire:b');
      expect(h.service.pendingMessageCount.value, 2);
      expect(h.ack('a')?.messageId, 'a');
      expect(h.latest['a']!.status, MessageStatus.delivered);
      expect(h.service.pendingMessageCount.value, 1);
      expect(h.sent('b'), isTrue);
      expect(h.ack('b')?.messageId, 'b');
      expect(h.service.pendingMessageCount.value, 0);
    });
  }, timeout: timeout);

  testWidgets('baseline: paused queue retains messages without sending until resume', (tester) async {
    await _withRetry(tester, (h) async {
      h.service.setSendingPaused(true);
      await h.enqueue('a');
      await tester.pump(const Duration(minutes: 1));
      expect(h.service.pendingMessageCount.value, 1);
      expect(h.sends, isEmpty);
      h.service.setSendingPaused(false);
      await tester.pump();
      expect(h.sends, hasLength(1));
      expect(h.sent('a'), isTrue);
      expect(h.ack('a')?.messageId, 'a');
      expect(h.service.pendingMessageCount.value, 0);
    });
  }, timeout: timeout);

  testWidgets('baseline: resume gives a sent message a full delivery timeout again', (tester) async {
    await _withRetry(tester, (h) async {
      await h.enqueue('a');
      await tester.pump();
      expect(h.sent('a'), isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      h.service.setSendingPaused(true);
      await tester.pump(const Duration(seconds: 10));
      expect(h.sends, hasLength(1));
      h.service.setSendingPaused(false);
      await tester.pump(const Duration(milliseconds: 999));
      expect(h.latest['a']!.status, MessageStatus.sent);
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.latest['a']!.status, MessageStatus.pending);
      expect(h.sends, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(h.sends, hasLength(2));
    });
  }, timeout: timeout);

  testWidgets('baseline: cancellation releases a slot while its old radio Future still runs', (tester) async {
    await _withRetry(tester, (h) async {
      final write = h.holdWrite();
      h.transmit = () => write.future;
      await h.enqueue('a');
      await h.enqueue('b');
      await tester.pump();
      expect(h.sends, hasLength(1));
      h.transmit = null;
      h.service.untrack('a');
      await tester.pump();
      expect(write.isCompleted, isFalse);
      expect(h.sends.map((send) => send.text), ['wire:a', 'wire:b']);
      expect(h.service.pendingMessageCount.value, 1);
      write.complete(_sentAt);
      await tester.pump();
      expect(h.service.isTracking('a'), isFalse);
      expect(h.service.pendingMessageCount.value, 1);
      expect(h.sent('b'), isTrue);
      expect(h.ack('b')?.messageId, 'b');
      expect(h.service.pendingMessageCount.value, 0);
    });
  }, timeout: timeout);

  testWidgets('baseline: pause cancels failed grace cleanup and resume does not rearm it', (tester) async {
    await _withRetry(tester, (h) async {
      await h.enqueue('a');
      await tester.pump();
      await _failAfterTwoAttempts(h, tester, 'a');
      h.service.setSendingPaused(true);
      h.service.setSendingPaused(false);
      await tester.pump(const Duration(seconds: 61));
      expect(h.latest['a']!.status, MessageStatus.failed);
      expect(h.service.pendingMessageCount.value, 1);
      expect(h.sends, hasLength(2));
      expect(h.ack('a')?.messageId, 'a');
      expect(h.latest['a']!.status, MessageStatus.delivered);
      expect(h.service.pendingMessageCount.value, 0);
    });
  }, timeout: timeout);

  testWidgets('baseline: cancellation during awaited route clearing prevents radio TX', (tester) async {
    await _withRetry(tester, (h) async {
      final route = h.holdRoute();
      h.clearRoute = () => route.future;
      await h.enqueue('a', contact: _contact(0x40, clearRoute: true));
      await tester.pump();
      expect(h.routeClears, 1);
      expect(h.sends, isEmpty);
      h.service.untrack('a');
      expect(h.service.pendingMessageCount.value, 0);
      route.complete();
      await tester.pump();
      expect(h.sends, isEmpty);
      expect(h.service.hasPendingMessages, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: dispose does not cancel the underlying radio Future', (tester) async {
    await _withRetry(tester, (h) async {
      final write = h.holdWrite();
      h.transmit = () => write.future;
      await h.enqueue('a');
      await tester.pump();
      final updates = h.updates.length;
      h.dispose();
      expect(h.service.hasPendingMessages, isFalse);
      expect(write.isCompleted, isFalse);
      write.complete(_sentAt);
      await tester.pump(const Duration(seconds: 6));
      expect(h.updates, hasLength(updates));
      expect(h.sends, hasLength(1));
      expect(h.service.hasPendingMessages, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: missing SENT uses configured fallback then the usual backoff', (tester) async {
    await _withRetry(tester, (h) async {
      await h.enqueue('a');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 4999));
      expect(h.sends, hasLength(1));
      expect(h.latest['a']!.retryCount, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.latest['a']!.retryCount, 1);
      await tester.pump(const Duration(milliseconds: 999));
      expect(h.sends, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.sends, hasLength(2));
    });
  }, timeout: timeout);
}
