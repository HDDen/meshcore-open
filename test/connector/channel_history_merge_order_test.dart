import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
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
}
