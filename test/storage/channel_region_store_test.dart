import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/storage/channel_region_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // PrefsManager.initialize looks for the preferences file through
  // path_provider on Windows and Linux; with the binding up that call is a
  // MissingPluginException the manager expects, without it a binding error.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(() {
    PrefsManager.reset();
  });

  ChannelRegionStore createStore() {
    final store = ChannelRegionStore()
      ..setPublicKeyHex = '00112233445566778899'
      ..registerChannel(Channel(index: 1, name: 'Public', psk: Uint8List(16)));
    return store;
  }

  Map<String, Object?> snapshot() {
    final prefs = PrefsManager.instance;
    return {for (final key in prefs.getKeys()) key: prefs.get(key)};
  }

  test('save trims region and clears empty values', () async {
    final store = createStore();

    expect(await store.saveRegion(1, '  EU  '), equals('EU'));
    expect(await store.loadRegion(1), equals('EU'));

    expect(await store.saveRegion(1, '   '), isEmpty);
    expect(await store.loadRegion(1), isEmpty);
  });

  test('a region saved for a name is found by a store that learns the '
      'name later', () async {
    // What adding a channel by QR relies on: the region is written before
    // the connector's own store knows the new slot.
    final psk = Uint8List(16)..[0] = 1;
    final early = ChannelRegionStore()
      ..setPublicKeyHex = '00112233445566778899'
      ..registerChannel(Channel(index: 5, name: '#ping', psk: psk));
    expect(await early.saveRegion(5, 'bots'), 'bots');

    final connectorStore = createStore();
    // No name for slot 5 yet: nothing to load, and nothing can be saved.
    expect(await connectorStore.loadRegion(5), isEmpty);
    expect(await connectorStore.saveRegion(5, 'other'), isEmpty);

    connectorStore.registerChannel(
      Channel(index: 5, name: '#ping', psk: psk),
    );
    expect(await connectorStore.loadRegion(5), 'bots');
  });

  test('loading writes nothing: an empty or untrimmed stored region is read '
      'as it is', () async {
    final store = createStore();
    final prefs = PrefsManager.instance;
    await prefs.setString('channel_region_0011223344name_UHVibGlj', '');
    final before = snapshot();

    expect(await store.loadRegion(1), isEmpty);
    expect(snapshot(), before);

    await prefs.setString('channel_region_0011223344name_UHVibGlj', ' EU ');
    final untrimmed = snapshot();
    expect(await store.loadRegion(1), 'EU');
    expect(snapshot(), untrimmed);
  });

  test('a region stored under the slot number is read without being moved, '
      'and a save moves it', () async {
    final store = createStore();
    final prefs = PrefsManager.instance;
    await prefs.setString('channel_region_00112233441', 'EU');
    final before = snapshot();

    expect(await store.loadRegion(1), 'EU');
    expect(snapshot(), before);
    // A store past its migration window no longer looks there.
    store.finishLegacyIndexMigration();
    expect(await store.loadRegion(1), isEmpty);
    store.beginLegacyIndexMigration();

    expect(await store.saveRegion(1, 'US'), 'US');
    expect(prefs.containsKey('channel_region_00112233441'), isFalse);
    expect(prefs.getString('channel_region_0011223344name_UHVibGlj'), 'US');
  });

  test('loading and clearing with nothing stored write nothing', () async {
    final store = createStore();
    final before = snapshot();

    expect(await store.loadRegion(1), isEmpty);
    await store.clearRegion(1);
    expect(snapshot(), before);
  });
}
