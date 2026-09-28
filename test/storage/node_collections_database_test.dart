import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_group.dart';
import 'package:meshcore_open/models/community.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/contact_group.dart';
import 'package:meshcore_open/models/delivery_observation.dart';
import 'package:meshcore_open/models/path_history.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/storage/channel_group_store.dart';
import 'package:meshcore_open/storage/channel_order_store.dart';
import 'package:meshcore_open/storage/channel_store.dart';
import 'package:meshcore_open/storage/community_store.dart';
import 'package:meshcore_open/storage/contact_group_store.dart';
import 'package:meshcore_open/storage/contact_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/node_identity_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The node collections in the database: contacts and channels as rows,
// path histories with the shared row, delivery observations, the small
// per-node values, and the move out of preferences. The database needs a
// native sqlite3 the test host can load; when it cannot, every test here is
// skipped rather than failed.

MessageHistoryDatabase _memoryDatabase() =>
    MessageHistoryDatabase.withExecutor(NativeDatabase.memory());

Future<String?> _sqliteProblem() async {
  try {
    final database = _memoryDatabase();
    await database.customSelect('SELECT 1').get();
    await database.close();
    return null;
  } catch (error) {
    return 'sqlite3 is not available to this test host: $error';
  }
}

const nodeA = '7020f1bd19aabbccddeeff00112233445566778899aabbccddeeff0011223344';
const nodeB = 'afdad95d3a00112233445566778899aabbccddeeff00112233445566778899aa';
const contact1 =
    'b4004fff7b835c81b74e1e55a6adadff317a7cff5ff06a8adb4ca6cd71667e0c';
const contact2 =
    'da98e0127037b4db4264497a76eb997351b0c58c2158c1e22e2f7d4093865d39';
const contact3 =
    '823288803512066d45c0c002da29ff1fbc78cae6dd1a9f484aee38071effacb9';

Contact contact(int n, {int pathLength = 1, bool hasMessages = false}) =>
    Contact(
      publicKey: Uint8List.fromList(
        List<int>.generate(32, (i) => (n * 7 + i) & 0xFF),
      ),
      name: 'Node $n',
      type: n % 4,
      pathLength: pathLength,
      path: Uint8List.fromList(
        List<int>.generate(pathLength < 0 ? 0 : pathLength, (i) => 0xA0 + i),
      ),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(1758000000000 + n * 1000),
      hasMessages: hasMessages,
    );

Channel channel(int index, {int unread = 0}) => Channel(
  index: index,
  name: '#channel_$index',
  psk: Uint8List.fromList(List<int>.generate(16, (i) => index + i)),
  unreadCount: unread,
);

ContactPathHistory history(String contact, int hops) => ContactPathHistory(
  contactPubKeyHex: contact,
  recentPaths: [
    PathRecord(
      hopCount: hops,
      tripTimeMs: 1000 * hops + 7,
      timestamp: DateTime.utc(2026, 9, 1, 12),
      wasFloodDiscovery: false,
      pathBytes: List<int>.generate(hops, (i) => 0x10 + i),
      successCount: hops,
      failureCount: 0,
    ),
  ],
);

