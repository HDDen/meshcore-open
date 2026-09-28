import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/storage/channel_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What ChannelStore promises, pinned on its preference form before the
// channels move into the database: index, name, key and unread count
// survive a save, each node keeps its own list, a save replaces the list.

const nodeA = '7020f1bd19aabbccddeeff00112233445566778899aabbccddeeff0011223344';
const nodeB = 'afdad95d3a00112233445566778899aabbccddeeff00112233445566778899aa';

Channel channel(int index, {String? name, int unread = 0, int fill = 0}) =>
    Channel(
      index: index,
      name: name ?? '#channel_$index',
      psk: Uint8List.fromList(List<int>.generate(16, (i) => fill + i)),
      unreadCount: unread,
    );

void expectSameChannel(Channel actual, Channel expected) {
  expect(actual.index, expected.index);
  expect(actual.name, expected.name);
  expect(actual.psk, expected.psk);
  expect(actual.unreadCount, expected.unreadCount);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  ChannelStore forNode(String node) => ChannelStore()..setPublicKeyHex = node;

  test('channels come back with index, name, key and unread count, in order',
      () async {
    final store = forNode(nodeA);
    final saved = [
      channel(0, name: 'Public', unread: 3),
      channel(2, name: '', fill: 0x20),
      channel(5, name: '#ru-kda', unread: 12, fill: 0x50),
    ];

    await store.saveChannels(saved);

    final loaded = await store.loadChannels();
    expect(loaded, hasLength(saved.length));
    for (var i = 0; i < saved.length; i++) {
      expectSameChannel(loaded[i], saved[i]);
    }
  });

  test('each node keeps its own list', () async {
    final a = forNode(nodeA);
    final b = forNode(nodeB);
    await a.saveChannels([channel(0), channel(1)]);

    expect(await b.loadChannels(), isEmpty);

    await b.saveChannels([channel(3)]);
    expect((await a.loadChannels()).map((c) => c.index), [0, 1]);
    expect((await b.loadChannels()).map((c) => c.index), [3]);
  });

  test('a save replaces the list whole, and an empty save leaves nothing',
      () async {
    final store = forNode(nodeA);
    await store.saveChannels([channel(0), channel(1), channel(2)]);
    await store.saveChannels([channel(1, unread: 7)]);

    final loaded = await store.loadChannels();
    expect(loaded.map((c) => c.index), [1]);
    expect(loaded.single.unreadCount, 7);

    await store.saveChannels(const []);
    expect(await store.loadChannels(), isEmpty);
  });

  test('without a node key nothing is loaded or saved', () async {
    final store = ChannelStore();
    expect(await store.loadChannels(), isEmpty);

    await store.saveChannels([channel(0)]);

    expect(await forNode(nodeA).loadChannels(), isEmpty);
    expect(
      PrefsManager.instance.getKeys().where((k) => k.startsWith('channels')),
      isEmpty,
    );
  });

  test('a list that will not decode reads as empty', () async {
    SharedPreferences.setMockInitialValues({'channels7020f1bd19': '{oops'});
    PrefsManager.reset();
    await PrefsManager.initialize();
    expect(await forNode(nodeA).loadChannels(), isEmpty);
  });
}
