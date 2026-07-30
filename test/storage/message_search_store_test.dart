import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/storage/channel_message_store.dart';
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
}
