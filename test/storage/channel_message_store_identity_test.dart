import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/storage/channel_identity_store.dart';
import 'package:meshcore_open/storage/channel_message_store.dart';
import 'package:meshcore_open/storage/channel_name_keyed_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A channel's history is keyed by its name; a channel renamed under the same
// key reads the history of its former name through the identity table,
// writes under the current name, never lists a message twice, pages across
// both names, and a clearing reaches every name. The database needs a native
// sqlite3 the test host can load; when it cannot, the tests are skipped.

const _node = '7020f1bd19aabbccddeeff00112233445566778899aabbccddeeff0011223344';
const _otherNode =
    'afdad95d3a00112233445566778899aabbccddeeff00112233445566778899aa';

Uint8List _psk(int fill) =>
    Uint8List.fromList(List<int>.generate(16, (i) => (fill + i) & 0xFF));

String _id(int fill) => Channel.storageIdForPsk(_psk(fill))!;

Channel _channel(int index, String name, {int fill = 1}) =>
    Channel(index: index, name: name, psk: _psk(fill));

ChannelMessage _message(
  String id,
  int minute, {
  ChannelMessageStatus status = ChannelMessageStatus.sent,
}) {
  final at = DateTime.fromMillisecondsSinceEpoch(minute * 60000);
  return ChannelMessage(
    senderName: 'Ghost',
    text: 'message $id',
    timestamp: at,
    receivedAt: at,
    isOutgoing: false,
    status: status,
    messageId: id,
    channelIndex: 2,
  );
}

Future<String?> _sqliteProblem() async {
  try {
    final database = MessageHistoryDatabase.withExecutor(
      NativeDatabase.memory(),
    );
    await database.customSelect('SELECT 1').get();
    await database.close();
    return null;
  } catch (error) {
    return 'sqlite3 is not available to this test host: $error';
  }
}

