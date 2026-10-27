import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/delivery_observation.dart';
import 'package:meshcore_open/models/path_history.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/storage/contact_store.dart';
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

  test('baseline: an unchanged path snapshot still executes an upsert', () async {
    final history = _path(0);
    await service.savePathHistory(_contactKey, history);
    final before = await changes();
    for (var i = 0; i < _saves; i++) {
      await service.savePathHistory(_contactKey, history);
    }
    final rows = await changes() - before;
    expect(rows, _saves);
    expect((await service.loadPathHistory(_contactKey))!.toJson(), history.toJson());
    report('pathUnchanged', rows);
  }, skip: sqliteProblem, timeout: timeout);

  test('baseline: changing paths are immediately readable without crossing nodes', () async {
    final other = StorageService()..setPublicKeyHex = 'cd' * 32;
    await other.savePathHistory(_contactKey, _path(100));
    for (var i = 0; i < _saves; i++) {
      await service.savePathHistory(_contactKey, _path(i));
      expect((await service.loadPathHistory(_contactKey))!.toJson(), _path(i).toJson());
    }
    expect((await other.loadPathHistory(_contactKey))!.toJson(), _path(100).toJson());
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
