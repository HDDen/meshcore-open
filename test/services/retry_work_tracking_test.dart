import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
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
  final tracker = BackgroundWorkTracker();
  late final RetryServiceConfig config;
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
    config = RetryServiceConfig(
      backgroundWorkTracker: tracker,
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
    );
    service.initialize(config);
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

void _expectWork(_Retry h, int count) {
  final snapshot = h.tracker.snapshot;
  expect(snapshot.countFor(BackgroundWorkKind.retry), count);
  expect(snapshot.activeCount, count);
  expect(snapshot.isBusy, count > 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(seconds: 30));

  testWidgets('logical request and unfinished radio attempt are separate retry holds', (tester) async {
    await _withRetry(tester, (h) async {
      final write = h.holdWrite();
      h.transmit = () => write.future;
      await h.enqueue('a');
      await tester.pump();
      _expectWork(h, 2);
      write.complete(_sentAt);
      await tester.pump();
      _expectWork(h, 1);
      expect(h.sent('a'), isTrue);
      _expectWork(h, 1);
      expect(h.ack('a')?.messageId, 'a');
      _expectWork(h, 0);
    });
  }, timeout: timeout);

  testWidgets('queued message is already held when ACK hands over the contact slot', (tester) async {
    await _withRetry(tester, (h) async {
      await h.enqueue('a');
      await h.enqueue('b');
      await tester.pump();
      _expectWork(h, 2);
      expect(h.sends, hasLength(1));
      expect(h.sent('a'), isTrue);
      expect(h.ack('a')?.messageId, 'a');
      await tester.pump();
      _expectWork(h, 1);
      expect(h.sends.last.text, 'wire:b');
      expect(h.sent('b'), isTrue);
      expect(h.ack('b')?.messageId, 'b');
      _expectWork(h, 0);
    });
  }, timeout: timeout);

  testWidgets('global queue counts waiting messages beyond the six active slots', (tester) async {
    await _withRetry(tester, (h) async {
      for (var i = 0; i < 7; i++) {
        await h.enqueue('m$i', contact: _contact(0x40 + i));
      }
      await tester.pump();
      expect(h.sends, hasLength(6));
      _expectWork(h, 7);
      expect(h.sent('m0'), isTrue);
      expect(h.ack('m0')?.messageId, 'm0');
      await tester.pump();
      _expectWork(h, 6);
      expect(h.sends.last.text, 'wire:m6');
    });
  }, timeout: timeout);

  testWidgets('ACK timeout and the unchanged backoff retain the logical wait', (tester) async {
    await _withRetry(tester, (h) async {
      await h.enqueue('a');
      await tester.pump();
      expect(h.sent('a'), isTrue);
      _expectWork(h, 1);
      await tester.pump(const Duration(seconds: 1));
      _expectWork(h, 1);
      expect(h.latest['a']!.retryCount, 1);
      await tester.pump(const Duration(milliseconds: 999));
      _expectWork(h, 1);
      expect(h.sends, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      _expectWork(h, 1);
      expect(h.sends.map((send) => send.attempt), [0, 1]);
    });
  }, timeout: timeout);

  testWidgets('failed grace remains matchable without any retry hold', (tester) async {
    await _withRetry(tester, (h) async {
      await h.enqueue('a');
      await tester.pump();
      await _failAfterTwoAttempts(h, tester, 'a');
      _expectWork(h, 0);
      expect(h.service.pendingMessageCount.value, 1);
      await tester.pump(const Duration(seconds: 59));
      _expectWork(h, 0);
      expect(h.service.pendingMessageCount.value, 1);
      await tester.pump(const Duration(seconds: 1));
      _expectWork(h, 0);
      expect(h.service.pendingMessageCount.value, 0);
    });
  }, timeout: timeout);

  testWidgets('late ACK of failed message does not release a different pending message', (tester) async {
    await _withRetry(tester, (h) async {
      await h.enqueue('a');
      await tester.pump();
      await _failAfterTwoAttempts(h, tester, 'a');
      await h.enqueue('b');
      await tester.pump();
      _expectWork(h, 1);
      expect(h.service.pendingMessageCount.value, 2);
      expect(h.ack('a')?.messageId, 'a');
      _expectWork(h, 1);
      expect(h.service.pendingMessageCount.value, 1);
      expect(h.sent('b'), isTrue);
      expect(h.ack('b')?.messageId, 'b');
      _expectWork(h, 0);
    });
  }, timeout: timeout);

  testWidgets('pause releases waiting queue and resume restores it without duplicates', (tester) async {
    await _withRetry(tester, (h) async {
      h.service.setSendingPaused(true);
      await h.enqueue('a');
      await h.enqueue('b');
      await tester.pump(const Duration(minutes: 1));
      _expectWork(h, 0);
      expect(h.service.pendingMessageCount.value, 2);
      expect(h.sends, isEmpty);
      h.service.setSendingPaused(false);
      await tester.pump();
      _expectWork(h, 2);
      final revision = h.tracker.revision;
      h.service.setSendingPaused(false);
      h.service.initialize(h.config);
      expect(h.tracker.revision, revision);
      _expectWork(h, 2);
    });
  }, timeout: timeout);

  testWidgets('pause retains unfinished attempt and its old completion cannot finish resumed wait', (tester) async {
    await _withRetry(tester, (h) async {
      final write = h.holdWrite();
      h.transmit = () => write.future;
      await h.enqueue('a');
      await tester.pump();
      _expectWork(h, 2);
      h.service.setSendingPaused(true);
      _expectWork(h, 1);
      h.transmit = null;
      h.service.setSendingPaused(false);
      await tester.pump();
      _expectWork(h, 2); // Новое ожидание и прежний незавершённый Future.
      write.complete(_sentAt);
      await tester.pump();
      _expectWork(h, 1);
      expect(h.sent('a'), isTrue);
      expect(h.ack('a')?.messageId, 'a');
      _expectWork(h, 0);
    });
  }, timeout: timeout);

  testWidgets('paused failed grace and reinitialization do not create a logical hold', (tester) async {
    await _withRetry(tester, (h) async {
      await h.enqueue('a');
      await tester.pump();
      await _failAfterTwoAttempts(h, tester, 'a');
      h.service.setSendingPaused(true);
      h.service.setSendingPaused(false);
      h.service.initialize(h.config);
      await tester.pump(const Duration(seconds: 61));
      expect(h.service.pendingMessageCount.value, 1);
      _expectWork(h, 0);
      expect(h.ack('a')?.messageId, 'a');
      expect(h.latest['a']!.status, MessageStatus.delivered);
      _expectWork(h, 0);
    });
  }, timeout: timeout);

  testWidgets('cancelled radio Future remains held without releasing the next message', (tester) async {
    await _withRetry(tester, (h) async {
      final write = h.holdWrite();
      h.transmit = () => write.future;
      await h.enqueue('a');
      await tester.pump();
      h.service.untrack('a');
      _expectWork(h, 1);
      h.transmit = null;
      await h.enqueue('b');
      await tester.pump();
      _expectWork(h, 2);
      write.complete(_sentAt);
      await tester.pump();
      _expectWork(h, 1);
      expect(h.service.isTracking('a'), isFalse);
      expect(h.sent('b'), isTrue);
      expect(h.ack('b')?.messageId, 'b');
      _expectWork(h, 0);
    });
  }, timeout: timeout);

  testWidgets('cancel during route clearing retains actual work until the callback ends', (tester) async {
    await _withRetry(tester, (h) async {
      final route = h.holdRoute();
      h.clearRoute = () => route.future;
      await h.enqueue('a', contact: _contact(0x40, clearRoute: true));
      await tester.pump();
      _expectWork(h, 2);
      h.service.untrack('a');
      _expectWork(h, 1);
      route.complete();
      await tester.pump();
      _expectWork(h, 0);
      expect(h.sends, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('service dispose and tracker close preserve the unfinished radio attempt', (tester) async {
    await _withRetry(tester, (h) async {
      final write = h.holdWrite();
      h.transmit = () => write.future;
      await h.enqueue('a');
      await tester.pump();
      _expectWork(h, 2);
      h.dispose();
      _expectWork(h, 1);
      expect(h.tracker.isClosed, isFalse);
      h.tracker.close();
      _expectWork(h, 1);
      write.complete(_sentAt);
      await tester.pump(const Duration(seconds: 6));
      _expectWork(h, 0);
      expect(h.service.hasPendingMessages, isFalse);
    });
  }, timeout: timeout);

  testWidgets('attempt failure releases actual work and the failed logical request', (tester) async {
    await _withRetry(tester, (h) async {
      final write = h.holdWrite();
      h.transmit = () => write.future;
      await h.enqueue('a');
      await tester.pump();
      _expectWork(h, 2);
      write.completeError(StateError('synthetic retry radio failure'));
      await tester.pump();
      _expectWork(h, 0);
      expect(h.latest['a']!.status, MessageStatus.failed);
      expect(h.service.pendingMessageCount.value, 0);
    });
  }, timeout: timeout);

  testWidgets('missing SENT fallback leaves the logical hold through retry backoff', (tester) async {
    await _withRetry(tester, (h) async {
      await h.enqueue('a');
      await tester.pump();
      _expectWork(h, 1);
      await tester.pump(const Duration(seconds: 5));
      _expectWork(h, 1);
      expect(h.latest['a']!.retryCount, 1);
      await tester.pump(const Duration(seconds: 1));
      _expectWork(h, 1);
      expect(h.sends, hasLength(2));
    });
  }, timeout: timeout);
}