DeliveryObservation observation(int n) => DeliveryObservation(
  contactKey: 'contact_$n',
  pathLength: n,
  messageBytes: 20 * n,
  secondsSinceLastRx: 60 * n,
  isFlood: n.isEven,
  deliveryMs: 1500 + n,
  timestamp: DateTime.utc(2026, 9, 1, 10, n % 60),
);

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = await _sqliteProblem();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final tempDir = Directory.systemTemp.createTempSync('mco_node_db_');
  var fileIndex = 0;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(() async {
    await MessageHistoryStorage.instance.resetForTesting();
    PrefsManager.reset();
  });

  /// Opens the storage over a fresh in-memory database, or over [factory],
  /// with [prefs] as the preference contents the move reads.
  Future<void> openStorage({
    Map<String, Object> prefs = const {},
    MessageHistoryDatabase Function()? factory,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    PrefsManager.reset();
    await PrefsManager.initialize();
    await MessageHistoryStorage.instance.resetForTesting();
    await MessageHistoryStorage.instance.initializeAndMigrate(
      databaseFactory: factory ?? _memoryDatabase,
    );
    expect(MessageHistoryStorage.instance.hasDatabase, isTrue);
  }

  /// A database in a file, so that the storage can be closed and reopened
  /// over the same rows, as a second launch does.
  MessageHistoryDatabase Function() fileDatabase() {
    final path =
        '${tempDir.path}${Platform.pathSeparator}node_${fileIndex++}.sqlite';
    return () => MessageHistoryDatabase.withExecutor(NativeDatabase(File(path)));
  }

  ContactStore contactsOf(String node) => ContactStore()..setPublicKeyHex = node;
  ChannelStore channelsOf(String node) => ChannelStore()..setPublicKeyHex = node;
  StorageService serviceOf(String node) =>
      StorageService()..setPublicKeyHex = node;

  group('contacts', () {
    test('contacts come back with their fields per node; a save replaces '
        'the list', () async {
      await openStorage();
      final a = contactsOf(nodeA);
      final b = contactsOf(nodeB);
      await a.saveContacts([contact(1, pathLength: -1), contact(2), contact(3)]);

      final loaded = await a.loadContacts();
      expect(loaded.map((c) => c.name), ['Node 1', 'Node 2', 'Node 3']);
      expect(loaded[0].pathLength, -1);
      expect(loaded[1].path, [0xA0]);
      expect(loaded[1].publicKeyHex, contact(2).publicKeyHex);
      expect(await b.loadContacts(), isEmpty);

      await a.saveContacts([contact(2)]);
      expect((await a.loadContacts()).map((c) => c.name), ['Node 2']);
      await a.saveContacts(const []);
      expect(await a.loadContacts(), isEmpty);
    });

    test('a save after a load writes what changed and removes what is gone',
        () async {
      await openStorage();
      final store = contactsOf(nodeA);
      await store.loadContacts();
      await store.saveContacts([contact(1), contact(2)]);
      final loaded = await store.loadContacts();

      // The very objects loaded are not written again; a new object for a
      // known key replaces its row; a key that is gone loses its row.
      await store.saveContacts([loaded[0], contact(3), contact(1, hasMessages: true)]);

      final again = await store.loadContacts();
      expect(again.map((c) => c.name), ['Node 1', 'Node 3']);
      expect(again[0].hasMessages, isTrue);
    });

    test('a store that never loaded deletes nothing', () async {
      await openStorage();
      await contactsOf(nodeA).saveContacts([contact(1), contact(2)]);

      await contactsOf(nodeA).saveContacts([contact(3)]);

      expect(
        (await contactsOf(nodeA).loadContacts()).map((c) => c.name),
        ['Node 1', 'Node 2', 'Node 3'],
      );
    });

    test('writes run in order and a load waits for them', () async {
      await openStorage();
      final store = contactsOf(nodeA);
      final first = store.saveContacts([contact(1)]);
      final second = store.saveContacts([contact(2)]);

      expect((await store.loadContacts()).map((c) => c.name), ['Node 2']);
      await first;
      await second;
    });

    test('the node is taken when the save is called, not when it runs',
        () async {
      await openStorage();
      final store = contactsOf(nodeA);
      final first = store.saveContacts([contact(1)]);
      store.setPublicKeyHex = nodeB;
      final second = store.saveContacts([contact(2)]);
      await first;
      await second;

      expect((await contactsOf(nodeA).loadContacts()).map((c) => c.name), [
        'Node 1',
      ]);
      expect((await contactsOf(nodeB).loadContacts()).map((c) => c.name), [
        'Node 2',
      ]);
    });
  }, skip: skip);

  group('channels', () {
    test('channels come back in slot order with their unread counts, per node',
        () async {
      await openStorage();
      final a = channelsOf(nodeA);
      await a.saveChannels([channel(3), channel(1, unread: 2)]);

      final loaded = await a.loadChannels();
      expect(loaded.map((c) => c.index), [1, 3]);
      expect(loaded[0].unreadCount, 2);
      expect(loaded[0].psk, channel(1).psk);
      expect(await channelsOf(nodeB).loadChannels(), isEmpty);
    });

    test('an unread count changed in place is written; a dropped slot goes',
        () async {
      await openStorage();
      final store = channelsOf(nodeA);
      await store.saveChannels([channel(0), channel(1)]);
      final loaded = await store.loadChannels();
      loaded[1].unreadCount = 5;

      await store.saveChannels([loaded[1]]);

      final again = await store.loadChannels();
      expect(again.map((c) => c.index), [1]);
      expect(again.single.unreadCount, 5);
    });
  }, skip: skip);

  group('path history', () {
    test('a history is kept per node; the shared one serves a node without '
        'its own', () async {
      await openStorage();
      await StorageService().savePathHistory(contact1, history(contact1, 1));
      final a = serviceOf(nodeA);
      final b = serviceOf(nodeB);

      expect((await a.loadPathHistory(contact1))!.recentPaths.single.hopCount, 1);
      expect((await b.loadPathHistory(contact1))!.recentPaths.single.hopCount, 1);

      await a.savePathHistory(contact1, history(contact1, 2));
      final own = await a.loadPathHistory(contact1);
      expect(own!.recentPaths.single.hopCount, 2);
      expect(own.toJson(), history(contact1, 2).toJson());
      expect((await b.loadPathHistory(contact1))!.recentPaths.single.hopCount, 1);
      expect(await b.loadPathHistory(contact2), isNull);
    });

    test('clearing a contact removes its own and the shared history; '
        'clearing all removes every node\'s', () async {
      await openStorage();
      final a = serviceOf(nodeA);
      final b = serviceOf(nodeB);
      await StorageService().savePathHistory(contact1, history(contact1, 1));
      await a.savePathHistory(contact1, history(contact1, 2));
      await a.savePathHistory(contact2, history(contact2, 3));
      await b.savePathHistory(contact2, history(contact2, 4));

      await a.clearPathHistory(contact1);
      expect(await a.loadPathHistory(contact1), isNull);
      expect(await b.loadPathHistory(contact1), isNull);
      expect((await a.loadPathHistory(contact2))!.recentPaths.single.hopCount, 3);

      await b.clearAllPathHistories();
      expect(await a.loadPathHistory(contact2), isNull);
      expect(await b.loadPathHistory(contact2), isNull);
    });

    test('an unreadable row reads as none', () async {
      await openStorage();
      await MessageHistoryStorage.instance.savePathHistoryJson(
        nodeKey: nodeA.substring(0, 10),
        contactKey: contact1,
        historyJson: 'not json',
      );
      expect(await serviceOf(nodeA).loadPathHistory(contact1), isNull);
    });
  }, skip: skip);

  group('delivery observations', () {
    test('the list is replaced whole and read back in order', () async {
      await openStorage();
      final service = StorageService();
      final saved = [observation(1), observation(2), observation(3)];
      await service.saveDeliveryObservations(saved);

      expect(
        (await service.loadDeliveryObservations()).map((o) => o.toJson()),
        saved.map((o) => o.toJson()),
      );

      await service.saveDeliveryObservations([observation(4)]);
      expect(
        (await serviceOf(nodeB).loadDeliveryObservations()).map(
          (o) => o.contactKey,
        ),
        ['contact_4'],
      );
      await service.clearDeliveryObservations();
      expect(await service.loadDeliveryObservations(), isEmpty);
    });
  }, skip: skip);

  group('node state', () {
    test('the small collections live per node', () async {
      await openStorage();
      final order = ChannelOrderStore()..setPublicKeyHex = nodeA;
      await order.saveChannelOrder([3, 1, 2]);
      expect(await order.loadChannelOrder(), [3, 1, 2]);
      expect(
        await (ChannelOrderStore()..setPublicKeyHex = nodeB).loadChannelOrder(),
        isEmpty,
      );

      final groups = ChannelGroupStore()..setPublicKeyHex = nodeA;
      final group = const ChannelGroup(name: 'Ops', channelNames: ['#ops']);
      await groups.saveGroups([group]);
      await groups.saveExpandedGroupNames({'Ops'});
      await groups.saveScreenOrder(['#ops', 'Ops']);
      expect((await groups.loadGroups()).single.toJson(), group.toJson());
      expect(await groups.loadExpandedGroupNames(), {'Ops'});
      expect(await groups.loadScreenOrder(), ['#ops', 'Ops']);
      expect(
        await (ChannelGroupStore()..setPublicKeyHex = nodeB).loadGroups(),
        isEmpty,
      );

      final contactGroups = ContactGroupStore()..setPublicKeyHex = nodeA;
      await contactGroups.saveGroups([
        const ContactGroup(name: 'Family', memberKeys: ['aa']),
      ]);
      expect((await contactGroups.loadGroups()).single.memberKeys, ['aa']);

      final communities = CommunityStore()..setPublicKeyHex = nodeA;
      final community = Community.create(id: 'c1', name: 'Ops');
      await communities.addCommunity(community);
      expect((await communities.loadCommunities()).single.toJson(), community.toJson());
      expect(
        await (CommunityStore()..setPublicKeyHex = nodeB).loadCommunities(),
        isEmpty,
      );
    });

    test('the node name is read from the startup cache and outlives a '
        'restart', () async {
      final factory = fileDatabase();
      await openStorage(factory: factory);
      final a = NodeIdentityStore()..setPublicKeyHex = nodeA;
      expect(a.loadName(), isNull);
      await a.saveName('  Alpha ');
      expect(a.loadName(), 'Alpha');
      expect((NodeIdentityStore()..setPublicKeyHex = nodeB).loadName(), isNull);

      await openStorage(factory: factory);
      expect((NodeIdentityStore()..setPublicKeyHex = nodeA).loadName(), 'Alpha');
    });

    test('repeater passwords and the clock sync map are app-wide', () async {
      await openStorage();
      await serviceOf(nodeA).saveRepeaterPassword('aa11', 'one');
      await serviceOf(nodeA).setRepeaterAutoClockSyncAfterLoginEnabled(
        'aa11',
        true,
      );

      final other = serviceOf(nodeB);
      expect(await other.getRepeaterPassword('aa11'), 'one');
      expect(await other.getRepeaterAutoClockSyncAfterLoginEnabled('aa11'), isTrue);
      await other.removeRepeaterPassword('aa11');
      expect(await serviceOf(nodeA).loadRepeaterPasswords(), isEmpty);
    });
  }, skip: skip);

  group('the move from preferences', () {
    /// The preference form of every collection, written by the stores
    /// themselves in their preference mode, plus a few damaged elements.
    Future<Map<String, Object>> seedPreferences() async {
      SharedPreferences.setMockInitialValues({});
      PrefsManager.reset();
      await PrefsManager.initialize();
      await MessageHistoryStorage.instance.resetForTesting();

      await contactsOf(nodeA).saveContacts([contact(1), contact(2)]);
      await channelsOf(nodeA).saveChannels([channel(0), channel(1, unread: 4)]);
      await serviceOf(nodeA).savePathHistory(contact1, history(contact1, 1));
      await StorageService().savePathHistory(contact2, history(contact2, 2));
      await StorageService().saveDeliveryObservations([
        for (var n = 1; n <= 101; n++) observation(n),
      ]);
      await (ChannelOrderStore()..setPublicKeyHex = nodeA).saveChannelOrder([
        2,
        1,
      ]);
      final groups = ChannelGroupStore()..setPublicKeyHex = nodeA;
      await groups.saveGroups([
        const ChannelGroup(name: 'Ops', channelNames: ['#ops']),
      ]);
      await groups.saveExpandedGroupNames({'Ops'});
      await groups.saveScreenOrder(['#ops']);
      await (ContactGroupStore()..setPublicKeyHex = nodeA).saveGroups([
        const ContactGroup(name: 'Family', memberKeys: ['aa']),
      ]);
      await (CommunityStore()..setPublicKeyHex = nodeA).addCommunity(
        Community.create(id: 'c1', name: 'Ops'),
      );
      await (NodeIdentityStore()..setPublicKeyHex = nodeA).saveName('Alpha');
      await StorageService().saveRepeaterPassword('aa11', 'pw');
      await StorageService().setRepeaterAutoClockSyncAfterLoginEnabled(
        'aa11',
        true,
      );

      final prefs = PrefsManager.instance;
      final seeded = <String, Object>{
        for (final key in prefs.getKeys()) key: prefs.get(key)!,
      };
      // Damage: an element that is no contact, a channel without a slot, a
      // history that is not JSON, an observation that is no record.
      final contactsKey = 'contacts${nodeA.substring(0, 10)}';
      seeded[contactsKey] = jsonEncode([
        ...jsonDecode(seeded[contactsKey] as String) as List,
        {'publicKey': 5},
      ]);
      final channelsKey = 'channels${nodeA.substring(0, 10)}';
      seeded[channelsKey] = jsonEncode([
        ...jsonDecode(seeded[channelsKey] as String) as List,
        {'name': 'no slot'},
      ]);
      seeded['path_history_$contact3'] = 'garbage';
      seeded['delivery_observations'] = jsonEncode([
        ...jsonDecode(seeded['delivery_observations'] as String) as List,
        'not a record',
      ]);
      // What stays: settings, and the bare key of the time before scoping.
      seeded['app_settings'] = '{}';
      seeded['channel_smaz_${nodeA.substring(0, 10)}name_UHVibGlj'] = true;
      seeded['contacts'] = '[]';
      return seeded;
    }

    test('every collection moves into its table, the keys go, damage is '
        'skipped, a legacy history becomes the shared one', () async {
      final seeded = await seedPreferences();
      await openStorage(prefs: seeded);

      expect(
        (await contactsOf(nodeA).loadContacts()).map((c) => c.name),
        ['Node 1', 'Node 2'],
      );
      final channels = await channelsOf(nodeA).loadChannels();
      expect(channels.map((c) => c.index), [0, 1]);
      expect(channels[1].unreadCount, 4);
      expect(
        (await serviceOf(nodeA).loadPathHistory(contact1))!
            .recentPaths
            .single
            .hopCount,
        1,
      );
      // The legacy history serves every node.
      expect(
        (await serviceOf(nodeB).loadPathHistory(contact2))!
            .recentPaths
            .single
            .hopCount,
        2,
      );
      expect(await serviceOf(nodeA).loadPathHistory(contact3), isNull);
      final observations = await StorageService().loadDeliveryObservations();
      expect(observations, hasLength(100));
      expect(observations.first.contactKey, 'contact_2');
      expect(observations.last.contactKey, 'contact_101');
      expect(
        await (ChannelOrderStore()..setPublicKeyHex = nodeA).loadChannelOrder(),
        [2, 1],
      );
      final groups = ChannelGroupStore()..setPublicKeyHex = nodeA;
      expect((await groups.loadGroups()).single.name, 'Ops');
      expect(await groups.loadExpandedGroupNames(), {'Ops'});
      expect(await groups.loadScreenOrder(), ['#ops']);
      expect(
        (await (ContactGroupStore()..setPublicKeyHex = nodeA).loadGroups())
            .single
            .name,
        'Family',
      );
      expect(
        (await (CommunityStore()..setPublicKeyHex = nodeA).loadCommunities())
            .single
            .id,
        'c1',
      );
      expect((NodeIdentityStore()..setPublicKeyHex = nodeA).loadName(), 'Alpha');
      expect(await StorageService().getRepeaterPassword('aa11'), 'pw');
      expect(
        await StorageService().getRepeaterAutoClockSyncAfterLoginEnabled('aa11'),
        isTrue,
      );

      final left = PrefsManager.instance.getKeys();
      expect(left, {
        'app_settings',
        'channel_smaz_${nodeA.substring(0, 10)}name_UHVibGlj',
        'contacts',
      });
    });

    test('a second launch finds nothing to move and keeps the rows', () async {
      final factory = fileDatabase();
      final seeded = await seedPreferences();
      await openStorage(prefs: seeded, factory: factory);

      // The same keys again, with other contents: the rows win.
      final again = Map<String, Object>.of(seeded);
      again['contacts${nodeA.substring(0, 10)}'] = jsonEncode([]);
      again['node_identity_${nodeA.substring(0, 10)}'] = 'Bravo';
      await openStorage(prefs: again, factory: factory);

      expect(
        (await contactsOf(nodeA).loadContacts()).map((c) => c.name),
        ['Node 1', 'Node 2'],
      );
      expect((NodeIdentityStore()..setPublicKeyHex = nodeA).loadName(), 'Alpha');
      expect(
        PrefsManager.instance.getKeys().where((k) => k.startsWith('contacts')),
        ['contacts'],
      );
    });
  }, skip: skip);
}
