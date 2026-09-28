import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/map_tile_cache_service.dart';
import 'package:meshcore_open/storage/map_tile_cache_database.dart';

// The tile record database of Windows and Linux: the move of the JSON index
// flutter_cache_manager wrote into it, the startup that runs the move, and
// the cache screen reading the same inventory afterwards. The database needs
// a native sqlite3 the test host can load; when it cannot, every test here
// is skipped rather than failed.

MapTileCacheDatabase _memoryDatabase() =>
    MapTileCacheDatabase.withExecutor(NativeDatabase.memory());

Future<String?> _sqliteProblem() async {
  try {
    final database = _memoryDatabase();
    await database.countRecords();
    await database.close();
    return null;
  } catch (error) {
    return 'sqlite3 is not available to this test host: $error';
  }
}

/// An executor that fails to open, as a database on an unwritable path
/// would. Closing it is nothing, since nothing was opened; drift's own
/// `LazyDatabase.close` would rethrow the failure instead.
class _UnopenableExecutor extends LazyDatabase {
  _UnopenableExecutor()
    : super(() => throw StateError('the database cannot be opened'));

  @override
  Future<void> close() async {}
}

const osm = 'https://tile.openstreetmap.org/12/2345/1234.png';
const stadia = 'https://tiles.stadiamaps.com/tiles/outdoors/10/1/2@2x.png';
const yandex =
    'https://tiles.api-maps.yandex.ru/v1/tiles/?lang=ru_RU&l=map'
    '&projection=web_mercator&maptype=map&x=9962&y=5889&z=14&scale=2.0';

