import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/services/message_retry_service.dart';

const _timestamp = 1700000000;
final _sentAt = DateTime.fromMillisecondsSinceEpoch(_timestamp * 1000);
final _selfKey = Uint8List.fromList(List.generate(32, (i) => i + 1));

typedef _Observation = ({int hops, int bytes, int tripMs});
typedef _PathResult = ({PathSelection selection, bool success, int? tripMs});

Contact _contact({int width = 1, bool flood = false}) => Contact(
  publicKey: Uint8List.fromList(List.generate(32, (i) => 0x40 + i)),
  name: 'Synthetic recipient',
  type: advTypeChat,
  pathLength: flood ? -1 : 2,
  pathHashWidth: width,
  path: flood
      ? Uint8List(0)
      : Uint8List.fromList(List.generate(width * 2, (i) => 0x10 + i)),
  lastSeen: _sentAt,
);

// Real ACK matching, timers and route selection; only radio callbacks are fake.
// Keep the fork's guarantees green before changing observation attribution.
class _Retry {
  final service = MessageRetryService()..retryBackoffMs = (_) => 0;
  final observations = <_Observation>[];
  final results = <_PathResult>[];
  final sends = <({int attempt, bool flood})>[];
  final wireSends = <({String text, int timestamp})>[];
  late Message latest;
  String text = '';
  String outboundText = '';
  String Function(Contact, String)? prepareOutboundText;

  _Retry() {
    service.setMaxRetries(2);
    service.initialize(RetryServiceConfig(
      sendMessage: (_, wireText, attempt, timestamp, {required useFlood}) async {
        // A retry can run inside tester.pump(). Record callback arguments here
        // and assert them after the awaited scenario, outside the pump guard.
        wireSends.add((text: wireText, timestamp: timestamp));
        sends.add((attempt: attempt, flood: useFlood));
        return _sentAt;
      },
      addMessage: (_, message) => latest = message,
      updateMessage: (message) => latest = message,
      getSelfPublicKey: () => _selfKey,
      prepareContactOutboundText: (contact, body) =>
          prepareOutboundText?.call(contact, body) ?? body,
      clearContactPath: (_) async {},
      selectRetryPath: (_, attempt, maxRetries, recentSelections) =>
          const PathSelection(pathBytes: [], hopCount: -1, useFlood: true),
      calculateTimeout: (_, _, {contactKey, deviceTimeoutMs}) => 1000,
      calculatePhysicsMaxTimeout: (_, _, _, _) => 3000,
      recordPathResult: (_, selection, success, tripMs) => results.add((
        selection: selection,
        success: success,
        tripMs: tripMs,
      )),
      onDeliveryObserved: (_, hops, bytes, tripMs) => observations.add((
        hops: hops,
        bytes: bytes,
        tripMs: tripMs,
      )),
    ));
  }

  Future<void> send(
    Contact contact, {
    String body = 'hello',
    String? preparedText,
  }) async {
    text = body;
    outboundText = preparedText ?? body;
    await service.sendMessageWithRetry(
      contact: contact,
      text: text,
      messageId: 'synthetic-message',
      timestamp: _sentAt,
      preparedOutboundText: preparedText,
    );
  }

  int hash(int attempt) => MessageRetryService.computeExpectedAckHash(
    _timestamp, attempt, outboundText, _selfKey,
  );

  bool confirm(int attempt, {bool flood = false}) =>
      service.updateMessageFromSent(hash(attempt), 1000, isFlood: flood);

  AcknowledgedAttempt? ack(int attempt, {int tripMs = 700}) =>
      service.handleAckReceived(hash(attempt), tripMs);
}

