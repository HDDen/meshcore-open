import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/adaptive_tx_power_settings.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/message_retry_service.dart';

class _Settings extends AppSettingsService {
  _Settings({required bool enabled, int floodRetries = 0})
    : settings = AppSettings(
        channelMinHopsEnabled: true,
        channelMinHopsRetries: 2,
        adaptiveTxPower: AdaptiveTxPowerSettings(
          enabled: true,
          directEnabled: enabled,
          forcedFloodRetries: floodRetries,
          targetDbm: 18,
        ),
      );

  @override
  final AppSettings settings;
}

const _timestamp = 1700000000;
const _text = 'Check the same packet';
final _key = Uint8List.fromList(List.generate(32, (index) => index + 1));
final _time = DateTime.fromMillisecondsSinceEpoch(_timestamp * 1000);

typedef _Send = ({int attempt, bool flood, bool boosted});

class _Retry {
  _Retry({int attempts = 2, int floodRetries = 0, bool enabled = true,
    bool boostConfirmed = true, bool withLna = false})
    : settings = _Settings(enabled: enabled, floodRetries: floodRetries) {
    service.setMaxRetries(attempts);
    service.initialize(RetryServiceConfig(
      appSettingsService: settings,
      getSelfPublicKey: () => _key,
      addMessage: (_, message) => latest = message,
      updateMessage: (message) => latest = message,
      clearContactPath: (_) async {},
      setContactPath: (_, _, _) async {},
      canBoostDirectTxPower: () => true,
      releaseTxPower: (owner) async {
        owners.remove(owner);
        releases++;
      },
      sendMessage: (_, text, attempt, timestamp, {required useFlood}) async =>
          send(text, attempt, timestamp, flood: useFlood, boosted: false),
      sendBoostedMessage: (
        _, text, attempt, timestamp, {
        required useFlood,
        required owner,
        required canSend,
        required sendWithoutBoost,
        required onSendingBoosted,
      }) async {
        if (!canSend()) return null;
        if (!boostConfirmed && !sendWithoutBoost) return null;
        if (boostConfirmed) {
          owners.add(owner);
          onSendingBoosted(withLna);
        }
        return send(text, attempt, timestamp, flood: useFlood, boosted: boostConfirmed);
      },
    ));
  }

  final service = MessageRetryService()..retryBackoffMs = (_) => 0;
  final _Settings settings;
  final sends = <_Send>[];
  final packets = <(String, int)>[];
  final owners = <Object>{};
  int releases = 0;
  late Message latest;

  DateTime send(String text, int attempt, int timestamp, {
    required bool flood,
    required bool boosted,
  }) {
    sends.add((attempt: attempt, flood: flood, boosted: boosted));
    packets.add((text, timestamp));
    service.updateMessageFromSent(hash(attempt), 1000, isFlood: flood);
    return _time;
  }

  int hash(int attempt) => MessageRetryService.computeExpectedAckHash(
    _timestamp, attempt, _text, _key,
  );

  Future<void> start({bool forceFlood = false}) =>
      service.sendMessageWithRetry(
        contact: Contact(
          publicKey: Uint8List.fromList(List.generate(32, (index) => index + 64)),
          name: 'Recipient',
          type: advTypeChat,
          path: Uint8List.fromList([0x21]),
          pathLength: 1,
          pathOverride: forceFlood ? -1 : null,
          lastSeen: _time,
        ),
        text: _text,
        timestamp: _time,
        messageId: 'message',
      );

  void dispose() {
    service.dispose();
    settings.dispose();
  }
}

