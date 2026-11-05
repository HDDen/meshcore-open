import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/delivery_observation.dart';
import 'package:meshcore_open/models/path_history.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/storage/contact_store.dart';
import 'package:meshcore_open/storage/channel_store.dart';
import 'package:meshcore_open/storage/contact_discovery_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('Synthetic preferences without a directory');
  }
}

const _node = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _saves = 8;
const _observationCount = 16;
final _contactKey = 'ab' * 32;

Contact _contact(int index) => Contact(
  publicKey: Uint8List.fromList(List.generate(32, (i) => (index * 32 + i) & 0xff)),
  name: 'Synthetic relay $index',
  type: 2,
  pathLength: 1,
  path: Uint8List.fromList([index + 1]),
  lastSeen: DateTime.utc(2026, 1, 1),
);

ContactPathHistory _path(int sequence) => ContactPathHistory(
  contactPubKeyHex: _contactKey,
  recentPaths: [PathRecord(
    hopCount: 1,
    tripTimeMs: 200 + sequence,
    timestamp: DateTime.utc(2026, 1, 1).add(Duration(seconds: sequence)),
    wasFloodDiscovery: false,
    pathBytes: [0x17],
    successCount: sequence + 1,
    failureCount: 0,
  )],
);

DeliveryObservation _observation(int index) => DeliveryObservation(
  contactKey: _contactKey,
  pathLength: 1,
  messageBytes: 32,
  secondsSinceLastRx: index,
  isFlood: false,
  deliveryMs: 200 + index,
  timestamp: DateTime.utc(2026, 1, 1).add(Duration(seconds: index)),
);

Future<String?> _sqliteProblem() async {
  final database = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
  try {
    await database.customSelect('SELECT 1').get();
    return null;
  } catch (error) {
    return 'sqlite3 is not available to this test host: $error';
  } finally {
    try {
      await database.close();
    } catch (_) {
      // На машине без SQLite executor мог не открыться даже для probe.
    }
  }
}

