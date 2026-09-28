import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel_group.dart';
import 'package:meshcore_open/models/community.dart';
import 'package:meshcore_open/models/contact_group.dart';
import 'package:meshcore_open/storage/channel_group_store.dart';
import 'package:meshcore_open/storage/channel_order_store.dart';
import 'package:meshcore_open/storage/community_store.dart';
import 'package:meshcore_open/storage/contact_group_store.dart';
import 'package:meshcore_open/storage/node_identity_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The small per-node collections: channel order, channel groups with their
// UI state, contact groups, communities and the node's own name. Pinned on
// their preference form before they move into one table of the database:
// what a save keeps, what a load drops, and that each node has its own.

const nodeA = '7020f1bd19aabbccddeeff00112233445566778899aabbccddeeff0011223344';
const nodeB = 'afdad95d3a00112233445566778899aabbccddeeff00112233445566778899aa';

Future<void> initPrefs([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  PrefsManager.reset();
  await PrefsManager.initialize();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => initPrefs());
  tearDown(PrefsManager.reset);

  group('channel order', () {
    ChannelOrderStore forNode(String node) =>
        ChannelOrderStore()..setPublicKeyHex = node;

    test('an order is read back as saved, per node', () async {
      final a = forNode(nodeA);
      final b = forNode(nodeB);
      await a.saveChannelOrder([3, 1, 2]);

      expect(await a.loadChannelOrder(), [3, 1, 2]);
      expect(await b.loadChannelOrder(), isEmpty);

      await b.saveChannelOrder([0]);
      expect(await a.loadChannelOrder(), [3, 1, 2]);
      expect(await b.loadChannelOrder(), [0]);
    });

    test('an order stored as a comma list is still read', () async {
      await initPrefs({'channel_order_7020f1bd19': '1,3,2'});
      expect(await forNode(nodeA).loadChannelOrder(), [1, 3, 2]);
    });

    test('without a node key nothing is loaded or saved', () async {
      final store = ChannelOrderStore();
      await store.saveChannelOrder([1]);
      expect(await store.loadChannelOrder(), isEmpty);
      expect(
        PrefsManager.instance.getKeys().where(
          (k) => k.startsWith('channel_order'),
        ),
        isEmpty,
      );
    });
  });

  group('channel groups', () {
    ChannelGroupStore forNode(String node) =>
        ChannelGroupStore()..setPublicKeyHex = node;

    test('groups come back with every field; a blank name is dropped',
        () async {
      final store = forNode(nodeA);
      final saved = [
        const ChannelGroup(
          name: 'Ops',
          channelNames: ['#ops', '#alert'],
          sortOrder: 2,
          widgetColor: 0xFF112233,
          widgetTextColor: 0xFFFFFFFF,
          allowOrderingInGroup: true,
        ),
        const ChannelGroup(name: 'Plain', channelNames: []),
        const ChannelGroup(name: '   ', channelNames: ['#lost']),
      ];

      await store.saveGroups(saved);

      final loaded = await store.loadGroups();
      expect(loaded.map((g) => g.toJson()), [
        saved[0].toJson(),
        saved[1].toJson(),
      ]);
    });

    test('expanded names and the screen order are kept per node', () async {
      final a = forNode(nodeA);
      final b = forNode(nodeB);
      await a.saveExpandedGroupNames({'Ops', ' ', 'Plain'});
      await a.saveScreenOrder(['#ops', 'Plain', '#alert']);

      expect(await a.loadExpandedGroupNames(), {'Ops', 'Plain'});
      expect(await a.loadScreenOrder(), ['#ops', 'Plain', '#alert']);
      expect(await b.loadExpandedGroupNames(), isEmpty);
      expect(await b.loadScreenOrder(), isEmpty);
      expect(await b.loadGroups(), isEmpty);
    });

    test('unreadable state reads as nothing', () async {
      await initPrefs({
        'channel_groups7020f1bd19': '{',
        'channel_groups_expanded7020f1bd19': '{',
        'channel_screen_order7020f1bd19': '{',
      });
      final store = forNode(nodeA);
      expect(await store.loadGroups(), isEmpty);
      expect(await store.loadExpandedGroupNames(), isEmpty);
      expect(await store.loadScreenOrder(), isEmpty);
    });
  });

  group('contact groups', () {
    ContactGroupStore forNode(String node) =>
        ContactGroupStore()..setPublicKeyHex = node;

    test('groups come back with their members, per node', () async {
      final a = forNode(nodeA);
      final b = forNode(nodeB);
      final saved = [
        const ContactGroup(name: 'Family', memberKeys: ['aa', 'bb']),
        const ContactGroup(name: 'Empty', memberKeys: []),
      ];
      await a.saveGroups(saved);

      expect(
        (await a.loadGroups()).map((g) => g.toJson()),
        saved.map((g) => g.toJson()),
      );
      expect(await b.loadGroups(), isEmpty);
    });
  });

  group('communities', () {
    CommunityStore forNode(String node) =>
        CommunityStore()..setPublicKeyHex = node;

    test('a community keeps its secret, creation time and hashtag channels',
        () async {
      final store = forNode(nodeA);
      final community = Community.create(
        id: 'c1',
        name: 'Ops',
      ).addHashtagChannel('#ops').addHashtagChannel('alerts');

      await store.saveCommunities([community]);

      final loaded = await store.loadCommunities();
      expect(loaded.map((c) => c.toJson()), [community.toJson()]);
      expect(loaded.single.communityId, community.communityId);
      expect(loaded.single.secret, hasLength(32));
    });

    test('add, update, remove and lookups go through the stored list',
        () async {
      final store = forNode(nodeA);
      final first = Community.create(id: 'c1', name: 'Ops');
      final second = Community.create(id: 'c2', name: 'Hikers');
      await store.addCommunity(first);
      await store.addCommunity(second);
      // Adding under an existing id replaces.
      await store.addCommunity(Community.create(id: 'c2', name: 'Riders'));

      expect((await store.loadCommunities()).map((c) => c.name), [
        'Ops',
        'Riders',
      ]);
      expect((await store.getCommunity('c1'))!.name, 'Ops');
      expect(await store.getCommunity('missing'), isNull);
      expect(
        (await store.findByCommunityId(first.communityId))!.id,
        'c1',
      );
      expect(await store.findByCommunityId('nope'), isNull);

      await store.addHashtagChannel('c1', '#ops');
      expect((await store.getCommunity('c1'))!.hashtagChannels, ['ops']);
      await store.removeHashtagChannel('c1', 'ops');
      expect((await store.getCommunity('c1'))!.hashtagChannels, isEmpty);

      await store.updateCommunity(
        Community(
          id: 'c1',
          name: 'Ops renamed',
          secret: first.secret,
          createdAt: first.createdAt,
        ),
      );
      expect((await store.getCommunity('c1'))!.name, 'Ops renamed');

      await store.removeCommunity('c1');
      expect((await store.loadCommunities()).map((c) => c.id), ['c2']);
      expect(await forNode(nodeB).loadCommunities(), isEmpty);
    });
  });

  group('node identity', () {
    NodeIdentityStore forNode(String node) =>
        NodeIdentityStore()..setPublicKeyHex = node;

    test('the name is trimmed, kept per node, and an empty name is ignored',
        () async {
      final a = forNode(nodeA);
      final b = forNode(nodeB);
      expect(a.loadName(), isNull);

      await a.saveName('  Alpha ');
      expect(a.loadName(), 'Alpha');
      expect(b.loadName(), isNull);

      await a.saveName('   ');
      await a.saveName(null);
      expect(a.loadName(), 'Alpha');

      await b.saveName('Bravo');
      expect(a.loadName(), 'Alpha');
      expect(b.loadName(), 'Bravo');
    });

    test('without a node key nothing is loaded or saved', () async {
      final store = NodeIdentityStore();
      await store.saveName('Nobody');
      expect(store.loadName(), isNull);
      expect(
        PrefsManager.instance.getKeys().where(
          (k) => k.startsWith('node_identity'),
        ),
        isEmpty,
      );
    });
  });
}
