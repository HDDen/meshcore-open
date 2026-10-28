import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/companion_cli_entry.dart';
import 'package:meshcore_open/models/repeater_cli_entry.dart';
import 'package:meshcore_open/storage/repeater_cli_store.dart';
import 'package:meshcore_open/storage/companion_cli_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

CompanionCliEntry _entry(String node, String response) => CompanionCliEntry(
  id: 'same-id-scoped-by-node', nodeKey: node, nodeName: 'Synthetic $node',
  command: 'get wifi.pwd', response: response, status: CompanionCliStatus.replied,
  createdAt: DateTime.utc(2026, 10, 28),
);

Future<String?> _sqliteProblem() async {
  final database = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
  try {
    await database.customSelect('SELECT 1').get();
    return null;
  } catch (error) {
    return 'SQLite unavailable: $error';
  } finally {
    try { await database.close(); } catch (_) {}
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sqliteProblem = await _sqliteProblem();
  final storage = MessageHistoryStorage.instance;
  setUp(() async {
    await storage.resetForTesting();
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(() async {
    await storage.resetForTesting();
    PrefsManager.reset();
  });

  Future<void> roundTrip() async {
    final store = CompanionCliStore();
    await store.save(_entry('01' * 32, 'SYNTHETIC_A'));
    await store.save(_entry('02' * 32, 'SYNTHETIC_B'));
    final rows = await CompanionCliStore().load();
    expect(rows.length, 2);
    expect(rows.map((entry) => entry.nodeKey).toSet(), {'01' * 32, '02' * 32});
    expect(rows.map((entry) => entry.response).toSet(), {'SYNTHETIC_A', 'SYNTHETIC_B'});
    await store.save(_entry('01' * 32, 'SYNTHETIC_UPDATED'));
    final updated = await CompanionCliStore().load();
    expect(updated.length, 2);
    expect(updated.singleWhere((entry) => entry.nodeKey == '01' * 32).response, 'SYNTHETIC_UPDATED');
  }

  test('without an open native DB history fails instead of writing preferences', () async {
    final store = CompanionCliStore();
    await expectLater(store.load(), throwsStateError);
    await expectLater(store.save(_entry('01' * 32, 'SYNTHETIC')), throwsStateError);
    expect(PrefsManager.instance.getKeys(), isEmpty);
  });

  test('SQLite keeps one row per operation and no mesh-message rows', () async {
    final database = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
    await storage.initializeAndMigrate(databaseFactory: () => database);
    expect(storage.hasDatabase, isTrue);
    await roundTrip();
    final count = await database.customSelect('SELECT COUNT(*) AS n FROM history_messages').getSingle();
    expect(count.read<int>('n'), 0);
    final rows = await storage.readCompanionCliHistory();
    expect(rows.length, 2);
    final columns = await database.customSelect('PRAGMA table_info(companion_cli_history)').get();
    expect(columns.map((row) => row.read<String>('name')).toSet(), {
      'node_key', 'entry_id', 'node_name', 'created_at_ms', 'command', 'response', 'status', 'failure',
    });
    final state = await database.customSelect('SELECT COUNT(*) AS n FROM node_state').getSingle();
    expect(state.read<int>('n'), 0);
    expect(PrefsManager.instance.getKeys(), isEmpty);
  }, skip: sqliteProblem, timeout: const Timeout(Duration(seconds: 30)));

  test('repeater history is isolated by node and destination; clear rejects an old callback', () async {
    final database = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
    await storage.initializeAndMigrate(databaseFactory: () => database);
    final store = RepeaterCliStore();
    final nodeA = '01' * 32;
    final nodeB = '02' * 32;
    final repeaterA = '03' * 32;
    final repeaterB = '04' * 32;
    RepeaterCliEntry row(String node, String repeater) => RepeaterCliEntry(
      id: 'same-id', nodeKey: node, repeaterKey: repeater, nodeName: 'Synthetic node',
      repeaterName: 'Synthetic repeater', createdAt: DateTime.utc(2026),
      type: 'command', text: 'get name');
    final old = store.revision(nodeA, repeaterA);
    await store.save(row(nodeA, repeaterA));
    await store.save(row(nodeA, repeaterB));
    await store.save(row(nodeB, repeaterA));
    await CompanionCliStore().save(_entry(nodeA, 'Companion is separate'));
    await store.clear(nodeA, repeaterA);
    expect(await store.save(row(nodeA, repeaterA), revision: old), isFalse);
    expect(await store.load(nodeA, repeaterA), isEmpty);
    expect(await store.load(nodeA, repeaterB), hasLength(1));
    expect(await store.load(nodeB, repeaterA), hasLength(1));
    expect(await CompanionCliStore().load(), hasLength(1));
    expect(await RepeaterCliStore().load(nodeB, repeaterA), hasLength(1));
    final columns = await database.customSelect('PRAGMA table_info(repeater_cli_history)').get();
    expect(columns.map((row) => row.read<String>('name')).toSet(), {
      'node_key', 'repeater_key', 'entry_id', 'node_name', 'repeater_name', 'created_at_ms', 'entry_type', 'text',
    });
    expect(PrefsManager.instance.getKeys(), isEmpty);
  }, skip: sqliteProblem, timeout: const Timeout(Duration(seconds: 30)));
}
