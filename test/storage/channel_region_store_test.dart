import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/storage/channel_region_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
      ..registerChannel(
        Channel(index: 1, name: 'Public', psk: Uint8List(16)),
      );
    return store;
  }

  test('save trims region and clears empty values', () async {
    final store = createStore();

    expect(await store.saveRegion(1, '  EU  '), equals('EU'));
    expect(await store.loadRegion(1), equals('EU'));

    expect(await store.saveRegion(1, '   '), isEmpty);
    expect(await store.loadRegion(1), isEmpty);
  });

  test('load removes legacy empty stored region', () async {
    final store = createStore();
    final prefs = PrefsManager.instance;

    await prefs.setString('channel_region_0011223344name_UHVibGlj', '');

    expect(await store.loadRegion(1), isEmpty);
    expect(
      prefs.containsKey('channel_region_0011223344name_UHVibGlj'),
      isFalse,
    );
  });
}