Future<void> _withRetry(
  WidgetTester tester,
  Future<void> Function(_Retry h) check,
) async {
  final h = _Retry();
  try {
    await check(h);
    expect(h.wireSends, isNotEmpty);
    expect(h.wireSends.map((send) => send.text), everyElement(h.outboundText));
    expect(h.wireSends.map((send) => send.timestamp), everyElement(_timestamp));
  } finally {
    h.service.dispose();
    await tester.pump(const Duration(seconds: 61));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(seconds: 30));

  for (final width in [1, 2, 3]) {
    testWidgets('U12a baseline: direct ACK preserves hop count and $width-byte hops',
        (tester) async {
      await _withRetry(tester, (h) async {
        final contact = _contact(width: width);
        await h.send(contact, body: 'hello ёж');
        await tester.pump();
        expect(h.sends, [(attempt: 0, flood: false)]);
        expect(h.confirm(0), isTrue);
        expect(h.observations, isEmpty, reason: 'SENT is not delivery');
        final acknowledged = h.ack(0);
        expect(acknowledged?.selection?.pathBytes, contact.path);
        expect(acknowledged?.selection?.hopCount, 2);
        expect(h.latest.status, MessageStatus.delivered);
        expect(h.results.single.success, isTrue);
        expect(h.results.single.selection.pathBytes, contact.path);
        expect(h.observations, [(
          hops: 2, bytes: utf8.encode(h.text).length, tripMs: 700,
        )]);
      });
    }, timeout: timeout);
  }

  testWidgets('U12a baseline: a flood delivery is a separate observation',
      (tester) async {
    await _withRetry(tester, (h) async {
      await h.send(_contact(flood: true));
      await tester.pump();
      expect(h.sends, [(attempt: 0, flood: true)]);
      expect(h.confirm(0, flood: true), isTrue);
      expect(h.ack(0)?.selection?.useFlood, isTrue);
      expect(h.observations, [(hops: -1, bytes: 5, tripMs: 700)]);
      expect(h.results.single.selection.useFlood, isTrue);
    });
  }, timeout: timeout);

  testWidgets('U12a baseline: a zero RTT delivers without training the model',
      (tester) async {
    await _withRetry(tester, (h) async {
      await h.send(_contact());
      await tester.pump();
      expect(h.confirm(0), isTrue);
      expect(h.ack(0, tripMs: 0), isNotNull);
      expect(h.latest.status, MessageStatus.delivered);
      expect(h.observations, isEmpty);
      expect(h.results.single.success, isTrue);
    });
  }, timeout: timeout);

  testWidgets('U12a baseline: unrelated and duplicate ACKs cannot train twice',
      (tester) async {
    await _withRetry(tester, (h) async {
      await h.send(_contact());
      await tester.pump();
      expect(h.confirm(0), isTrue);
      expect(h.service.handleAckReceived(h.hash(0) ^ 0x80000000, 700), isNull);
      expect(h.observations, isEmpty);
      expect(h.results, isEmpty);
      expect(h.ack(0), isNotNull);
      final observation = h.observations.single;
      expect(h.ack(0), isNull);
      expect(h.observations, [observation]);
      expect(h.results, hasLength(1));
      expect(h.service.isTracking('synthetic-message'), isFalse);
    });
  }, timeout: timeout);

  testWidgets('U12a: late direct ACK trains on its original route',
      (tester) async {
    await _withRetry(tester, (h) async {
      final contact = _contact(width: 2);
      await h.send(contact);
      await tester.pump();
      expect(h.confirm(0), isTrue);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(h.sends, [
        (attempt: 0, flood: false),
        (attempt: 1, flood: true),
      ]);
      expect(h.confirm(1, flood: true), isTrue);
      final acknowledged = h.ack(0);
      expect(acknowledged?.selection?.useFlood, isFalse);
      expect(acknowledged?.selection?.pathBytes, contact.path);
      expect(acknowledged?.selection?.hopCount, 2);
      expect(h.latest.status, MessageStatus.delivered);
      final success = h.results.where((result) => result.success).single;
      expect(success.selection.pathBytes, contact.path);
      expect(success.selection.hopCount, 2);
      // Delivery still credits the first attempt; ML must use that same route.
      expect(h.observations, [(hops: 2, bytes: 5, tripMs: 700)]);
    });
  }, timeout: timeout);

  testWidgets('U12a: node-reported flood overrides the planned route for learning',
      (tester) async {
    await _withRetry(tester, (h) async {
      await h.send(_contact(width: 3));
      await tester.pump();
      expect(h.sends.single.flood, isFalse);
      expect(h.confirm(0, flood: true), isTrue);
      expect(h.ack(0)?.selection?.useFlood, isTrue);
      expect(h.latest.status, MessageStatus.delivered);
      expect(h.observations, [(hops: -1, bytes: 5, tripMs: 700)]);
      expect(h.results.single.selection.useFlood, isTrue);
    });
  }, timeout: timeout);

  testWidgets('U12a: learning keeps the prepared UTF-8 wire text after cleanup',
      (tester) async {
    await _withRetry(tester, (h) async {
      var prepareCalls = 0;
      h.prepareOutboundText = (_, body) {
        prepareCalls++;
        return 'different re-encoded text';
      };
      const wireText = 'prepared signed container ёж';
      await h.send(_contact(), body: 'visible body', preparedText: wireText);
      await tester.pump();
      expect(h.confirm(0), isTrue);
      expect(h.ack(0), isNotNull);
      expect(h.latest.status, MessageStatus.delivered);
      expect(h.service.isTracking('synthetic-message'), isFalse);
      expect(prepareCalls, 0, reason: 'An ACK must not re-encode a prepared payload');
      expect(h.observations, [(
        hops: 2, bytes: utf8.encode(wireText).length, tripMs: 700,
      )]);
    });
  }, timeout: timeout);

  testWidgets('U12a: colliding ACK routes deliver without training', (tester) async {
    await _withRetry(tester, (h) async {
      h.service.setMaxRetries(5);
      await h.send(_contact(width: 2));
      await tester.pump();
      for (var attempt = 0; attempt < 4; attempt++) {
        expect(h.confirm(attempt), isTrue);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(h.sends.last.attempt, attempt + 1);
      }
      expect(h.sends.last.flood, isTrue);
      expect(h.confirm(4, flood: true), isTrue);
      // Firmware hashes attempt & 3: direct attempt 0 and flood attempt 4
      // share a hash. Delivery is certain, its route is not.
      expect(h.hash(0), h.hash(4));
      expect(h.ack(0), isNotNull);
      expect(h.latest.status, MessageStatus.delivered);
      expect(h.results.where((result) => result.success), isEmpty);
      expect(h.observations, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('U12a: a shared ACK hash on the same route can still train',
      (tester) async {
    await _withRetry(tester, (h) async {
      h.service.setMaxRetries(6); // Attempt 4 is direct; attempt 5 would flood.
      await h.send(_contact(width: 3));
      await tester.pump();
      for (var attempt = 0; attempt < 4; attempt++) {
        expect(h.confirm(attempt), isTrue);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(h.sends.last.attempt, attempt + 1);
      }
      expect(h.sends.last.flood, isFalse);
      expect(h.confirm(4), isTrue);
      expect(h.hash(0), h.hash(4));
      expect(h.ack(0)?.selection?.hopCount, 2);
      expect(h.latest.status, MessageStatus.delivered);
      expect(h.observations, [(hops: 2, bytes: 5, tripMs: 700)]);
    });
  }, timeout: timeout);

  testWidgets('U12a: expired route snapshots do not teach the latest guessed route',
      (tester) async {
    await _withRetry(tester, (h) async {
      await h.send(_contact());
      await tester.pump();
      expect(h.confirm(0), isTrue);
      // Pause retains the pending message and expected hashes. pump advances
      // timers, not DateTime.now(), which production uses to prune snapshots.
      // Age only the mapping; let the real ACK handler prune it and fall back.
      h.service.setSendingPaused(true);
      expect(h.service.expectedAcksFor('synthetic-message'), hasLength(1));
      h.service.setAckMappingTimestampForTest(
        h.hash(0),
        DateTime.now().subtract(const Duration(minutes: 16)),
      );
      final acknowledged = h.ack(0);
      expect(acknowledged, isNotNull);
      expect(acknowledged!.selection, isNull);
      expect(h.latest.status, MessageStatus.delivered);
      expect(h.sends, hasLength(1));
      expect(h.observations, isEmpty);
    });
  }, timeout: timeout);
}
