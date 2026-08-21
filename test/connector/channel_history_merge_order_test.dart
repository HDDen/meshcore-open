import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/channel_message_timeline_helper.dart';
import 'package:meshcore_open/helpers/channel_path_signal_helper.dart';
import 'package:meshcore_open/models/channel_message.dart';

ChannelMessage _message({
  required String id,
  required String sender,
  required String text,
  required DateTime timestamp,
  DateTime? receivedAt,
  required bool outgoing,
}) {
  return ChannelMessage(
    senderName: sender,
    text: text,
    timestamp: timestamp,
    receivedAt: receivedAt,
    isOutgoing: outgoing,
    status: ChannelMessageStatus.sent,
    channelIndex: 0,
    messageId: id,
  );
}

void main() {
  test('channel path observations keep signal readings per route', () {
    final firstPath = Uint8List.fromList([0x01, 0x02]);
    final secondPath = Uint8List.fromList([0x03, 0x04]);
    final first = ChannelMessage(
      senderName: 'Alice',
      text: 'Hello',
      timestamp: DateTime.utc(2026),
      isOutgoing: false,
      pathBytes: firstPath,
      snr: -2.5,
    );
    final second = ChannelMessage(
      senderName: 'Alice',
      text: 'Hello',
      timestamp: DateTime.utc(2026),
      isOutgoing: false,
      pathBytes: secondPath,
      snr: 1.25,
      rssi: -97,
    );

    final merged = ChannelPathSignalHelper.merge(
      first.pathObservations,
      second.pathObservations,
    );

    expect(merged, hasLength(2));
    expect(merged[0].pathBytes, firstPath);
    expect(merged[0].snr, -2.5);
    expect(merged[0].rssi, isNull);
    expect(merged[1].pathBytes, secondPath);
    expect(merged[1].snr, 1.25);
    expect(merged[1].rssi, -97);
  });

  test('same path observations fill missing signal fields', () {
    final path = Uint8List.fromList([0x01, 0x02]);
    final snrOnly = ChannelPathObservation(pathBytes: path, snr: -3.0);
    final rssiOnly = ChannelPathObservation(pathBytes: path, rssi: -110);

    final merged = ChannelPathSignalHelper.merge(
      [snrOnly],
      [rssiOnly],
    );

    expect(merged, hasLength(1));
    expect(merged.single.snr, -3.0);
    expect(merged.single.rssi, -110);
  });

  test('direct channel message exposes signal through primary getters', () {
    final message = ChannelMessage(
      senderName: 'Alice',
      text: 'Direct',
      timestamp: DateTime.utc(2026),
      isOutgoing: false,
      snr: 2.0,
      rssi: -88,
    );

    expect(message.pathBytes, isEmpty);
    expect(message.pathObservations, hasLength(1));
    expect(message.snr, 2.0);
    expect(message.rssi, -88);
  });

  test('shared history merge preserves primary receive order despite skew', () {
    final sent = _message(
      id: 'sent',
      sender: 'Me',
      text: 'Question',
      timestamp: DateTime.utc(2026, 1, 1, 12),
      receivedAt: DateTime.utc(2026, 1, 1, 12, 0, 1),
      outgoing: true,
    );
    final reply = _message(
      id: 'reply',
      sender: 'Alice',
      text: 'Answer',
      // Alice's clock is behind, but the reply was received after `sent`.
      timestamp: DateTime.utc(2026, 1, 1, 11, 59),
      receivedAt: DateTime.utc(2026, 1, 1, 12, 0, 2),
      outgoing: false,
    );
    final secondary = _message(
      id: 'secondary',
      sender: 'Bob',
      text: 'Older shared message',
      timestamp: DateTime.utc(2026, 1, 1, 10),
      receivedAt: DateTime.utc(2026, 1, 1, 12, 0, 0),
      outgoing: false,
    );

    final merged = MeshCoreConnector.mergeChannelMessagesPreservingPrimaryOrder(
      [sent, reply],
      [secondary],
    );

    expect(merged.map((message) => message.messageId), [
      'secondary',
      'sent',
      'reply',
    ]);
  });

  test('timeline ordering ignores sender-controlled packet timestamp', () {
    final firstReceived = _message(
      id: 'future-packet',
      sender: 'Alice',
      text: 'Clock is wrong',
      timestamp: DateTime.utc(2100),
      receivedAt: DateTime.utc(2026, 1, 1, 12),
      outgoing: false,
    );
    final secondReceived = _message(
      id: 'normal-packet',
      sender: 'Bob',
      text: 'Received later',
      timestamp: DateTime.utc(2026, 1, 1, 11),
      receivedAt: DateTime.utc(2026, 1, 1, 12, 0, 1),
      outgoing: false,
    );

    final messages = [secondReceived, firstReceived]
      ..sort(ChannelMessageTimelineHelper.compare);

    expect(messages.map((message) => message.messageId), [
      'future-packet',
      'normal-packet',
    ]);
  });

  test(
    'backlog receive time stays monotonic when local clock does not advance',
    () {
      final previous = DateTime.utc(2026, 1, 1, 12);

      final next = ChannelMessageTimelineHelper.nextBacklogReceivedAt(
        now: previous,
        previous: previous,
      );

      expect(next, previous.add(const Duration(seconds: 1)));
    },
  );

  test('first radio transmission replaces queued time only once', () {
    final queuedAt = DateTime.utc(2026, 1, 1, 12);
    final firstSentAt = queuedAt.add(const Duration(seconds: 15));
    final retryAt = firstSentAt.add(const Duration(minutes: 2));
    final queued = _message(
      id: 'queued',
      sender: 'Me',
      text: 'Delayed',
      timestamp: queuedAt,
      receivedAt: queuedAt,
      outgoing: true,
    );

    final sent = ChannelMessageTimelineHelper.markFirstRadioTransmission(
      queued,
      firstSentAt,
    );
    final retried = ChannelMessageTimelineHelper.markFirstRadioTransmission(
      sent,
      retryAt,
    );

    expect(sent.receivedAt, firstSentAt);
    expect(sent.sentByRadioAt, firstSentAt);
    expect(retried.receivedAt, firstSentAt);
    expect(retried.sentByRadioAt, firstSentAt);
  });

  test('repeat merge timing keeps the earliest physical receipt', () {
    final firstReceivedAt = DateTime.utc(2026, 1, 1, 12);
    final laterReceivedAt = firstReceivedAt.add(const Duration(seconds: 2));
    final insertedFirst = _message(
      id: 'later-completion',
      sender: 'Alice',
      text: 'Same packet',
      timestamp: DateTime.utc(2100),
      receivedAt: laterReceivedAt,
      outgoing: false,
    );
    final completedLater = _message(
      id: 'earlier-receipt',
      sender: 'Alice',
      text: 'Same packet',
      timestamp: DateTime.utc(2100),
      receivedAt: firstReceivedAt,
      outgoing: false,
    );

    final receivedAt = ChannelMessageTimelineHelper.earliestReceivedAt(
      insertedFirst,
      completedLater,
    );

    expect(receivedAt, firstReceivedAt);
  });

  test('self repeat never changes the outgoing transmission time', () {
    final sentAt = DateTime.utc(2026, 1, 1, 12);
    final outgoing = _message(
      id: 'outgoing',
      sender: 'Me',
      text: 'Echo',
      timestamp: sentAt,
      receivedAt: sentAt,
      outgoing: true,
    );
    final echoWithEarlierClock = _message(
      id: 'echo',
      sender: 'Me',
      text: 'Echo',
      timestamp: sentAt,
      receivedAt: sentAt.subtract(const Duration(minutes: 1)),
      outgoing: false,
    );

    final receivedAt = ChannelMessageTimelineHelper.earliestReceivedAt(
      outgoing,
      echoWithEarlierClock,
    );

    expect(receivedAt, sentAt);
  });
}
