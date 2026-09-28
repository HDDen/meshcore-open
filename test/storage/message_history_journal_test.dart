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

// What the history database promises about its file on disk, pinned before
// its journal changes: a committed write is on disk for anyone who opens the
// file, the maintenance screen reports what the database keeps on disk, a
// full vacuum leaves no log behind, and the multi-row writes keep their
// meaning whatever carries their statements. The database needs a native
// sqlite3 the test host can load; when it cannot, every test here is skipped
// rather than failed.

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
/// a write-ahead log and the shared index of that log.
int _bytesOnDisk(String path) {
  var total = 0;
  for (final suffix in const ['', '-wal', '-shm']) {
    final file = File('$path$suffix');
    if (file.existsSync()) total += file.lengthSync();
  }
  return total;
}

WardriveSampleRow _sample(String id, int timestampMs) => (
  id: id,
  timestampMs: timestampMs,
  publicKeyHex: 'aa$id',
  pingSuccess: true,
  sampleJson: '{"id":"$id"}',
);

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = await _sqliteProblem();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mco_history_journal_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await MessageHistoryStorage.instance.resetForTesting();
  });

  tearDown(() async {
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

  MessageHistoryDatabase fileDatabase([String? path]) =>
      MessageHistoryDatabase.withExecutor(
        NativeDatabase(File(path ?? databasePath())),
      );

  /// Opens the storage over the database file the maintenance screen looks
  /// at, as a launch does.
  Future<MessageHistoryStorage> openStorage() async {
    await MessageHistoryStorage.instance.initializeAndMigrate(
      databaseFactory: fileDatabase,
    );
    expect(MessageHistoryStorage.instance.hasDatabase, isTrue);
    return MessageHistoryStorage.instance;
  }

  /// Writes [count] node-state rows of about 20 KB each, one transaction
  /// apiece, as the stores write.
  Future<void> writeRows(MessageHistoryStorage storage, int count) async {
    for (var i = 0; i < count; i++) {
      await storage.writeNodeState(
        nodeKey: 'node',
        name: 'name $i',
        value: 'v' * 20000,
      );
    }
  }

  group('the file on disk', () {
    test('a committed write is on disk for a second connection at once', () async {
      // Two connections to one file, as a second process would open it. The
      // warning drift prints about a second database object is meant for two
      // objects over one executor, which these are not.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
      );
      final database = fileDatabase();
      addTearDown(database.close);
      await database.writeNodeState(
        nodeKey: 'node',
        name: 'name',
        value: 'value',
      );

      final other = fileDatabase();
      addTearDown(other.close);

      expect(await other.readNodeState('node', 'name'), 'value');
    }, skip: skip);

    test('the maintenance screen reports what the database keeps on disk', () async {
      final storage = await openStorage();
      await writeRows(storage, 40);

      final snapshot = await MessageHistoryMaintenance().snapshot();

      expect(snapshot, isNotNull);
      expect(snapshot!.databasePath, databasePath());
      expect(snapshot.databaseBytes, greaterThan(512 * 1024));
      expect(snapshot.databaseBytes, _bytesOnDisk(databasePath()));
    }, skip: skip);

    test('a full vacuum leaves no free pages and no write-ahead log behind', () async {
      final storage = await openStorage();
      await writeRows(storage, 40);
      for (var i = 0; i < 40; i++) {
        await storage.deleteNodeState('node', 'name $i');
      }

      await storage.fullVacuum();

      final stats = await storage.maintenanceStats();
      expect(stats, isNotNull);
      expect(stats!.freePageCount, 0);
      final log = File('${databasePath()}-wal');
      expect(!log.existsSync() || log.lengthSync() == 0, isTrue);
      final snapshot = await MessageHistoryMaintenance().snapshot();
      expect(snapshot!.databaseBytes, _bytesOnDisk(databasePath()));
    }, skip: skip);
  });

  group('multi-row writes', () {
    test('a wardrive import adds what is not there yet and says how many', () async {
      final database = fileDatabase();
      addTearDown(database.close);

      final first = await database.importWardriveSamples([
        _sample('a', 1),
        _sample('b', 2),
      ], cap: 6000);
      final second = await database.importWardriveSamples([
        _sample('b', 2),
        _sample('c', 3),
      ], cap: 6000);

      expect(first, 2);
      expect(second, 1);
      expect(await database.countWardriveSamples(), 3);
      expect(await database.importWardriveSamples(const [], cap: 6000), 0);
    }, skip: skip);

    test('a wardrive import trims to the cap after adding', () async {
      final database = fileDatabase();
      addTearDown(database.close);

      final added = await database.importWardriveSamples([
        for (var i = 0; i < 5; i++) _sample('s$i', i),
      ], cap: 3);

      expect(added, 5);
      expect(await database.countWardriveSamples(), 3);
      expect(
        await database.readWardriveSamples(limit: 10),
        ['{"id":"s4"}', '{"id":"s3"}', '{"id":"s2"}'],
      );
    }, skip: skip);

    test('discovered contacts are upserted and deleted in one write, and an '
        'update keeps its place', () async {
      final database = fileDatabase();
      addTearDown(database.close);
      await database.writeDiscoveredContacts(
        upserts: {'k1': 'one', 'k2': 'two', 'k3': 'three'},
        deleteKeys: const [],
      );

      await database.writeDiscoveredContacts(
        upserts: {'k1': 'one again', 'k4': 'four'},
        deleteKeys: const ['k2'],
      );

      expect(await database.readDiscoveredContacts(), [
        'one again',
        'three',
        'four',
      ]);
    }, skip: skip);

    test('the delivery observations are replaced whole', () async {
      final database = fileDatabase();
      addTearDown(database.close);
      await database.replaceDeliveryObservations(const ['a', 'b']);

      await database.replaceDeliveryObservations(const ['c']);
      expect(await database.readDeliveryObservations(), ['c']);

      await database.replaceDeliveryObservations(const []);
      expect(await database.readDeliveryObservations(), isEmpty);
    }, skip: skip);

    test('node contacts and channels are written by difference', () async {
      final database = fileDatabase();
      addTearDown(database.close);
      await database.writeNodeContacts(
        nodeKey: 'node',
        upserts: {'c1': 'one', 'c2': 'two'},
        deleteKeys: const [],
      );
      await database.writeNodeChannels(
        nodeKey: 'node',
        upserts: {0: 'zero', 1: 'one'},
        deleteIndexes: const [],
      );

      await database.writeNodeContacts(
        nodeKey: 'node',
        upserts: {'c2': 'two again'},
        deleteKeys: const ['c1'],
      );
      await database.writeNodeChannels(
        nodeKey: 'node',
        upserts: {1: 'one again', 2: 'two'},
        deleteIndexes: const [0],
      );

      expect(await database.readNodeContacts('node'), ['two again']);
      expect(await database.readNodeChannels('node'), ['one again', 'two']);
    }, skip: skip);
  });
}
