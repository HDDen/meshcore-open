import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/storage/contact_identity_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/message_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A contact's history is keyed by its public key; a key the user linked to
// another reads the history of both, writes under its own, never lists a
// message twice, sums the two in the contacts list's summary, and a clearing
// reaches both keys. The database needs a native sqlite3 the test host can
// load; when it cannot, the tests are skipped.

const _node = '7020f1bd19aabbccddeeff00112233445566778899aabbccddeeff0011223344';
final _newKey = 'aa' * 32;
final _oldKey = 'bb' * 32;

Message _message(String id, int minute, {bool outgoing = false}) {
  final at = DateTime.fromMillisecondsSinceEpoch(minute * 60000);
  return Message(
    senderKey: Uint8List(32),
    text: 'message $id',
    timestamp: at,
    receivedAt: at,
    isOutgoing: outgoing,
    messageId: id,
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
    MessageHistoryKind.direct,
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
  late MessageStore store;
  late String oldStorageKey;
  late String newStorageKey;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await MessageHistoryStorage.instance.resetForTesting();
    await MessageHistoryStorage.instance.initializeAndMigrate(
      databaseFactory: () =>
          MessageHistoryDatabase.withExecutor(NativeDatabase.memory()),
    );
    ContactIdentities.instance.resetForTesting();
    await ContactIdentities.instance.load();
    store = MessageStore()..setPublicKeyHex = _node;
    oldStorageKey = '${store.keyFor}$_oldKey';
    newStorageKey = '${store.keyFor}$_newKey';
  });

  tearDown(() async {
    ContactIdentities.instance.resetForTesting();
    await MessageHistoryStorage.instance.resetForTesting();
    PrefsManager.reset();
  });

  /// Two messages under the old key, then the link: the new key is the same
  /// person.
  Future<void> seedAndLink() async {
    await store.saveMessages(_oldKey, [_message('a', 1), _message('b', 2)]);
    await ContactIdentities.instance.link(_newKey, _oldKey);
  }

  test('a linked key reads the history of the old one', () async {
    await seedAndLink();
    expect(
      (await store.loadLatestMessages(_newKey, limit: 10)).map((m) => m.messageId),
      ['a', 'b'],
    );
    expect(
      (await store.loadMessages(_newKey)).map((m) => m.messageId),
      ['a', 'b'],
    );
    expect(
      (await store.loadScopedMessages(_newKey)).map((m) => m.messageId),
      ['a', 'b'],
    );
    await ContactIdentities.instance.forget(_newKey);
    expect(await store.loadLatestMessages(_newKey, limit: 10), isEmpty);
  }, skip: skip);

  test('a save under the new key drops the message from the old one', () async {
    await seedAndLink();
    await store.saveMessage(_newKey, _message('c', 3, outgoing: true));
    await store.saveMessage(_newKey, _message('a', 1));

    final latest = await store.loadLatestMessages(_newKey, limit: 10);
    expect(latest.map((m) => m.messageId), ['a', 'b', 'c']);
    expect(await _idsUnder(oldStorageKey), ['b']);
    expect(await _idsUnder(newStorageKey), ['a', 'c']);
  }, skip: skip);

  test('paging, deletion and the summary cross the keys', () async {
    await seedAndLink();
    await store.saveMessage(_newKey, _message('c', 3));
    final c = (await store.loadLatestMessages(_newKey, limit: 1)).single;
    final before = await store.loadMessagesBefore(_newKey, before: c, limit: 10);
    expect(before.map((m) => m.messageId), ['a', 'b']);

    final summaries = await store.loadMessageSummaries([_newKey]);
    expect(summaries[_newKey]?.messageCount, 3);
    expect(summaries[_newKey]?.latestMessageText, 'message c');
    expect((await store.loadMessageSummary(_newKey))?.messageCount, 3);

    await store.deleteMessage(_newKey, 'a');
    expect(await _idsUnder(oldStorageKey), ['b']);
  }, skip: skip);

  test('clearing reaches both keys', () async {
    await seedAndLink();
    await store.saveMessage(_newKey, _message('c', 3));
    await store.clearMessages(_newKey);
    final keys = MessageHistoryStorage.instance.getKeys(MessageHistoryKind.direct);
    expect(keys.contains(oldStorageKey), isFalse);
    expect(keys.contains(newStorageKey), isFalse);
  }, skip: skip);
}
