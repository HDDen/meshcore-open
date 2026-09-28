import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/storage/channel_order_store.dart';
import 'package:meshcore_open/storage/channel_region_store.dart';
import 'package:meshcore_open/storage/channel_settings_store.dart';
import 'package:meshcore_open/storage/channel_store.dart';
import 'package:meshcore_open/storage/community_store.dart';
import 'package:meshcore_open/storage/contact_group_store.dart';
import 'package:meshcore_open/storage/contact_settings_store.dart';
import 'package:meshcore_open/storage/contact_store.dart';
import 'package:meshcore_open/storage/node_identity_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/storage/unread_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// On Windows and Linux every write, a removal of an absent key included,
// rewrites the whole preferences file. Loading, then, must not write: the
// stores used to remove the keys of the time before scoping whether or not
// they were there, and the region store tidied what it read.

const node = '7020f1bd19aabbccddeeff00112233445566778899aabbccddeeff0011223344';
const contactKey =
    'b4004fff7b835c81b74e1e55a6adadff317a7cff5ff06a8adb4ca6cd71667e0c';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> initPrefs([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    PrefsManager.reset();
    await PrefsManager.initialize();
  }

  Map<String, Object?> snapshot() {
    final prefs = PrefsManager.instance;
    return {for (final key in prefs.getKeys()) key: prefs.get(key)};
  }

  setUp(() => initPrefs());
  tearDown(PrefsManager.reset);

  test('loading with nothing stored writes nothing', () async {
    await initPrefs({'app_settings': '{}'});
    final before = snapshot();
    final channel = Channel(index: 1, name: 'Public', psk: Uint8List(16));

    await (ContactStore()..setPublicKeyHex = node).loadContacts();
    await (ChannelStore()..setPublicKeyHex = node).loadChannels();
    await (ChannelOrderStore()..setPublicKeyHex = node).loadChannelOrder();
    await (ContactGroupStore()..setPublicKeyHex = node).loadGroups();
    await (CommunityStore()..setPublicKeyHex = node).loadCommunities();
    await (UnreadStore()..setPublicKeyHex = node).loadContactUnreadCount();
    await (ContactSettingsStore()..setPublicKeyHex = node).loadSmazEnabled(
      contactKey,
    );
    final region = ChannelRegionStore()
      ..setPublicKeyHex = node
      ..registerChannel(channel);
    await region.loadRegion(1);
    await region.clearRegion(1);
    final settings = ChannelSettingsStore()
      ..setPublicKeyHex = node
      ..registerChannel(channel);
    await settings.loadSmazEnabled(1);
    (NodeIdentityStore()..setPublicKeyHex = node).loadName();

    expect(snapshot(), before);
  });

  test('a value of the time before scoping is taken over once, and only '
      'when it is there', () async {
    await initPrefs({
      'contacts': jsonEncode([]),
      'channel_order_': '[1, 2]',
    });

    expect(await (ContactStore()..setPublicKeyHex = node).loadContacts(), isEmpty);
    expect(
      await (ChannelOrderStore()..setPublicKeyHex = node).loadChannelOrder(),
      [1, 2],
    );

    final prefs = PrefsManager.instance;
    expect(prefs.containsKey('contacts'), isFalse);
    expect(prefs.containsKey('channel_order_'), isFalse);
    expect(prefs.getString('contacts7020f1bd19'), '[]');
    expect(prefs.getString('channel_order_7020f1bd19'), '[1, 2]');

    final after = snapshot();
    await (ContactStore()..setPublicKeyHex = node).loadContacts();
    await (ChannelOrderStore()..setPublicKeyHex = node).loadChannelOrder();
    expect(snapshot(), after);
  });

  test('the node name is written once, not at every handshake', () async {
    final store = NodeIdentityStore()..setPublicKeyHex = node;
    await store.saveName('Alpha');
    final once = snapshot();

    await store.saveName('Alpha');
    await store.saveName(' Alpha ');

    expect(snapshot(), once);
    expect(store.loadName(), 'Alpha');
  });
}
