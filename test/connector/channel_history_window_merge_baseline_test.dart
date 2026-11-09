import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/reply_target_index.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('U27b baseline: marked posts remain quote targets when off', () async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    addTearDown(PrefsManager.reset);
    await PrefsManager.initialize();

    final channel = _channel(1);
    final messages = _history(1, 2);
    const verdict = FilterVerdict(
      reason: FilterReason.textRule,
      detail: 'Message',
    );
    final original = messages.first.copyWith(filterVerdict: verdict);
    final reply = messages.last.copyWith(
      replyToMessageId: original.messageId,
      replyToText: original.text,
      replyToSenderName: original.senderName,
    );
    connector.setChannelMessagesForTest(channel.index, [original, reply]);

    final transcript = connector.getChannelMessageTimeline(channel);
    expect(transcript.map((message) => message.messageId), ['1:0', '1:1']);
    expect(connector.getChannelMessageTimeline(channel), same(transcript));

    final merged = connector.getChannelMergedMessages(channel);
    final targets = ReplyTargetIndex();
    expect(targets.find(merged, reply.replyToMessageId!), same(original));
    expect(merged.first.filterVerdict, verdict);
    expect(merged.first.text, 'Message 0');

    final restored = original.copyWith(filterVerdict: null);
    connector.setChannelMessagesForTest(channel.index, [restored, reply]);
    expect(connector.getChannelMessageTimeline(channel), isNot(same(transcript)));
    expect(
      targets.find(
        connector.getChannelMergedMessages(channel),
        original.messageId,
      ),
      same(restored),
    );
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
