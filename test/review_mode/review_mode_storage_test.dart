import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/review_mode/review_mode_storage.dart';
import 'package:meshcore_open/review_mode/review_radio.dart';
import 'package:meshcore_open/storage/channel_message_store.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/message_store.dart';

import '../support/history_test_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final environment = HistoryTestEnvironment();
  setUp(environment.setUp);
  tearDown(environment.tearDown);

  test('review cleanup removes only simulated SQLite messages and routes', () async {
    final history = MessageHistoryStorage.instance;
    final realNode = 'aa' * 32;
    final contact = 'bb' * 32;
    final channel = Channel(index: 0, name: 'Public', psk: Uint8List(16));
    for (final node in [realNode, ReviewRadio.selfPublicKeyHex]) {
      final direct = MessageStore()..setPublicKeyHex = node;
      await direct.saveMessages(contact, [Message(
        senderKey: Uint8List(32), text: node, timestamp: DateTime(2026),
        isOutgoing: false, messageId: node,
      )]);
      final group = ChannelMessageStore()
        ..setPublicKeyHex = node
        ..registerChannel(channel);
      await group.saveChannelMessages(0, [ChannelMessage(
        senderName: 'Test', text: node, timestamp: DateTime(2026),
        isOutgoing: false, status: ChannelMessageStatus.sent, channelIndex: 0,
        messageId: node,
      )]);
      await history.savePathHistoryJson(
        nodeKey: node.substring(0, 10), contactKey: contact,
        historyJson: '{"route":"$node"}',
      );
    }
    await history.savePathHistoryJson(
      nodeKey: '', contactKey: 'shared', historyJson: '{"route":"shared"}',
    );

    await clearReviewModeData();
    await clearReviewModeData(); // Cleanup after an interrupted session is repeatable.

    for (final kind in MessageHistoryKind.values) {
      final keys = history.getKeys(kind);
      expect(keys.where((key) => key.contains(ReviewRadio.storagePrefix)), isEmpty);
      expect(keys.where((key) => key.contains(realNode.substring(0, 10))), isNotEmpty);
    }
    expect(await history.loadPathHistoryJson(ReviewRadio.storagePrefix, contact), isNull);
    expect(await history.loadPathHistoryJson(realNode.substring(0, 10), contact),
        '{"route":"$realNode"}');
    expect(await history.loadPathHistoryJson('', 'shared'), '{"route":"shared"}');
  });
}