void main() {
  const ackWait = Duration(seconds: 1);

  testWidgets('one repeat on the route and two repeats on automatic Flood',
      (tester) async {
    final retry = _Retry(withLna: true);
    addTearDown(retry.dispose);
    await retry.start();
    await tester.pump();
    await tester.pump(ackWait);
    expect(retry.sends, [
      (attempt: 0, flood: false, boosted: false),
      (attempt: 0, flood: false, boosted: true),
    ]);
    expect(retry.owners, hasLength(1));

    await tester.pump(ackWait);
    await tester.pump();
    expect(retry.sends.last, (attempt: 1, flood: true, boosted: false));
    expect(retry.owners, isEmpty);
    await tester.pump(ackWait);
    await tester.pump(ackWait);
    expect(retry.sends.skip(3), [
      (attempt: 1, flood: true, boosted: true),
      (attempt: 1, flood: true, boosted: true),
    ]);
    expect(retry.packets, everyElement((_text, _timestamp)));
    expect(retry.owners, hasLength(1));
    expect(retry.service.handleAckReceived(retry.hash(1), 10), isNotNull);
    expect(retry.latest.status, MessageStatus.delivered);
    expect(retry.latest.sentWithTxPowerBoost, isTrue);
    expect(retry.latest.sentWithAdaptiveLna, isTrue);
    expect(retry.owners, isEmpty);
    expect(retry.releases, 2);
  });

  testWidgets('forced Flood boosts its last two attempts without adding sends',
      (tester) async {
    final retry = _Retry(attempts: 3, floodRetries: 2);
    addTearDown(retry.dispose);
    await retry.start(forceFlood: true);
    await tester.pump();
    await tester.pump(ackWait);
    await tester.pump();
    await tester.pump(ackWait);
    await tester.pump();
    expect(retry.sends, [
      (attempt: 0, flood: true, boosted: false),
      (attempt: 1, flood: true, boosted: true),
      (attempt: 2, flood: true, boosted: true),
    ]);
    expect(retry.owners, hasLength(1));
    expect(retry.service.handleAckReceived(retry.hash(2), 10), isNotNull);
    expect(retry.latest.sentWithTxPowerBoost, isTrue);
    expect(retry.latest.sentWithAdaptiveLna, isFalse);
    expect(retry.owners, isEmpty);
  });

  for (final boostConfirmed in [true, false]) {
    testWidgets('only an accepted boost on the acknowledged Flood attempt is marked '
        '(boost confirmed: $boostConfirmed)', (tester) async {
      final retry = _Retry(
        floodRetries: 1, boostConfirmed: boostConfirmed, withLna: true,
      );
      addTearDown(retry.dispose);
      await retry.start(forceFlood: true);
      await tester.pump();
      await tester.pump(ackWait);
      await tester.pump();
      expect(retry.sends.last.boosted, boostConfirmed);
      expect(retry.latest.sentWithTxPowerBoost, isFalse);
      // A late ACK for the ordinary attempt must not claim the newer boost.
      final ackedAttempt = boostConfirmed ? 0 : 1;
      expect(retry.service.handleAckReceived(retry.hash(ackedAttempt), 10), isNotNull);
      expect(retry.latest.status, MessageStatus.delivered);
      expect(retry.latest.sentWithTxPowerBoost, isFalse);
      expect(retry.latest.sentWithAdaptiveLna, isFalse);
    });
  }

  testWidgets('a late ACK stops the route repeat before Flood', (tester) async {
    final retry = _Retry();
    addTearDown(retry.dispose);
    await retry.start();
    await tester.pump();
    await tester.pump(ackWait);
    expect(retry.owners, hasLength(1));
    expect(retry.service.handleAckReceived(retry.hash(0), 10), isNotNull);
    await tester.pump(ackWait);
    expect(retry.sends, hasLength(2));
    expect(retry.owners, isEmpty);
  });

  testWidgets('disabling direct boost preserves the existing attempt plan',
      (tester) async {
    final retry = _Retry(enabled: false);
    addTearDown(retry.dispose);
    await retry.start();
    await tester.pump();
    await tester.pump(ackWait);
    await tester.pump();
    expect(retry.sends, [
      (attempt: 0, flood: false, boosted: false),
      (attempt: 1, flood: true, boosted: false),
    ]);
    expect(retry.service.handleAckReceived(retry.hash(1), 10), isNotNull);
    expect(retry.owners, isEmpty);
  });
}
