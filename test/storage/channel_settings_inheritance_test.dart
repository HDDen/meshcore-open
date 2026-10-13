import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/storage/channel_identity_store.dart';
import 'package:meshcore_open/storage/channel_name_keyed_store.dart';
import 'package:meshcore_open/storage/channel_region_store.dart';
import 'package:meshcore_open/storage/channel_settings_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A channel's settings and region are kept by the node and the channel's
// name. When a node has none, it reads the value its channel's former names
// hold in its scope, then the value another node keeps for the same channel;
// a value set on the node wins from then on. A clearing by names reaches
// every setting of a scope.

const _nodeA = '7020f1bd19aabbccddeeff00112233445566778899aabbccddeeff0011223344';
const _nodeB = 'afdad95d3a00112233445566778899aabbccddeeff00112233445566778899aa';

Uint8List _psk(int fill) =>
    Uint8List.fromList(List<int>.generate(16, (i) => (fill + i) & 0xFF));

String _id(int fill) => Channel.storageIdForPsk(_psk(fill))!;

Channel _channel(int index, String name, {int fill = 1}) =>
    Channel(index: index, name: name, psk: _psk(fill));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    ChannelIdentities.instance.resetForTesting();
    await ChannelIdentities.instance.load();
  });

  tearDown(() {
    ChannelIdentities.instance.resetForTesting();
    PrefsManager.reset();
  });

  test('a node without a setting takes the one another node keeps', () async {
    final a = ChannelSettingsStore()..setPublicKeyHex = _nodeA;
    a.replaceChannels([_channel(1, 'Горы')]);
    await a.saveSmazEnabled(1, true);
    await a.saveMcmpVersion(1, 2);

    final b = ChannelSettingsStore()..setPublicKeyHex = _nodeB;
    b.replaceChannels([_channel(5, 'Горы')]);
    expect(await b.loadSmazEnabled(5), isTrue);
    expect(await b.loadMcmpVersion(5), 2);
    expect(await b.loadUrlImagesEnabled(5), isFalse);

    await b.saveSmazEnabled(5, false);
    expect(await b.loadSmazEnabled(5), isFalse);
    expect(await a.loadSmazEnabled(1), isTrue);
  });

  test('a renamed channel keeps its settings and its region', () async {
    final settings = ChannelSettingsStore()..setPublicKeyHex = _nodeA;
    final regions = ChannelRegionStore()..setPublicKeyHex = _nodeA;
    settings.replaceChannels([_channel(1, 'Горы')]);
    regions.replaceChannels([_channel(1, 'Горы')]);
    await settings.saveSmazEnabled(1, true);
    await settings.saveCyr2LatProfileId(1, 'profile-1');
    await regions.saveRegion(1, 'alps');

    await ChannelIdentities.instance.link(
      ChannelIdentity(_id(1), 'Горы'),
      ChannelIdentity(_id(1), 'Горы-2026'),
    );
    settings.replaceChannels([_channel(1, 'Горы-2026')]);
    regions.replaceChannels([_channel(1, 'Горы-2026')]);

    expect(await settings.loadSmazEnabled(1), isTrue);
    expect(await settings.loadCyr2LatProfileId(1), 'profile-1');
    expect(await regions.loadRegion(1), 'alps');

    // The channel's own keys come first, the former name's after them.
    expect(
      settings.channelInheritedKeys(
        keyPrefix: settings.keyFor,
        scope: settings.publicKeyHex,
        channelIndex: 1,
      ),
      [ChannelNameKeyedStore.nameStorageKey(settings.keyFor, 'Горы')],
    );
  });

  test('the other node is read under every name of the channel', () async {
    final a = ChannelRegionStore()..setPublicKeyHex = _nodeA;
    a.replaceChannels([_channel(1, 'Горы')]);
    await a.saveRegion(1, 'alps');
    await ChannelIdentities.instance.link(
      ChannelIdentity(_id(1), 'Горы'),
      ChannelIdentity(_id(1), 'Горы-2026'),
    );

    final b = ChannelRegionStore()..setPublicKeyHex = _nodeB;
    b.replaceChannels([_channel(5, 'Горы-2026')]);
    expect(await b.loadRegion(5), 'alps');
    await b.saveRegion(5, 'urals');
    expect(await b.loadRegion(5), 'urals');
    expect(await a.loadRegion(1), 'alps');
  });

  test('a clearing by names reaches every setting of a scope', () async {
    final a = ChannelSettingsStore()..setPublicKeyHex = _nodeA;
    a.replaceChannels([_channel(1, 'Горы')]);
    await a.saveSmazEnabled(1, true);
    await a.saveUrlImagesEnabled(1, true);
    await a.saveWidgetColor(1, 0xFF112233);
    final regions = ChannelRegionStore()..setPublicKeyHex = _nodeA;
    regions.replaceChannels([_channel(1, 'Горы')]);
    await regions.saveRegion(1, 'alps');

    await (ChannelSettingsStore()..setPublicKeyHex = _nodeA)
        .clearSettingsForNames(['Горы']);
    await (ChannelRegionStore()..setPublicKeyHex = _nodeA)
        .clearRegionsForNames(['Горы']);

    expect(await a.loadSmazEnabled(1), isFalse);
    expect(await a.loadUrlImagesEnabled(1), isFalse);
    expect(await a.loadWidgetColor(1), isNull);
    expect(await regions.loadRegion(1), '');
  });

  test('a sender name is inherited until the node clears it', () async {
    final a = ChannelSettingsStore()..setPublicKeyHex = _nodeA;
    a.replaceChannels([_channel(1, 'Горы')]);
    await a.saveSenderName(1, 'База');

    final b = ChannelSettingsStore()..setPublicKeyHex = _nodeB;
    b.replaceChannels([_channel(5, 'Горы')]);
    expect(await b.loadSenderName(5), 'База');

    // The empty string is a value of its own: the node's name, set here,
    // which the read does not fall through.
    await b.saveSenderName(5, '');
    expect(await b.loadSenderName(5), '');
    expect(await a.loadSenderName(1), 'База');

    final c = ChannelSettingsStore()..setPublicKeyHex = _nodeB;
    c.replaceChannels([_channel(7, 'Море')]);
    expect(await c.loadSenderName(7), isNull);
  });
}
