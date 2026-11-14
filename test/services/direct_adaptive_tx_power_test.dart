import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/adaptive_tx_power_settings.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/message_retry_service.dart';

class _Settings extends AppSettingsService {
  _Settings({
    required bool enabled,
    required bool rotateRoutes,
    required int floodRetries,
    required int automaticFloodRetries,
  }) : settings = AppSettings(
        channelMinHopsEnabled: true,
        channelMinHopsRetries: 2,
        autoRouteRotationEnabled: rotateRoutes,
        automaticDirectFloodRetries: automaticFloodRetries,
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
final _recipientKey = Uint8List.fromList(
  List.generate(32, (index) => index + 64),
);
final _time = DateTime.fromMillisecondsSinceEpoch(_timestamp * 1000);

typedef _Send = ({int attempt, bool flood, bool boosted});

class _Retry {
  _Retry({
    int attempts = 2,
    int floodRetries = 0,
    int automaticFloodRetries = 0,
    bool enabled = true,
    bool rotateRoutes = true,
    bool boostConfirmed = true,
    bool withLna = false,
    this.wireText = _text,
  }) : settings = _Settings(
    enabled: enabled,
    rotateRoutes: rotateRoutes,
    floodRetries: floodRetries,
    automaticFloodRetries: automaticFloodRetries,
  ) {
    service.setMaxRetries(attempts);
    service.initialize(RetryServiceConfig(
      appSettingsService: settings,
      getSelfPublicKey: () => _key,
      addMessage: (_, message) => latest = message,
      updateMessage: (message) => latest = message,
      clearContactPath: (_) async {
        contact = contact.copyWith(pathLength: -1, path: Uint8List(0));
      },
      setContactPath: (_, path, hops) async {
        contact = contact.copyWith(pathLength: hops, path: path);
      },
      findContact: (_) => contact,
      selectRetryPath: (_, _, _, _) => nextRoute,
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
        boostRequests.add(attempt);
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
  final String wireText;
  final sends = <_Send>[];
  final packets = <(String, int)>[];
  final routes = <List<int>>[];
  final boostRequests = <int>[];
  final owners = <Object>{};
  late Contact contact;
  PathSelection? nextRoute;
  int releases = 0;
  late Message latest;

  DateTime send(String text, int attempt, int timestamp, {
    required bool flood,
    required bool boosted,
  }) {
    sends.add((attempt: attempt, flood: flood, boosted: boosted));
    packets.add((text, timestamp));
    routes.add(contact.path.toList());
    service.updateMessageFromSent(hash(attempt), 1000, isFlood: flood);
    return _time;
  }

  int hash(int attempt) => MessageRetryService.computeExpectedAckHash(
    _timestamp, attempt, wireText, _key,
  );

  Future<void> start({
    bool forceFlood = false,
    bool hasRoute = true,
    List<int> path = const [0x21],
    int contactType = advTypeChat,
  }) {
    contact = Contact(
      publicKey: _recipientKey,
      name: 'Recipient',
      type: contactType,
      path: hasRoute ? Uint8List.fromList(path) : Uint8List(0),
      pathLength: hasRoute ? path.length : -1,
      pathOverride: forceFlood ? -1 : null,
      lastSeen: _time,
    );
    return service.sendMessageWithRetry(
      contact: contact,
      text: wireText,
      timestamp: _time,
      messageId: 'message',
    );
  }

  void receiveRelayEcho({List<int> remainingPath = const []}) {
    service.handleRxLogFrame(Uint8List.fromList([
      pushCodeLogRxData,
      32,
      186,
      (payloadTypeTXTMSG << 2) | 0x02,
      remainingPath.length,
      ...remainingPath,
      _recipientKey.first,
      _key.first,
      0x41,
      0x42,
    ]));
  }

  void dispose() {
    service.dispose();
    settings.dispose();
  }
}

void main() {
  const ackWait = Duration(seconds: 1);

  testWidgets('automatic Flood adds numbered attempts and boosts only its tail',
      (tester) async {
    final retry = _Retry(automaticFloodRetries: 2, floodRetries: 1, withLna: true);
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
    await tester.pump();
    await tester.pump(ackWait);
    await tester.pump();
    expect(retry.sends.skip(3), [
      (attempt: 2, flood: true, boosted: false),
      (attempt: 3, flood: true, boosted: true),
    ]);
    expect(retry.latest.sendAttemptLimit, 4);
    expect(retry.latest.activeTxBoostWithLna, isTrue);
    expect(retry.packets, everyElement((_text, _timestamp)));
    expect(retry.owners, hasLength(1));
    expect(retry.service.handleAckReceived(retry.hash(3), 10), isNotNull);
    expect(retry.latest.status, MessageStatus.delivered);
    expect(retry.latest.activeTxBoostWithLna, isNull);
    expect(retry.latest.sentWithTxPowerBoost, isTrue);
    expect(retry.latest.sentWithAdaptiveLna, isTrue);
    expect(retry.owners, isEmpty);
    expect(retry.releases, 2);
  });

  testWidgets('rotation replays the same route only when no relay was heard', (
    tester,
  ) async {
    final retry = _Retry(attempts: 3);
    retry.nextRoute = const PathSelection(
      pathBytes: [0x31, 0x32],
      hopCount: 2,
      useFlood: false,
    );
    addTearDown(retry.dispose);
    await retry.start(path: [0x21, 0x22]);
    await tester.pump();

    retry.receiveRelayEcho(remainingPath: [0x23]);
    expect(retry.latest.deliveryProgressCompletedSteps, 0);
    await tester.pump(ackWait);
    expect(retry.sends.last, (attempt: 0, flood: false, boosted: true));
    expect(retry.routes, [[0x21, 0x22], [0x21, 0x22]]);

    await tester.pump(ackWait);
    await tester.pump();
    expect(retry.sends.last, (attempt: 1, flood: false, boosted: false));
    expect(retry.routes.last, [0x31, 0x32]);
    expect(retry.owners, isEmpty);

    retry.receiveRelayEcho(remainingPath: [0x32]);
    expect(retry.latest.deliveryProgressCompletedSteps, 1);
    await tester.pump(ackWait);
    await tester.pump();
    expect(retry.sends.last, (attempt: 2, flood: true, boosted: false));
    expect(retry.sends, hasLength(4));
    expect(retry.service.handleAckReceived(retry.hash(2), 10), isNotNull);
  });

  testWidgets('fixed route uses only its last two numbered retries for boost', (
    tester,
  ) async {
    final retry = _Retry(
      attempts: 5,
      rotateRoutes: false,
      floodRetries: 2,
      automaticFloodRetries: 2,
    );
    addTearDown(retry.dispose);
    await retry.start();
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(ackWait);
      await tester.pump();
    }
    expect(retry.sends, [
      (attempt: 0, flood: false, boosted: false),
      (attempt: 1, flood: false, boosted: false),
      (attempt: 2, flood: false, boosted: true),
      (attempt: 3, flood: false, boosted: true),
      (attempt: 4, flood: true, boosted: false),
      (attempt: 5, flood: true, boosted: true),
      (attempt: 6, flood: true, boosted: true),
    ]);
    expect(retry.routes.take(4), everyElement([0x21]));
    expect(retry.packets, everyElement((_text, _timestamp)));
    expect(
      retry.service.handleAckReceived(retry.hash(6), 10, ackAttemptByte: 6),
      isNotNull,
    );
    expect(retry.latest.sentWithTxPowerBoost, isTrue);
    expect(retry.owners, isEmpty);
  });

  testWidgets('fixed route skips boost after a matching relay echo', (
    tester,
  ) async {
    final retry = _Retry(attempts: 4, rotateRoutes: false, floodRetries: 2);
    addTearDown(retry.dispose);
    await retry.start(path: [0x21, 0x22]);
    await tester.pump();
    retry.receiveRelayEcho(remainingPath: [0x22]);

    await tester.pump(ackWait);
    await tester.pump();
    expect(retry.sends.last, (attempt: 1, flood: false, boosted: false));
    expect(retry.latest.deliveryProgressCompletedSteps, 0);
    // A delayed echo of attempt 0 can't suppress a boost of attempt 2.
    retry.receiveRelayEcho();
    expect(retry.latest.deliveryProgressCompletedSteps, 0);

    await tester.pump(ackWait);
    await tester.pump();
    expect(retry.sends.last, (attempt: 2, flood: false, boosted: true));
    expect(retry.sends, hasLength(3));
    expect(retry.service.handleAckReceived(retry.hash(2), 10), isNotNull);
    expect(retry.owners, isEmpty);
  });

  testWidgets('fixed route sends its retry even if raising TX fails', (
    tester,
  ) async {
    final retry = _Retry(
      attempts: 3,
      rotateRoutes: false,
      floodRetries: 1,
      boostConfirmed: false,
    );
    addTearDown(retry.dispose);
    await retry.start();
    await tester.pump();
    await tester.pump(ackWait);
    await tester.pump();
    expect(retry.sends, [
      (attempt: 0, flood: false, boosted: false),
      (attempt: 1, flood: false, boosted: false),
    ]);
    expect(retry.boostRequests, [1]);
    expect(retry.service.handleAckReceived(retry.hash(1), 10), isNotNull);
    expect(retry.latest.sentWithTxPowerBoost, isFalse);
  });

  testWidgets('direct without a repeater uses numbered attempts without boost', (
    tester,
  ) async {
    final retry = _Retry(attempts: 3, floodRetries: 2);
    addTearDown(retry.dispose);
    await retry.start(path: []);
    await tester.pump();
    await tester.pump(ackWait);
    await tester.pump();
    expect(retry.sends, [
      (attempt: 0, flood: false, boosted: false),
      (attempt: 1, flood: false, boosted: false),
    ]);
    expect(retry.service.handleAckReceived(retry.hash(1), 10), isNotNull);
  });

  testWidgets('forced Flood boosts its last two attempts without adding sends',
      (tester) async {
    final retry = _Retry(attempts: 3, floodRetries: 2, automaticFloodRetries: 5);
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
    expect(retry.latest.sendAttemptLimit, isNull);
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
      expect(retry.latest.activeTxBoostWithLna, boostConfirmed ? true : null);
      expect(retry.latest.sentWithTxPowerBoost, isFalse);
      // A late ACK for the ordinary attempt must not claim the newer boost.
      final ackedAttempt = boostConfirmed ? 0 : 1;
      expect(retry.service.handleAckReceived(retry.hash(ackedAttempt), 10), isNotNull);
      expect(retry.latest.status, MessageStatus.delivered);
      expect(retry.latest.activeTxBoostWithLna, isNull);
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

  testWidgets('automatic Flood adds attempts with boost disabled', (tester) async {
    final retry = _Retry(enabled: false, automaticFloodRetries: 2, floodRetries: 5);
    addTearDown(retry.dispose);
    await retry.start();
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(ackWait);
      await tester.pump();
    }
    expect(retry.sends, [
      (attempt: 0, flood: false, boosted: false),
      (attempt: 1, flood: true, boosted: false),
      (attempt: 2, flood: true, boosted: false),
      (attempt: 3, flood: true, boosted: false),
    ]);
    expect(retry.latest.sendAttemptLimit, 4);
    expect(retry.service.handleAckReceived(retry.hash(2), 10), isNotNull);
    await tester.pump(ackWait);
    expect(retry.sends, hasLength(4));
  });

  testWidgets('Flood power is capped at the extra attempts and keeps its first send ordinary',
      (tester) async {
    final retry = _Retry(automaticFloodRetries: 2, floodRetries: 5);
    addTearDown(retry.dispose);
    await retry.start();
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(ackWait);
      await tester.pump();
    }
    expect(retry.sends.where((send) => send.flood), [
      (attempt: 1, flood: true, boosted: false),
      (attempt: 2, flood: true, boosted: true),
      (attempt: 3, flood: true, boosted: true),
    ]);
    expect(retry.service.handleAckReceived(retry.hash(1), 10), isNotNull);
    expect(retry.latest.sentWithTxPowerBoost, isFalse);
    expect(retry.owners, isEmpty);
  });

  testWidgets('numbered Flood ACK identifies a boosted attempt with a reused hash', (
    tester,
  ) async {
    final retry = _Retry(automaticFloodRetries: 3, floodRetries: 1);
    addTearDown(retry.dispose);
    await retry.start();
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(ackWait);
      await tester.pump();
    }
    expect(retry.sends.where((send) => send.flood), [
      (attempt: 1, flood: true, boosted: false),
      (attempt: 2, flood: true, boosted: false),
      (attempt: 3, flood: true, boosted: false),
      (attempt: 4, flood: true, boosted: true),
    ]);
    expect(retry.hash(4), retry.hash(0));
    expect(
      retry.service.handleAckReceived(retry.hash(4), 10, ackAttemptByte: 4),
      isNotNull,
    );
    expect(retry.latest.sentWithTxPowerBoost, isTrue);
  });

  testWidgets('zero extra attempts sends the automatic Flood once', (tester) async {
    final retry = _Retry(floodRetries: 5);
    addTearDown(retry.dispose);
    await retry.start();
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(ackWait);
      await tester.pump();
    }
    expect(retry.sends.where((send) => send.flood), [
      (attempt: 1, flood: true, boosted: false),
    ]);
    expect(retry.latest.status, MessageStatus.failed);
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('Flood without a route boosts the tail of its ordinary retries',
      (tester) async {
    final retry = _Retry(automaticFloodRetries: 5, floodRetries: 5);
    addTearDown(retry.dispose);
    await retry.start(hasRoute: false);
    await tester.pump();
    await tester.pump(ackWait);
    await tester.pump();
    await tester.pump(ackWait);
    expect(retry.latest.status, MessageStatus.failed);
    expect(retry.latest.activeTxBoostWithLna, isNull);
    expect(retry.latest.sendAttemptLimit, isNull);
    expect(retry.sends, [
      (attempt: 0, flood: true, boosted: false),
      (attempt: 1, flood: true, boosted: true),
    ]);
    expect(retry.owners, isEmpty);
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('room posts keep their ordinary Flood budget', (tester) async {
    final retry = _Retry(enabled: false, automaticFloodRetries: 5);
    addTearDown(retry.dispose);
    await retry.start(contactType: advTypeRoom);
    await tester.pump();
    await tester.pump(ackWait);
    await tester.pump();
    await tester.pump(ackWait);
    expect(retry.latest.status, MessageStatus.failed);
    expect(retry.latest.sendAttemptLimit, isNull);
    expect(retry.sends, [
      (attempt: 0, flood: false, boosted: false),
      (attempt: 1, flood: true, boosted: false),
    ]);
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('long text limits the extra numbered Flood attempts', (tester) async {
    final retry = _Retry(
      attempts: 3,
      enabled: false,
      automaticFloodRetries: 5,
      wireText: 'x' * (maxTextPayloadBytesAfterFullLengthAttempts + 1),
    );
    addTearDown(retry.dispose);
    await retry.start();
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(ackWait);
      await tester.pump();
    }
    expect(retry.latest.status, MessageStatus.failed);
    expect(retry.latest.sendAttemptLimit, 4);
    expect(retry.sends, [
      (attempt: 0, flood: false, boosted: false),
      (attempt: 1, flood: false, boosted: false),
      (attempt: 2, flood: true, boosted: false),
      (attempt: 3, flood: true, boosted: false),
    ]);
    await tester.pump(const Duration(seconds: 61));
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
