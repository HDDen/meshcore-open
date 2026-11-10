import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/services/message_retry_service.dart';

const _timestamp = 1700000000;
const _messageId = 'watchdog-message';
const _wireText = 'wire:hello';
final _sentAt = DateTime.fromMillisecondsSinceEpoch(_timestamp * 1000);
final _selfKey = Uint8List.fromList(List.generate(32, (i) => i + 1));

typedef _Observation = ({int hops, int bytes, int tripMs});
typedef _Result = ({PathSelection path, bool success});

Contact _contact({bool direct = false}) => Contact(
  publicKey: Uint8List.fromList(List.generate(32, (i) => 0x40 + i)),
  name: 'Synthetic recipient',
  type: advTypeChat,
  pathLength: direct ? 2 : -1,
  pathHashWidth: 2,
  path: direct ? Uint8List.fromList([0x11, 0x22, 0x33, 0x44]) : Uint8List(0),
  lastSeen: _sentAt,
);

// Adapted from the upstream watchdog cases to the fork's actual callback API.
// Use virtual timers, not wall-clock sleeps. Radio callbacks only collect data.
class _Watchdog {
  final service = MessageRetryService();
  final tracker = BackgroundWorkTracker();
  final sends = <({int attempt, bool flood, String text})>[];
  final observations = <_Observation>[];
  final results = <_Result>[];
  late Message latest;
  int deliveryTimeoutMs = 1000;
  Completer<DateTime?>? heldWrite;

  _Watchdog() {
    service.setMaxRetries(2);
    service.initialize(RetryServiceConfig(
      backgroundWorkTracker: tracker,
      sendMessage: (_, text, attempt, timestamp, {required useFlood}) {
        sends.add((attempt: attempt, flood: useFlood, text: text));
        return heldWrite?.future ?? Future<DateTime?>.value(_sentAt);
      },
      addMessage: (_, message) => latest = message,
      updateMessage: (message) => latest = message,
      getSelfPublicKey: () => _selfKey,
      clearContactPath: (_) async {},
      calculateTimeout: (_, _, {contactKey, deviceTimeoutMs}) => deliveryTimeoutMs,
      // The existing service uses this bound as its missing-SENT fallback.
      calculatePhysicsMaxTimeout: (_, _, _, _) => 5000,
      recordPathResult: (_, path, success, tripMs) =>
          results.add((path: path, success: success)),
      onDeliveryObserved: (_, hops, bytes, tripMs) =>
          observations.add((hops: hops, bytes: bytes, tripMs: tripMs)),
    ));
  }

  Future<void> send({bool direct = false}) => service.sendMessageWithRetry(
    contact: _contact(direct: direct),
    text: 'hello',
    messageId: _messageId,
    timestamp: _sentAt,
    preparedOutboundText: _wireText,
  );

  int hash(int attempt) => MessageRetryService.computeExpectedAckHash(
    _timestamp, attempt, _wireText, _selfKey,
  );

  bool sent(int attempt, {bool flood = true}) =>
      service.updateMessageFromSent(hash(attempt), deliveryTimeoutMs, isFlood: flood);

  AcknowledgedAttempt? ack(int attempt, {int? attemptByte}) =>
      service.handleAckReceived(hash(attempt), 700, ackAttemptByte: attemptByte);
}

void _expectReleased(_Watchdog h) {
  expect(h.service.hasPendingMessages, isFalse);
  expect(h.tracker.snapshot.countFor(BackgroundWorkKind.retry), 0);
  expect(h.tracker.snapshot.activeCount, 0);
}

void _expectUnconfirmedRoute(_Watchdog h) {
  expect(h.observations, isEmpty,
      reason: 'A missing SENT leaves the actual node route unconfirmed');
  expect(h.results.where((result) => result.success), isEmpty);
}

