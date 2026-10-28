import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/companion_cli_entry.dart';
import 'package:meshcore_open/storage/companion_cli_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<String?> _sqliteProblem() async {
  final database = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
  try {
    await database.customSelect('SELECT 1').get();
    return null;
  } catch (error) {
    return 'SQLite unavailable: $error';
  } finally {
    try {
      await database.close();
    } catch (_) {}
  }
}

// Инварианты прежнего baseline сохранены для нового SQL-хранилища:
// reopen/изоляция/отсутствие CLI prefs; способ записи теперь отдельная таблица.
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sqliteProblem = await _sqliteProblem();
  final storage = MessageHistoryStorage.instance;

  test('baseline: CLI rows survive a database reopen without entering preferences and scoped delete keeps other rows', () async {
    await storage.resetForTesting();
    SharedPreferences.setMockInitialValues({'cli-baseline-sentinel': 'unchanged'});
    PrefsManager.reset();
    await PrefsManager.initialize();
    final directory = await Directory.systemTemp.createTemp('mcoa-cli-baseline-');
    final file = File('${directory.path}${Platform.pathSeparator}history.sqlite');
    addTearDown(() async {
      await storage.resetForTesting();
      PrefsManager.reset();
      await directory.delete(recursive: true);
    });
    MessageHistoryDatabase open() => MessageHistoryDatabase.withExecutor(NativeDatabase(file));
    final nodeA = '01' * 32;
    final nodeB = '02' * 32;
    const id = 'same-operation-id-in-two-nodes';
    CompanionCliEntry entry(String node) => CompanionCliEntry(
      id: id, nodeKey: node, nodeName: 'Synthetic $node',
      command: 'set name Synthetic', response: 'SYNTHETIC_OK',
      status: CompanionCliStatus.replied, createdAt: DateTime.utc(2026, 10, 28),
    );

    await storage.initializeAndMigrate(databaseFactory: open);
    expect(storage.hasDatabase, isTrue);
    final store = CompanionCliStore();
    await store.save(entry(nodeA));
    await store.save(entry(nodeB));
    await storage.writeNodeState(nodeKey: nodeA, name: 'cli-baseline-other-state', value: 'SYNTHETIC_SETTING');
    expect(PrefsManager.instance.getKeys(), {'cli-baseline-sentinel'});

    await storage.resetForTesting();
    await storage.initializeAndMigrate(databaseFactory: open);
    final reloaded = await CompanionCliStore().load();
    expect(reloaded.map((row) => row.nodeKey).toSet(), {nodeA, nodeB});
    expect(reloaded.every((row) => row.response == 'SYNTHETIC_OK'), isTrue);

    await store.clear(nodeA);
    expect((await CompanionCliStore().load()).single.nodeKey, nodeB);
    expect(await storage.readNodeState(nodeA, 'cli-baseline-other-state'), 'SYNTHETIC_SETTING');
    expect(PrefsManager.instance.getString('cli-baseline-sentinel'), 'unchanged');
    expect(PrefsManager.instance.getKeys(), {'cli-baseline-sentinel'});
  }, skip: sqliteProblem, timeout: const Timeout(Duration(seconds: 30)));

  test('schema 2 upgrades to typed CLI tables without changing existing message or node rows', () async {
    final directory = await Directory.systemTemp.createTemp('mcoa-cli-schema-');
    final file = File('${directory.path}${Platform.pathSeparator}history.sqlite');
    MessageHistoryDatabase? current;
    addTearDown(() async {
      await current?.close();
      await directory.delete(recursive: true);
    });
    final old = MessageHistoryDatabase.withExecutor(NativeDatabase(file,
      setup: MessageHistoryDatabase.setupConnection));
    current = old;
    await old.customSelect('SELECT 1').get();
    await old.writeNodeState(nodeKey: '01' * 32, name: 'existing-setting', value: 'preserve');
    await old.customStatement('''
INSERT INTO history_messages
 (kind, storage_key, message_id, timeline_at_ms, timestamp_ms, is_outgoing,
  is_cli, status, raw_text, search_text, contains_marker, message_json)
VALUES (0, 'synthetic-scope', 'existing-message', 1, 1, 0, 0, 0,
        'Synthetic existing text', 'Synthetic existing text', 0, '{}')
''');
    // Синтетическая предыдущая схема: новые CLI-таблицы в ней отсутствуют.
    await old.customStatement('DROP TABLE companion_cli_history');
    await old.customStatement('DROP TABLE repeater_cli_history');
    await old.customStatement('PRAGMA user_version = 2');
    await old.close();
    current = null;

    final upgraded = MessageHistoryDatabase.withExecutor(NativeDatabase(file,
      setup: MessageHistoryDatabase.setupConnection));
    current = upgraded;
    expect(await upgraded.readCompanionCliHistory(), isEmpty);
    expect(await upgraded.readRepeaterCliHistory('01' * 32, '02' * 32), isEmpty);
    expect(await upgraded.readNodeState('01' * 32, 'existing-setting'), 'preserve');
    final message = await upgraded.customSelect('SELECT raw_text FROM history_messages').getSingle();
    expect(message.read<String>('raw_text'), 'Synthetic existing text');
    final version = await upgraded.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 3);
    final synchronous = await upgraded.customSelect('PRAGMA synchronous').getSingle();
    expect(synchronous.data.values.single, 2);
  }, skip: sqliteProblem, timeout: const Timeout(Duration(seconds: 30)));
}
