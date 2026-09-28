import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_maintenance.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The history database in the write-ahead log mode it opens with now: the
// pragmas every connection gets, a database from before switching over, the
// log beside the file counted by the maintenance screen, the checkpoint at
// startup that folds the last session's log into the file, and the one
// after a vacuum. The files are opened the way production opens them,
// through MessageHistoryDatabase.setupConnection. Skipped where the host
// has no native sqlite3.

Future<String?> _sqliteProblem() async {
  try {
    final database = MessageHistoryDatabase.withExecutor(
      NativeDatabase.memory(),
    );
    await database.customSelect('SELECT 1').get();
    await database.close();
    return null;
  } catch (error) {
    return 'sqlite3 is not available to this test host: $error';
  }
}

/// Everything SQLite may keep for the database at [path]: the file itself,
/// the write-ahead log and the shared index of that log.
int _bytesOnDisk(String path) {
  var total = 0;
  for (final suffix in const ['', '-wal', '-shm']) {
    final file = File('$path$suffix');
    if (file.existsSync()) total += file.lengthSync();
  }
  return total;
}

Future<Object?> _pragma(MessageHistoryDatabase database, String name) async {
  final row = await database.customSelect('PRAGMA $name').getSingle();
  return row.data.values.first;
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = await _sqliteProblem();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mco_history_wal_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await MessageHistoryStorage.instance.resetForTesting();
    // Several tests hold two connections to one file on purpose, as a next
    // launch does over a session that never closed its database.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDown(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    await MessageHistoryStorage.instance.resetForTesting();
    PrefsManager.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    tempDir.deleteSync(recursive: true);
  });

  /// Where the maintenance screen looks for the database.
  String databasePath() =>
      '${tempDir.path}${Platform.pathSeparator}'
      '${MessageHistoryStorage.databaseFileName}';

  /// The database file opened as the app opens it.
  MessageHistoryDatabase fileDatabase() => MessageHistoryDatabase.withExecutor(
    NativeDatabase(
      File(databasePath()),
      setup: MessageHistoryDatabase.setupConnection,
    ),
  );

  Future<MessageHistoryStorage> openStorage() async {
    await MessageHistoryStorage.instance.initializeAndMigrate(
      databaseFactory: fileDatabase,
    );
    expect(MessageHistoryStorage.instance.hasDatabase, isTrue);
    return MessageHistoryStorage.instance;
  }

  /// [count] node-state rows of about 20 KB each, one transaction apiece.
  Future<void> writeRows(MessageHistoryDatabase database, int count) async {
    for (var i = 0; i < count; i++) {
      await database.writeNodeState(
        nodeKey: 'node',
        name: 'name $i',
        value: 'v' * 20000,
      );
    }
  }

  group('the connection', () {
    test('opens in write-ahead log mode, every commit synced, the log '
        'limited', () async {
      final database = fileDatabase();
      addTearDown(database.close);

      expect(await _pragma(database, 'journal_mode'), 'wal');
      expect(await _pragma(database, 'synchronous'), 2, reason: 'FULL');
      expect(await _pragma(database, 'journal_size_limit'), 4194304);
      expect(await _pragma(database, 'auto_vacuum'), 2, reason: 'INCREMENTAL');
    }, skip: skip);

    test('a database from before the change switches over at its next open '
        'and keeps its rows', () async {
      final before = MessageHistoryDatabase.withExecutor(
        NativeDatabase(File(databasePath())),
      );
      await before.writeNodeState(nodeKey: 'node', name: 'name', value: 'v');
      expect(await _pragma(before, 'journal_mode'), 'delete');
      await before.close();

      final database = fileDatabase();
      addTearDown(database.close);

      expect(await _pragma(database, 'journal_mode'), 'wal');
      expect(await database.readNodeState('node', 'name'), 'v');
    }, skip: skip);

    test('a committed write is on disk for a second connection at once', () async {
      final database = fileDatabase();
      addTearDown(database.close);
      await database.writeNodeState(nodeKey: 'node', name: 'name', value: 'v');

      final other = fileDatabase();
      addTearDown(other.close);

      expect(await other.readNodeState('node', 'name'), 'v');
    }, skip: skip);
  });

  group('the log beside the file', () {
    test('the maintenance screen counts the log and its index', () async {
      final storage = await openStorage();
      for (var i = 0; i < 40; i++) {
        await storage.writeNodeState(
          nodeKey: 'node',
          name: 'name $i',
          value: 'v' * 20000,
        );
      }
      final path = databasePath();
      final log = File('$path-wal');
      expect(
        log.existsSync() && log.lengthSync() > 512 * 1024,
        isTrue,
        reason: 'the commits sit in the log until a checkpoint',
      );

      final snapshot = await MessageHistoryMaintenance().snapshot();

      expect(snapshot!.databaseBytes, _bytesOnDisk(path));
      expect(snapshot.databaseBytes, greaterThan(File(path).lengthSync()));
    }, skip: skip);

    test('the startup checkpoint folds the last session\'s log into the file',
        () async {
      // A session that wrote and never closed its database, as the app does.
      final session = fileDatabase();
      addTearDown(session.close);
      await writeRows(session, 40);
      final path = databasePath();
      final log = File('$path-wal');
      expect(log.lengthSync(), greaterThan(512 * 1024));

      final storage = await openStorage();

      expect(log.lengthSync(), 0);
      expect(File(path).lengthSync(), greaterThan(512 * 1024));
      expect(await storage.readNodeState('node', 'name 39'), 'v' * 20000);
    }, skip: skip);

    test('a full vacuum leaves no log behind and keeps both modes', () async {
      final storage = await openStorage();
      for (var i = 0; i < 40; i++) {
        await storage.writeNodeState(
          nodeKey: 'node',
          name: 'name $i',
          value: 'v' * 20000,
        );
      }
      for (var i = 0; i < 40; i++) {
        await storage.deleteNodeState('node', 'name $i');
      }

      await storage.fullVacuum();

      final path = databasePath();
      final log = File('$path-wal');
      expect(!log.existsSync() || log.lengthSync() == 0, isTrue);
      final stats = await storage.maintenanceStats();
      expect(stats!.freePageCount, 0);
      expect(stats.autoVacuumMode, 2);
      final snapshot = await MessageHistoryMaintenance().snapshot();
      expect(snapshot!.databaseBytes, _bytesOnDisk(path));
      final other = fileDatabase();
      addTearDown(other.close);
      expect(await _pragma(other, 'journal_mode'), 'wal');
    }, skip: skip);
  });
}
