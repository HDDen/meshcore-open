import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/storage/channel_order_store.dart';
import 'package:meshcore_open/storage/channel_message_store.dart';
import 'package:meshcore_open/storage/channel_store.dart';
import 'package:meshcore_open/storage/contact_store.dart';
import 'package:meshcore_open/storage/message_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const scope = '0011223344';
  const contactKey =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const legacyKey = 'messages_$contactKey';
  const scopedKey = 'messages_$scope$contactKey';
  const historyJson = '[{"text":"hello","timestamp":1}]';

  setUp(() async {
    SharedPreferences.setMockInitialValues({legacyKey: historyJson});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  test('search read does not migrate an unscoped contact history', () async {
    final store = MessageStore()..setPublicKeyHex = scope;

    expect(await store.loadMessagesJsonForSearch(contactKey), isNull);
    expect(PrefsManager.instance.getString(legacyKey), historyJson);
    expect(PrefsManager.instance.getString(scopedKey), isNull);
  });

  test('current scope can read legacy history without modifying it', () async {
    final store = MessageStore()..setPublicKeyHex = scope;

    expect(
      await store.loadMessagesJsonForSearch(
        contactKey,
        includeLegacyUnscoped: true,
      ),
      historyJson,
    );
    expect(PrefsManager.instance.getString(legacyKey), historyJson);
    expect(PrefsManager.instance.getString(scopedKey), isNull);
  });

  test('channel search fallback does not migrate slot-based history', () async {
    const oldKey = 'channel_messages_1';
    const nameKey = 'channel_messages_0011223344name_VGVzdA';
    await PrefsManager.instance.setString(oldKey, historyJson);
    final channel = Channel.fromHex(1, 'Test', Channel.publicChannelPsk);
    final store = ChannelMessageStore()
      ..setPublicKeyHex = scope
      ..replaceChannels([channel]);

    expect(await store.loadChannelMessagesJsonForSearch(1), isNull);
    expect(
      await store.loadChannelMessagesJsonForSearch(
        1,
        includeLegacyIndexFallback: true,
      ),
      historyJson,
    );
    expect(PrefsManager.instance.getString(oldKey), historyJson);
    expect(PrefsManager.instance.getString(nameKey), isNull);
  });

  test('read-only channel load does not migrate slot-based history', () async {
    const oldKey = 'channel_messages_1';
    const nameKey = 'channel_messages_0011223344name_VGVzdA';
    await PrefsManager.instance.setString(oldKey, historyJson);
    final channel = Channel.fromHex(1, 'Test', Channel.publicChannelPsk);
    final store = ChannelMessageStore()
      ..setPublicKeyHex = scope
      ..replaceChannels([channel]);

    expect(
      await store.loadChannelMessages(1, allowLegacyMigration: false),
      isEmpty,
    );
    expect(PrefsManager.instance.getString(oldKey), historyJson);
    expect(PrefsManager.instance.getString(nameKey), isNull);
  });

  test('read-only contact cache load does not migrate legacy data', () async {
    await PrefsManager.instance.setString('contacts', '[]');
    final store = ContactStore()..setPublicKeyHex = '${scope}00';

    expect(await store.loadContacts(allowLegacyMigration: false), isEmpty);
    expect(PrefsManager.instance.getString('contacts'), '[]');
    expect(PrefsManager.instance.getString('contacts$scope'), isNull);
  });

  test('read-only channel cache load does not migrate legacy data', () async {
    await PrefsManager.instance.setString('channels', '[]');
    final store = ChannelStore()..setPublicKeyHex = scope;

    expect(await store.loadChannels(allowLegacyMigration: false), isEmpty);
    expect(PrefsManager.instance.getString('channels'), '[]');
    expect(PrefsManager.instance.getString('channels$scope'), isNull);
  });

  test('read-only channel order load does not migrate legacy data', () async {
    await PrefsManager.instance.setString('channel_order_', '[1,0]');
    final store = ChannelOrderStore()..setPublicKeyHex = '${scope}00';

    expect(await store.loadChannelOrder(allowLegacyMigration: false), isEmpty);
    expect(PrefsManager.instance.getString('channel_order_'), '[1,0]');
    expect(PrefsManager.instance.getString('channel_order_$scope'), isNull);
  });
}