// Настоящие stores и SQL над синтетическими данными. total_changes считает
// затронутые строки, не транзакции, fsync, физические записи или энергию.
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sqliteProblem = await _sqliteProblem();
  const timeout = Timeout(Duration(seconds: 30));
  final storage = MessageHistoryStorage.instance;
  late MessageHistoryDatabase database;
  late StorageService service;
  late PathProviderPlatform originalPaths;

  setUpAll(() {
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
  });
  tearDownAll(() { PathProviderPlatform.instance = originalPaths; });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await storage.resetForTesting();
    database = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
    await storage.initializeAndMigrate(databaseFactory: () => database);
    service = StorageService()..setPublicKeyHex = _node;
  });
  tearDown(() async {
    await storage.resetForTesting();
    PrefsManager.reset();
  });

  Future<int> changes() async {
    final row = await database.customSelect('SELECT total_changes() AS n').getSingle();
    return row.read<int>('n');
  }

  void report(String scenario, int rows) {
    debugPrint('[SecondaryPersistenceBaseline] scenario=$scenario '
        'saves=$_saves changedRows=$rows; in-memory SQLite, not energy or commits');
  }

  test('baseline: saving identical contact instances already skips SQL changes', () async {
    final contacts = ContactStore()..setPublicKeyHex = _node;
    final values = [_contact(0), _contact(1)];
    await contacts.saveContacts(values);
    final before = await changes();
    for (var i = 0; i < _saves; i++) {
      await contacts.saveContacts(values);
    }
    final rows = await changes() - before;
    expect(rows, 0);
    expect((await contacts.loadContacts()).map((c) => c.name), values.map((c) => c.name));
    report('contactsSameInstances', rows);
  }, skip: sqliteProblem, timeout: timeout);

  test('baseline: equal replacement contacts are written without losing values', () async {
    final contacts = ContactStore()..setPublicKeyHex = _node;
    await contacts.saveContacts([_contact(0), _contact(1)]);
    final before = await changes();
    for (var i = 0; i < _saves; i++) {
      await contacts.saveContacts([_contact(0), _contact(1)]);
    }
    final rows = await changes() - before;
    expect(rows, _saves * 2);
    expect((await contacts.loadContacts()).map((c) => c.name),
        ['Synthetic relay 0', 'Synthetic relay 1']);
    report('contactsEqualReplacements', rows);
  }, skip: sqliteProblem, timeout: timeout);

  test('U10b: identical path snapshots do not update the SQL row', () async {
    final history = _path(0);
    await service.savePathHistory(_contactKey, history);
    final before = await changes();
    for (var i = 0; i < _saves; i++) {
      await service.savePathHistory(_contactKey, history);
    }
    final rows = await changes() - before;
    expect(rows, 0);
    expect((await service.loadPathHistory(_contactKey))!.toJson(), history.toJson());
    report('pathUnchanged', rows);
  }, skip: sqliteProblem, timeout: timeout);

  test('baseline: changing paths are immediately readable without crossing nodes', () async {
    final other = StorageService()..setPublicKeyHex = 'cd' * 32;
    await other.savePathHistory(_contactKey, _path(100));
    final before = await changes();
    for (var i = 0; i < _saves; i++) {
      await service.savePathHistory(_contactKey, _path(i));
      expect((await service.loadPathHistory(_contactKey))!.toJson(), _path(i).toJson());
    }
    expect((await other.loadPathHistory(_contactKey))!.toJson(), _path(100).toJson());
    final rows = await changes() - before;
    expect(rows, _saves);
    report('pathChanged', rows);
  }, skip: sqliteProblem, timeout: timeout);

  test('U10b baseline: equal channel snapshots already skip SQL and one unread change updates one row', () async {
    final channels = ChannelStore()..setPublicKeyHex = _node;
    List<Channel> snapshot() => [
      for (var i = 0; i < 17; i++)
        Channel(index: i, name: 'Channel $i', psk: Uint8List(16)..[0] = i + 1),
    ];
    await channels.saveChannels(snapshot());
    final before = await changes();
    for (var i = 0; i < _saves; i++) {
      // Distinct model objects: this store compares the persisted content.
      await channels.saveChannels(snapshot());
    }
    final unchangedRows = await changes() - before;
    expect(unchangedRows, 0);
    report('U10bChannelListUnchanged', unchangedRows);

    final updated = snapshot();
    updated[3].unreadCount = 9;
    await channels.saveChannels(updated);
    expect(await changes() - before, 1);
    final loaded = await channels.loadChannels();
    expect(loaded, hasLength(17));
    expect(loaded.singleWhere((channel) => channel.index == 3).unreadCount, 9);
  }, skip: sqliteProblem, timeout: timeout);

  test('U10b baseline: discovered contacts skip identical instances and update only a replaced row', () async {
    final discovered = ContactDiscoveryStore();
    final contacts = [_contact(0), _contact(1), _contact(2)];
    await discovered.saveContacts(contacts);
    final before = await changes();
    for (var i = 0; i < _saves; i++) {
      await discovered.saveContacts(contacts);
    }
    final unchangedRows = await changes() - before;
    expect(unchangedRows, 0);
    report('U10bDiscoveryUnchanged', unchangedRows);

    await discovered.saveContacts([contacts[0], _contact(1), contacts[2]]);
    expect(await changes() - before, 1);
    expect((await discovered.loadContacts()).map((contact) => contact.name),
        unorderedEquals(contacts.map((contact) => contact.name)));
  }, skip: sqliteProblem, timeout: timeout);

  test('U10b baseline: queued channel saves capture node and mutable unread count at entry', () async {
    final channels = ChannelStore()..setPublicKeyHex = _node;
    final first = Channel(index: 2, name: 'First', psk: Uint8List(16)..[0] = 1,
        unreadCount: 3);
    final saveFirst = channels.saveChannels([first]);
    first.unreadCount = 99;
    channels.setPublicKeyHex = 'cd' * 32;
    final second = Channel(index: 2, name: 'Second', psk: Uint8List(16)..[0] = 2);
    final saveSecond = channels.saveChannels([second]);
    await Future.wait([saveFirst, saveSecond]);

    final original = await (ChannelStore()..setPublicKeyHex = _node).loadChannels();
    final other = await channels.loadChannels();
    expect(original.single.name, 'First');
    expect(original.single.unreadCount, 3);
    expect(other.single.name, 'Second');
    expect(other.single.unreadCount, 0);
  }, skip: sqliteProblem, timeout: timeout);

  test('U10b baseline: an already started path save stays with its original node', () async {
    final other = StorageService()..setPublicKeyHex = 'cd' * 32;
    await other.savePathHistory(_contactKey, _path(100));
    final save = service.savePathHistory(_contactKey, _path(1));
    service.setPublicKeyHex = 'cd' * 32;
    await save;

    final original = StorageService()..setPublicKeyHex = _node;
    expect((await original.loadPathHistory(_contactKey))!.toJson(), _path(1).toJson());
    expect((await service.loadPathHistory(_contactKey))!.toJson(), _path(100).toJson());
  }, skip: sqliteProblem, timeout: timeout);

  test('U10b baseline: clearing a path removes the local and shared rows, preserving another node', () async {
    final shared = StorageService();
    final other = StorageService()..setPublicKeyHex = 'cd' * 32;
    await shared.savePathHistory(_contactKey, _path(0));
    expect((await service.loadPathHistory(_contactKey))!.toJson(), _path(0).toJson());
    await other.savePathHistory(_contactKey, _path(100));
    await service.savePathHistory(_contactKey, _path(1));
    await service.clearPathHistory(_contactKey);

    expect(await service.loadPathHistory(_contactKey), isNull);
    expect(await shared.loadPathHistory(_contactKey), isNull);
    expect((await other.loadPathHistory(_contactKey))!.toJson(), _path(100).toJson());
    // An identical value after a clear must insert again, never be swallowed
    // by a cache claiming that it had already been saved.
    await service.savePathHistory(_contactKey, _path(1));
    expect((await service.loadPathHistory(_contactKey))!.toJson(), _path(1).toJson());
  }, skip: sqliteProblem, timeout: timeout);

  test('U10b baseline: a rolled-back path save does not suppress the following committed save', () async {
    await service.savePathHistory(_contactKey, _path(0));
    final failure = StateError('synthetic path transaction rollback');
    await expectLater(database.transaction(() async {
      await service.savePathHistory(_contactKey, _path(1));
      throw failure;
    }), throwsA(same(failure)));

    expect((await service.loadPathHistory(_contactKey))!.toJson(), _path(0).toJson());
    await service.savePathHistory(_contactKey, _path(1));
    expect((await service.loadPathHistory(_contactKey))!.toJson(), _path(1).toJson());
  }, skip: sqliteProblem, timeout: timeout);

  test('U10b: equivalent new path objects also avoid SQL updates', () async {
    await service.savePathHistory(_contactKey, _path(0));
    final before = await changes();
    for (var i = 0; i < _saves; i++) {
      await service.savePathHistory(_contactKey, _path(0));
    }
    final rows = await changes() - before;
    expect(rows, 0);
    expect((await service.loadPathHistory(_contactKey))!.toJson(), _path(0).toJson());
    report('pathEqualNewObjects', rows);
  }, skip: sqliteProblem, timeout: timeout);

  test('U10b: another writer invalidates an earlier same-value save', () async {
    await service.savePathHistory(_contactKey, _path(0));
    final independent = StorageService()..setPublicKeyHex = _node;
    await independent.savePathHistory(_contactKey, _path(1));
    final before = await changes();
    // The same caller saved this value before, but the current row differs.
    await service.savePathHistory(_contactKey, _path(0));
    expect(await changes() - before, 1);
    expect((await independent.loadPathHistory(_contactKey))!.toJson(), _path(0).toJson());
  }, skip: sqliteProblem, timeout: timeout);

  test('U10b: equality with a shared fallback still inserts the node-specific row', () async {
    final shared = StorageService();
    await shared.savePathHistory(_contactKey, _path(0));
    expect((await service.loadPathHistory(_contactKey))!.toJson(), _path(0).toJson());
    final before = await changes();
    await service.savePathHistory(_contactKey, _path(0));
    expect(await changes() - before, 1);

    // The explicit local snapshot must survive a later change of the shared
    // fallback, even though the initial read returned the same JSON.
    await shared.savePathHistory(_contactKey, _path(100));
    expect((await service.loadPathHistory(_contactKey))!.toJson(), _path(0).toJson());
    expect((await shared.loadPathHistory(_contactKey))!.toJson(), _path(100).toJson());
  }, skip: sqliteProblem, timeout: timeout);

  test('U10b: an empty path snapshot remains a saved local value', () async {
    await service.savePathHistory(_contactKey, _path(0));
    final empty = ContactPathHistory(contactPubKeyHex: _contactKey, recentPaths: []);
    final before = await changes();
    await service.savePathHistory(_contactKey, empty);
    expect(await changes() - before, 1);
    final afterFirst = await changes();
    for (var i = 0; i < _saves; i++) {
      await service.savePathHistory(_contactKey, empty);
    }
    expect(await changes() - afterFirst, 0);
    final loaded = await service.loadPathHistory(_contactKey);
    expect(loaded, isNotNull);
    expect(loaded!.recentPaths, isEmpty);
  }, skip: sqliteProblem, timeout: timeout);

  for (final sliding in [false, true]) {
    test('baseline: delivery observations replace the whole list, sliding=$sliding', () async {
      List<DeliveryObservation> values(int offset) =>
          List.generate(_observationCount, (i) => _observation(i + offset));
      await service.saveDeliveryObservations(values(0));
      final before = await changes();
      for (var i = 0; i < _saves; i++) {
        final next = values(sliding ? i + 1 : 0);
        await service.saveDeliveryObservations(next);
        expect((await service.loadDeliveryObservations()).map((o) => o.toJson()),
            next.map((o) => o.toJson()));
      }
      final rows = await changes() - before;
      expect(rows, _saves * _observationCount * 2);
      report(sliding ? 'observationsSlidingWindow' : 'observationsUnchanged', rows);

      await service.saveDeliveryObservations([]);
      expect(await service.loadDeliveryObservations(), isEmpty);
    }, skip: sqliteProblem, timeout: timeout);
  }

  test('baseline: identical node state is written and stays scoped by node', () async {
    const name = 'synthetic_a7_snapshot';
    final value = jsonEncode({'count': 2});
    await storage.writeNodeState(nodeKey: _node, name: name, value: value);
    final before = await changes();
    for (var i = 0; i < _saves; i++) {
      await storage.writeNodeState(nodeKey: _node, name: name, value: value);
    }
    final rows = await changes() - before;
    expect(rows, _saves);
    expect(await storage.readNodeState(_node, name), value);
    expect(await storage.readNodeState('cd' * 32, name), isNull);
    report('nodeStateUnchanged', rows);
  }, skip: sqliteProblem, timeout: timeout);
}