CacheObject _record(
  String key, {
  String? url,
  String? relativePath,
  String? eTag,
  int? length,
  DateTime? touched,
}) => CacheObject(
  url ?? key,
  key: key,
  relativePath: relativePath ?? '${key.hashCode.toRadixString(16)}.png',
  validTill: DateTime.fromMillisecondsSinceEpoch(1818692015954),
  eTag: eTag,
  length: length,
  touched: touched,
);

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = await _sqliteProblem();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mco_tile_db_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    tempDir.deleteSync(recursive: true);
  });

  File indexFile() => File(
    '${tempDir.path}${Platform.pathSeparator}'
    '${MapTileCacheDatabase.legacyIndexFileName}',
  );

  /// An index as the package's JSON repository writes it.
  Future<File> writeIndex(List<CacheObject> records) async {
    final repo = JsonCacheInfoRepository.withFile(indexFile());
    await repo.open();
    for (final record in records) {
      await repo.insert(record, setTouchedToNow: record.touched == null);
    }
    await repo.close();
    return indexFile();
  }

  Future<MapTileCacheDatabase> openDatabase() async {
    final database = _memoryDatabase();
    addTearDown(database.close);
    return database;
  }

  group('moving the JSON index', () {
    test('every record reaches the table with its fields, the file goes and '
        'the counts are reported', () async {
      final touched = DateTime.fromMillisecondsSinceEpoch(1787528910467);
      final file = await writeIndex([
        _record(osm),
        _record(
          stadia,
          url: '$stadia?api_key=k1',
          relativePath: 'stadia.png',
          eTag: '"e1"',
          length: 7000,
        ),
        _record(
          yandex,
          url: '$yandex&apikey=k&signature=s',
          relativePath: 'yandex.png',
          eTag: '"e2"',
          length: 25160,
          touched: touched,
        ),
      ]);
      final database = await openDatabase();

      final result = await database.importLegacyIndex(file);

      expect(result.records, 3);
      expect(result.added, 3);
      expect(result.skipped, 0);
      expect(result.fileWasCorrupt, isFalse);
      expect(file.existsSync(), isFalse);

      final byKey = {
        for (final record in await database.allRecords()) record.key: record,
      };
      expect(byKey.keys, unorderedEquals([osm, stadia, yandex]));
      expect(byKey.values.map((r) => r.id).toSet(), hasLength(3));

      final plain = byKey[osm]!;
      expect(plain.url, osm);
      expect(plain.eTag, isNull);
      expect(plain.length, isNull);
      expect(plain.touched, isNotNull);

      final full = byKey[yandex]!;
      expect(full.url, '$yandex&apikey=k&signature=s');
      expect(full.relativePath, 'yandex.png');
      expect(full.eTag, '"e2"');
      expect(full.length, 25160);
      expect(full.validTill, DateTime.fromMillisecondsSinceEpoch(1818692015954));
      expect(full.touched, touched);

      // A second run finds nothing to move.
      final again = await database.importLegacyIndex(file);
      expect(again.records, 0);
      expect(await database.countRecords(), 3);
    }, skip: skip);

    test('a key already in the table keeps its row', () async {
      final database = await openDatabase();
      final existing = await database.insertRecord(
        _record(osm, relativePath: 'kept.png', length: 1),
        setTouchedToNow: true,
      );
      final file = await writeIndex([
        _record(osm, relativePath: 'stale.png', length: 2),
        _record(stadia, length: 3),
      ]);

      final result = await database.importLegacyIndex(file);

      expect(result.records, 2);
      expect(result.added, 1);
      final kept = (await database.findRecord(osm))!;
      expect(kept.id, existing.id);
      expect(kept.relativePath, 'kept.png');
      expect(kept.length, 1);
      expect((await database.findRecord(stadia))!.length, 3);
    }, skip: skip);

    test('an element that is not a record is skipped, the rest arrive', () async {
      final good = _record(osm, length: 5).toMap(setTouchedToNow: false)
        ..[CacheObject.columnId] = 1;
      final alsoGood = _record(stadia, length: 6).toMap(setTouchedToNow: false)
        ..[CacheObject.columnId] = 4;
      final file = indexFile()
        ..writeAsStringSync(
          jsonEncode([
            good,
            'garbage',
            {'url': 1},
            {'url': 'https://x/1/2/3.png', 'relativePath': 'x.png'},
            alsoGood,
          ]),
        );
      final database = await openDatabase();

      final result = await database.importLegacyIndex(file);

      expect(result.records, 2);
      expect(result.added, 2);
      expect(result.skipped, 3);
      expect(file.existsSync(), isFalse);
      expect(
        (await database.allRecords()).map((r) => r.key),
        unorderedEquals([osm, stadia]),
      );
    }, skip: skip);

    test('a file that will not decode is set aside and nothing is imported',
        () async {
      final file = indexFile()..writeAsStringSync('[{"url": "broken"');
      final database = await openDatabase();

      final result = await database.importLegacyIndex(file);

      expect(result.fileWasCorrupt, isTrue);
      expect(result.records, 0);
      expect(file.existsSync(), isFalse);
      final quarantined = File(result.quarantinedPath!);
      expect(quarantined.existsSync(), isTrue);
      expect(quarantined.path, startsWith('${file.path}.corrupt-'));
      expect(quarantined.readAsStringSync(), '[{"url": "broken"');
      expect(await database.countRecords(), 0);
    }, skip: skip);

    test('a file that is not a list is corrupt too', () async {
      final file = indexFile()..writeAsStringSync('{"url": "not a list"}');
      final database = await openDatabase();
      final result = await database.importLegacyIndex(file);
      expect(result.fileWasCorrupt, isTrue);
      expect(file.existsSync(), isFalse);
    }, skip: skip);

    test('no file means nothing to do', () async {
      final database = await openDatabase();
      final result = await database.importLegacyIndex(indexFile());
      expect(result.records, 0);
      expect(result.added, 0);
      expect(result.fileWasCorrupt, isFalse);
    }, skip: skip);

    test('the temporary file of an unfinished write goes with the index',
        () async {
      final file = await writeIndex([_record(osm)]);
      final temporary = File('${file.path}.tmp')..writeAsStringSync('[');
      final database = await openDatabase();

      await database.importLegacyIndex(file);

      expect(file.existsSync(), isFalse);
      expect(temporary.existsSync(), isFalse);
    }, skip: skip);
  });

  group('openForThisPlatform', () {
    test('answers null where the package keeps its own repository', () async {
      expect(
        await MapTileCacheRepository.openForThisPlatform(
          useDatabase: false,
          databaseFactory: _memoryDatabase,
          supportDirectory: () async => tempDir,
        ),
        isNull,
      );
    });

    test('with an index present it moves the index, puts up the notice and '
        'keeps the sweep off', () async {
      final file = await writeIndex([_record(osm), _record(stadia)]);
      var noticed = 0;

      final repository = await MapTileCacheRepository.openForThisPlatform(
        useDatabase: true,
        databaseFactory: _memoryDatabase,
        supportDirectory: () async => tempDir,
        onImportStarted: () async => noticed++,
      );

      expect(repository, isNotNull);
      addTearDown(repository!.database.close);
      expect(noticed, 1);
      expect(repository.sweepOrphanedFiles, isFalse);
      expect(file.existsSync(), isFalse);
      expect(
        (await repository.getAllObjects()).map((r) => r.key),
        unorderedEquals([osm, stadia]),
      );
    }, skip: skip);

    test('without an index the sweep stays on and no notice is shown',
        () async {
      var noticed = 0;
      final repository = await MapTileCacheRepository.openForThisPlatform(
        useDatabase: true,
        databaseFactory: _memoryDatabase,
        supportDirectory: () async => tempDir,
        onImportStarted: () async => noticed++,
      );

      expect(repository, isNotNull);
      addTearDown(repository!.database.close);
      expect(noticed, 0);
      expect(repository.sweepOrphanedFiles, isTrue);
      expect(await repository.getAllObjects(), isEmpty);
    }, skip: skip);

    test('a database that cannot open leaves the index in place and answers '
        'null', () async {
      final file = await writeIndex([_record(osm)]);
      final content = file.readAsStringSync();

      final repository = await MapTileCacheRepository.openForThisPlatform(
        useDatabase: true,
        databaseFactory: () =>
            MapTileCacheDatabase.withExecutor(_UnopenableExecutor()),
        supportDirectory: () async => tempDir,
      );

      expect(repository, isNull);
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), content);
    }, skip: skip);

    test('closing the repository counts connections and leaves the database '
        'open', () async {
      final database = await openDatabase();
      final repository = MapTileCacheRepository(database);
      await repository.open();
      await repository.open();
      expect(await repository.close(), isFalse);
      expect(await repository.close(), isTrue);
      expect(await repository.close(), isTrue);
      expect(await database.countRecords(), 0);
    }, skip: skip);
  });

  group('the cache screen after the move', () {
    test('reads the same inventory from the database as from the index',
        () async {
      final records = [
        _record(osm, length: 5000),
        _record(stadia, length: 7000),
        _record(yandex, length: 25160),
        _record('https://example.test/favicon.ico', length: 300),
      ];
      final settings = AppSettingsService();

      Future<CachedTileInventory> inventoryOver(
        String cacheKey,
        CacheInfoRepository repo,
      ) async {
        final manager = CacheManager(
          Config(cacheKey, repo: repo, fileSystem: IOFileSystem(cacheKey)),
        );
        final service = MapTileCacheService(
          appSettingsService: settings,
          cacheManager: manager,
          sweepOrphanedFiles: false,
        );
        addTearDown(service.dispose);
        return service.getCachedTileInventory();
      }

      final file = await writeIndex(records);
      final jsonRepo = JsonCacheInfoRepository.withFile(file);
      final before = await inventoryOver('map_tile_cache_json', jsonRepo);
      await jsonRepo.close();

      final database = await openDatabase();
      await database.importLegacyIndex(file);
      final after = await inventoryOver(
        'map_tile_cache_db',
        MapTileCacheRepository(database),
      );

      String describe(CachedTileInfo tile) =>
          '${tile.key} ${tile.host} ${tile.sourceId} '
          '${tile.zoom}/${tile.x}/${tile.y} ${tile.length}';
      expect(before.tiles, hasLength(3));
      expect(
        after.tiles.map(describe),
        unorderedEquals(before.tiles.map(describe)),
      );
      expect(after.totalBytes, before.totalBytes);
      expect(after.totalBytes, 5000 + 7000 + 25160 + 300);
    }, skip: skip);
  });
}