Future<List<String>> _idsUnder(String key) async {
  final json = await MessageHistoryStorage.instance.getString(
    MessageHistoryKind.channel,
    key,
  );
  if (json == null) return const [];
  return [
    for (final entry in jsonDecode(json) as List<dynamic>)
      (entry as Map<String, dynamic>)['messageId'] as String,
  ];
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = await _sqliteProblem();
  late ChannelMessageStore store;
  late String oldKey;
  late String newKey;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await MessageHistoryStorage.instance.resetForTesting();
    await MessageHistoryStorage.instance.initializeAndMigrate(
      databaseFactory: () =>
          MessageHistoryDatabase.withExecutor(NativeDatabase.memory()),
    );
    ChannelIdentities.instance.resetForTesting();
    await ChannelIdentities.instance.load();
    store = ChannelMessageStore()..setPublicKeyHex = _node;
    oldKey = ChannelNameKeyedStore.nameStorageKey(store.keyFor, 'Горы');
    newKey = ChannelNameKeyedStore.nameStorageKey(store.keyFor, 'Горы-2026');
  });

  tearDown(() async {
    ChannelIdentities.instance.resetForTesting();
    await MessageHistoryStorage.instance.resetForTesting();
    PrefsManager.reset();
  });

  /// Two messages under the old name, then the rename: slot 2 now holds
  /// 'Горы-2026' with the same key.
  Future<void> seedAndRename() async {
    store.replaceChannels([_channel(2, 'Горы')]);
    await store.saveChannelMessages(2, [_message('a', 1), _message('b', 2)]);
    await ChannelIdentities.instance.link(
      ChannelIdentity(_id(1), 'Горы'),
      ChannelIdentity(_id(1), 'Горы-2026'),
    );
    store.replaceChannels([_channel(2, 'Горы-2026')]);
  }

  test('a renamed channel reads the history of its former name', () async {
    await seedAndRename();
    expect(store.channelStorageKeys(store.keyFor, 2), [newKey, oldKey]);

    final latest = await store.loadLatestChannelMessages(2, limit: 10);
    expect(latest.map((m) => m.messageId), ['a', 'b']);
    expect(latest.every((m) => m.channelIndex == 2), isTrue);
    final whole = await store.loadChannelMessages(2);
    expect(whole.map((m) => m.messageId), ['a', 'b']);
    // Without the link the new name starts empty.
    await ChannelIdentities.instance.forget(ChannelIdentity(_id(1), 'Горы'));
    expect(await store.loadLatestChannelMessages(2, limit: 10), isEmpty);
  }, skip: skip);

  test('a save under the new name drops the message from the former one', () async {
    await seedAndRename();
    await store.saveChannelMessage(2, _message('c', 3));
    await store.saveChannelMessage(
      2,
      _message('a', 1, status: ChannelMessageStatus.failed),
    );

    final latest = await store.loadLatestChannelMessages(2, limit: 10);
    expect(latest.map((m) => m.messageId), ['a', 'b', 'c']);
    expect(latest.first.status, ChannelMessageStatus.failed);
    expect(await _idsUnder(oldKey), ['b']);
    expect(await _idsUnder(newKey), ['a', 'c']);
  }, skip: skip);

  test('paging crosses the names', () async {
    await seedAndRename();
    await store.saveChannelMessage(2, _message('c', 3));
    final c = (await store.loadLatestChannelMessages(2, limit: 1)).single;
    expect(c.messageId, 'c');

    final before = await store.loadChannelMessagesBefore(2, before: c, limit: 10);
    expect(before.map((m) => m.messageId), ['a', 'b']);
    final one = await store.loadChannelMessagesBefore(2, before: c, limit: 1);
    expect(one.map((m) => m.messageId), ['b']);
    final a = before.first;
    final after = await store.loadChannelMessagesAfter(2, after: a, limit: 10);
    expect(after.map((m) => m.messageId), ['b', 'c']);
  }, skip: skip);

  test('a deletion and a replacement reach the former name', () async {
    await seedAndRename();
    await store.deleteChannelMessage(2, 'a');
    expect(await _idsUnder(oldKey), ['b']);

    await store.replaceChannelMessages(2, [_message('b', 2), _message('d', 4)]);
    expect(await _idsUnder(oldKey), isEmpty);
    expect(await _idsUnder(newKey), ['b', 'd']);
  }, skip: skip);

  test('clearing the channel removes every name; by names, another scope', () async {
    await seedAndRename();
    await store.saveChannelMessage(2, _message('c', 3));
    await store.clearChannelMessages(2);
    final keys = MessageHistoryStorage.instance.getKeys(
      MessageHistoryKind.channel,
    );
    expect(keys.contains(oldKey), isFalse);
    expect(keys.contains(newKey), isFalse);

    final other = ChannelMessageStore()..setPublicKeyHex = _otherNode;
    other.replaceChannels([_channel(5, 'Горы')]);
    await other.saveChannelMessages(5, [_message('x', 1)]);
    final otherKey = ChannelNameKeyedStore.nameStorageKey(other.keyFor, 'Горы');
    expect(await _idsUnder(otherKey), ['x']);
    await (ChannelMessageStore()..setPublicKeyHex = _otherNode)
        .clearMessagesForNames(['Горы-2026', 'Горы']);
    expect(await _idsUnder(otherKey), isEmpty);
  }, skip: skip);

  test('the resend count survives a save and a load, 0 when absent', () async {
    store.replaceChannels([_channel(2, 'Горы')]);
    final resent = _message('r', 1).copyWith(isOutgoing: true, resendCount: 2);
    await store.saveChannelMessages(2, [resent, _message('s', 2)]);

    final loaded = await store.loadChannelMessages(2);
    expect(loaded.map((m) => m.resendCount), [2, 0]);
    expect(
      ChannelMessageStore.decodeStoredMessage({
        'senderName': 'Ghost',
        'text': 'old row',
        'timestamp': 60000,
        'isOutgoing': true,
        'status': ChannelMessageStatus.sent.index,
        'messageId': 'old',
      }).resendCount,
      0,
    );
  }, skip: skip);
  test('strict channel writes cannot succeed without a channel name', () async {
    store.replaceChannels(const []);
    await expectLater(
      store.saveChannelMessage(2, _message('pending', 1), requireBinding: true),
      throwsStateError,
    );
  }, skip: skip);

  test('strict channel writes cannot succeed without a node scope', () async {
    final unscoped = ChannelMessageStore();
    unscoped.registerChannel(_channel(2, 'Test'));
    await expectLater(
      unscoped.saveChannelMessage(2, _message('pending', 1), requireBinding: true),
      throwsStateError,
    );
  }, skip: skip);

}
