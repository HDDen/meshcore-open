import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';

Channel _channel(int index) =>
    Channel(index: index, name: 'Channel $index', psk: Uint8List(16)..[0] = index + 1);

List<ChannelMessage> _history(int index, int count) => [
  for (var i = 0; i < count; i++)
    ChannelMessage(
      senderName: 'Synthetic sender',
      text: 'Message $i',
      timestamp: DateTime.utc(2026).add(Duration(seconds: i)),
      receivedAt: DateTime.utc(2026).add(Duration(seconds: i)),
      isOutgoing: false,
      channelIndex: index,
      messageId: '$index:$i',
    ),
];

/// Pins RAM-window policy only. Slot/history state is synthetic; reads are
/// side-effect-free and do not start shared-history loads or physical IO.
/// Existing storage tests cover SQL cursor pagination and durable row writes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MeshCoreConnector connector;

  setUp(() {
    connector = MeshCoreConnector();
  });
  tearDown(() {
    connector.dispose();
  });

  test('U10c: memory pressure retains the entire active paged window', () {
    connector.setChannelMessagesForTest(1, _history(1, 1205));
    connector.setActiveChannel(1);
    connector.trimInactiveMessageHistoryWindows();

    final active = connector.getLoadedChannelMessages(_channel(1));
    expect(active, hasLength(1205));
    expect(active.first.messageId, '1:0');
    expect(active.last.messageId, '1:1204');
  });

  test('U10c: leaving a channel keeps the newest 300 messages in RAM', () {
    connector.setChannelMessagesForTest(1, _history(1, 1205));
    connector.setChannelMessagesForTest(2, _history(2, 450));
    connector.setActiveChannel(1);
    connector.setActiveChannel(2);

    final inactive = connector.getLoadedChannelMessages(_channel(1));
    expect(inactive, hasLength(300));
    expect(inactive.first.messageId, '1:905');
    expect(inactive.last.messageId, '1:1204');
    expect(connector.getLoadedChannelMessages(_channel(2)), hasLength(450));
  });

  test('U10c: inactive trimming is bounded and repeated calls are idempotent', () {
    connector.setChannelMessagesForTest(0, _history(0, 7));
    connector.setChannelMessagesForTest(1, _history(1, 1205));
    connector.setChannelMessagesForTest(2, _history(2, 450));
    connector.setActiveChannel(1);
    connector.trimInactiveMessageHistoryWindows();
    final first = connector.getLoadedChannelMessages(_channel(2))
        .map((message) => message.messageId).toList();
    connector.trimInactiveMessageHistoryWindows();

    expect(connector.getLoadedChannelMessages(_channel(0)), hasLength(7));
    expect(connector.getLoadedChannelMessages(_channel(1)), hasLength(1205));
    expect(first, hasLength(300));
    expect(first.first, '2:150');
    expect(first.last, '2:449');
    expect(connector.getLoadedChannelMessages(_channel(2))
        .map((message) => message.messageId), first);

    connector.setActiveChannel(null);
    expect(connector.getLoadedChannelMessages(_channel(1)), hasLength(300));
  });
}