Future<void> _withWatchdog(
  WidgetTester tester,
  Future<void> Function(_Watchdog h) check,
) async {
  final h = _Watchdog();
  try {
    await check(h);
    expect(h.sends.map((send) => send.text), everyElement(_wireText));
  } finally {
    h.service.dispose();
    final held = h.heldWrite;
    if (held != null && !held.isCompleted) held.complete(_sentAt);
    await tester.pump();
    await tester.pump(const Duration(seconds: 61));
    expect(h.tracker.snapshot.activeCount, 0);
    h.tracker.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(seconds: 30));

  testWidgets('watchdog: missing SENT uses its fallback and the normal backoff', (tester) async {
    await _withWatchdog(tester, (h) async {
      await h.send();
      await tester.pump();
      expect(h.sends.map((send) => send.attempt), [0]);
      await tester.pump(const Duration(milliseconds: 4999));
      expect(h.latest.retryCount, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.latest.retryCount, 1);
      expect(h.sends, hasLength(1));
      await tester.pump(const Duration(milliseconds: 999));
      expect(h.sends, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.sends.map((send) => send.attempt), [0, 1]);
      expect(h.tracker.snapshot.countFor(BackgroundWorkKind.retry), 1);
    });
  }, timeout: timeout);

  testWidgets('watchdog: SENT replaces the fallback without a second retry', (tester) async {
    await _withWatchdog(tester, (h) async {
      await h.send();
      await tester.pump();
      h.deliveryTimeoutMs = 20000;
      expect(h.sent(0), isTrue);
      await tester.pump(const Duration(milliseconds: 5001));
      expect(h.sends, hasLength(1));
      expect(h.latest.status, MessageStatus.sent);
      expect(h.ack(0), isNotNull);
      expect(h.latest.status, MessageStatus.delivered);
      expect(h.observations, [(hops: -1, bytes: _wireText.length, tripMs: 700)]);
      _expectReleased(h);
      await tester.pump(const Duration(seconds: 21));
      expect(h.sends, hasLength(1));
    });
  }, timeout: timeout);

  testWidgets('watchdog: ACK after lost SENT cancels the scheduled backoff', (tester) async {
    await _withWatchdog(tester, (h) async {
      await h.send(direct: true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(h.latest.retryCount, 1);
      expect(h.sends, hasLength(1));
      expect(h.ack(0), isNotNull);
      expect(h.latest.status, MessageStatus.delivered);
      _expectReleased(h);
      _expectUnconfirmedRoute(h);
      await tester.pump(const Duration(seconds: 2));
      expect(h.sends, hasLength(1), reason: 'The queued retry must be cancelled');
    });
  }, timeout: timeout);

  testWidgets('watchdog: late direct ACK after flood still teaches the direct route', (tester) async {
    await _withWatchdog(tester, (h) async {
      await h.send(direct: true);
      await tester.pump();
      expect(h.sent(0, flood: false), isTrue);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(h.sends.map((send) => send.attempt), [0, 1]);
      expect(h.sends.last.flood, isTrue);
      expect(h.sent(1), isTrue);
      final acknowledged = h.ack(0);
      expect(acknowledged?.selection?.pathBytes, [0x11, 0x22, 0x33, 0x44]);
      expect(acknowledged?.selection?.hopCount, 2);
      expect(h.latest.status, MessageStatus.delivered);
      expect(h.observations, [(hops: 2, bytes: _wireText.length, tripMs: 700)]);
      _expectReleased(h);
    });
  }, timeout: timeout);

  testWidgets('U34: a lost SENT cannot charge a route after a flood ACK', (tester) async {
    await _withWatchdog(tester, (h) async {
      await h.send(direct: true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(h.sends.last.attempt, 1);
      expect(h.sends.last.flood, isTrue);
      expect(h.sent(1), isTrue);
      expect(h.ack(1), isNotNull);
      expect(h.results.single.success, isTrue);
      expect(h.results.single.path.useFlood, isTrue);
      _expectReleased(h);
    });
  }, timeout: timeout);

  testWidgets('U34: a reported flood timeout goes into flood statistics', (tester) async {
    await _withWatchdog(tester, (h) async {
      await h.send(direct: true);
      await tester.pump();
      expect(h.sends.single.flood, isFalse);
      expect(h.sent(0, flood: true), isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(h.results.single.path.useFlood, isTrue);
      expect(h.results.single.success, isFalse);

      expect(h.ack(0)?.selection?.useFlood, isTrue);
      expect(h.latest.status, MessageStatus.delivered);
      _expectReleased(h);
    });
  }, timeout: timeout);

  testWidgets('U34: a flood ACK during grace commits the route timeout', (tester) async {
    await _withWatchdog(tester, (h) async {
      await h.send(direct: true);
      await tester.pump();
      expect(h.sent(0, flood: false), isTrue);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(h.sends.last.attempt, 1);
      expect(h.sent(1), isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(h.latest.status, MessageStatus.failed);
      expect(h.results.single.path.useFlood, isTrue);
      expect(h.results.single.success, isFalse);

      expect(h.ack(1), isNotNull);
      expect(h.latest.status, MessageStatus.delivered);
      expect(
        h.results.map((result) => (result.path.useFlood, result.success)),
        [(true, false), (false, false), (true, true)],
      );
      expect(h.results[1].path.pathBytes, [0x11, 0x22, 0x33, 0x44]);
      expect(h.ack(1), isNull);
      expect(h.results, hasLength(3));
      _expectReleased(h);
    });
  }, timeout: timeout);

  testWidgets('watchdog: a valid ACK before missing-SENT fallback delivers once', (tester) async {
    await _withWatchdog(tester, (h) async {
      await h.send(direct: true);
      await tester.pump();
      expect(h.ack(0), isNotNull);
      expect(h.latest.status, MessageStatus.delivered);
      _expectReleased(h);
      _expectUnconfirmedRoute(h);
      expect(h.ack(0), isNull, reason: 'A duplicate must not resolve twice');
      await tester.pump(const Duration(seconds: 7));
      expect(h.sends, hasLength(1));
    });
  }, timeout: timeout);

  testWidgets('watchdog: a foreign hash cannot deliver while SENT is missing', (tester) async {
    await _withWatchdog(tester, (h) async {
      await h.send();
      await tester.pump();
      expect(h.service.handleAckReceived(h.hash(0) ^ 0x80000000, 700), isNull);
      expect(h.latest.status, MessageStatus.pending);
      expect(h.service.isTracking(_messageId), isTrue);
      expect(h.tracker.snapshot.countFor(BackgroundWorkKind.retry), 1);
      _expectUnconfirmedRoute(h);
    });
  }, timeout: timeout);

  testWidgets('watchdog: a cancelled send cannot be revived by an unconfirmed ACK', (tester) async {
    await _withWatchdog(tester, (h) async {
      await h.send();
      await tester.pump();
      h.service.untrack(_messageId);
      expect(h.ack(0), isNull);
      _expectReleased(h);
      _expectUnconfirmedRoute(h);
    });
  }, timeout: timeout);

  testWidgets('watchdog: lost-SENT ACK can deliver during failed-message grace', (tester) async {
    await _withWatchdog(tester, (h) async {
      await h.send();
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(h.sends.map((send) => send.attempt), [0, 1]);
      await tester.pump(const Duration(seconds: 5));
      expect(h.latest.status, MessageStatus.failed);
      expect(h.tracker.snapshot.activeCount, 0);
      expect(h.ack(0), isNotNull);
      expect(h.latest.status, MessageStatus.delivered);
      _expectReleased(h);
      _expectUnconfirmedRoute(h);
    });
  }, timeout: timeout);

  testWidgets('watchdog: ACK releases the wait but keeps unfinished I/O held', (tester) async {
    await _withWatchdog(tester, (h) async {
      final write = Completer<DateTime?>();
      h.heldWrite = write;
      await h.send(direct: true);
      await tester.pump();
      expect(h.tracker.snapshot.countFor(BackgroundWorkKind.retry), 2);
      expect(h.ack(0), isNotNull);
      expect(h.latest.status, MessageStatus.delivered);
      expect(h.service.hasPendingMessages, isFalse);
      // The actual radio callback still awaits its SENT/timeout. Releasing
      // the logical ACK wait must not release that protected operation early.
      expect(h.tracker.snapshot.countFor(BackgroundWorkKind.retry), 1);
      _expectUnconfirmedRoute(h);
      write.complete(_sentAt);
      await tester.pump();
      _expectReleased(h);
      expect(h.sent(0, flood: false), isFalse, reason: 'Late SENT cannot revive delivery');
      expect(h.latest.status, MessageStatus.delivered);
      expect(h.sends, hasLength(1));
    });
  }, timeout: timeout);

  for (final lostFirst in [false, true]) {
    for (final explicitByte in [false, true]) {
      testWidgets('watchdog: shared hash with lost SENT (first=$lostFirst, byte=$explicitByte)',
          (tester) async {
        await _withWatchdog(tester, (h) async {
          h.service.setMaxRetries(5);
          await h.send(direct: true);
          await tester.pump();
          for (var attempt = 0; attempt < 4; attempt++) {
            if (attempt == 0 && lostFirst) {
              // First attempt has no SENT, so its fallback is five seconds.
              await tester.pump(const Duration(seconds: 5));
            } else {
              expect(h.sent(attempt, flood: false), isTrue);
              await tester.pump(const Duration(seconds: 1));
            }
            // Preserve the real exponential backoff: 1, 2, 4, 8 seconds.
            await tester.pump(Duration(seconds: 1 << attempt));
            expect(h.sends.last.attempt, attempt + 1);
          }
          expect(h.sends.last.flood, isTrue);
          if (lostFirst) {
            // A later SENT must not erase the earlier unconfirmed attempt 0.
            expect(h.sent(4), isTrue);
          }
          // Otherwise attempt 0 was confirmed but attempt 4 lost its SENT.
          expect(h.hash(0), h.hash(4));
          final confirmedAttempt = lostFirst ? 4 : 0;
          final acknowledged = h.ack(0,
              attemptByte: explicitByte ? confirmedAttempt : null);
          expect(acknowledged, isNotNull);
          expect(h.latest.status, MessageStatus.delivered);
          if (explicitByte) {
            // A byte naming the confirmed candidate preserves accurate routing
            // even though another attempt with this hash lost its SENT.
            expect(acknowledged!.selection?.useFlood, lostFirst);
            expect(h.observations, [(
              hops: lostFirst ? -1 : 2, bytes: _wireText.length, tripMs: 700,
            )]);
            expect(h.results.where((result) => result.success), hasLength(1));
            expect(h.results.where((result) => !result.success), hasLength(3));
          } else {
            expect(acknowledged!.selection, isNull);
            _expectUnconfirmedRoute(h);
            expect(h.results, isEmpty);
          }
          _expectReleased(h);
        });
      }, timeout: timeout);
    }
  }
}
