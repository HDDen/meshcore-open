import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/map_tile_cache_database.dart';

// What the map tile cache asks of its record repository, pinned on the JSON
// repository flutter_cache_manager used on Windows and Linux, and held
// against the database repository that replaced it there: what a record
// keeps, how it is found, what the cleanup queries answer, how the cache
// manager drives it, and how the JSON index lies on disk, which is what the
// move out of that index reads.

typedef OpenRepository = Future<CacheInfoRepository> Function();

Future<String?> _sqliteProblem() async {
  try {
    final database = MapTileCacheDatabase.withExecutor(
      NativeDatabase.memory(),
    );
    await database.countRecords();
    await database.close();
    return null;
  } catch (error) {
    return 'sqlite3 is not available to this test host: $error';
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = await _sqliteProblem();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mco_tile_repo_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    tempDir.deleteSync(recursive: true);
  });

  File indexFile() => File(
    '${tempDir.path}${Platform.pathSeparator}map_tile_cache_test.json',
  );

  group('JSON repository', () {
    repositoryContract(() async {
      final repo = JsonCacheInfoRepository.withFile(indexFile());
      await repo.open();
      return repo;
    });

    test('the index file holds one map per record with these keys', () async {
      final repo = JsonCacheInfoRepository.withFile(indexFile());
      await repo.open();
      final touched = DateTime.fromMillisecondsSinceEpoch(1787528910467);
      final stored = await repo.insert(
        CacheObject(
          'https://tiles.stadiamaps.com/tiles/outdoors/10/1/2.png?api_key=k',
          key: 'https://tiles.stadiamaps.com/tiles/outdoors/10/1/2.png',
          relativePath: 'ee657320-9be8-11f1-a100-1338ffcad740.png',
          validTill: DateTime.fromMillisecondsSinceEpoch(1818692015954),
          eTag: '"bb9bc9d216f8f6b794350cee410a12a6"',
          length: 25160,
          touched: touched,
        ),
        setTouchedToNow: false,
      );
      final bare = await repo.insert(
        CacheObject(
          'https://tile.openstreetmap.org/1/2/3.png',
          relativePath: 'bare.file',
          validTill: DateTime.fromMillisecondsSinceEpoch(1818692015954),
        ),
      );
      await repo.close();

      final decoded = jsonDecode(indexFile().readAsStringSync());
      expect(decoded, isA<List<dynamic>>());
      final maps = (decoded as List<dynamic>).cast<Map<String, dynamic>>();
      expect(maps, hasLength(2));

      final full = maps.singleWhere((map) => map['_id'] == stored.id);
      expect(full.keys.toSet(), {
        'url',
        'key',
        'relativePath',
        'eTag',
        'validTill',
        'touched',
        'length',
        '_id',
      });
      expect(
        full['url'],
        'https://tiles.stadiamaps.com/tiles/outdoors/10/1/2.png?api_key=k',
      );
      expect(full['key'], 'https://tiles.stadiamaps.com/tiles/outdoors/10/1/2.png');
      expect(full['relativePath'], 'ee657320-9be8-11f1-a100-1338ffcad740.png');
      expect(full['eTag'], '"bb9bc9d216f8f6b794350cee410a12a6"');
      expect(full['validTill'], 1818692015954);
      expect(full['touched'], 1787528910467);
      expect(full['length'], 25160);
      expect(full['_id'], isA<int>());

      // A record without a tag or a length, as a server that sends neither
      // leaves it, and the key defaulting to the url.
      final plain = maps.singleWhere((map) => map['_id'] == bare.id);
      expect(plain['key'], 'https://tile.openstreetmap.org/1/2/3.png');
      expect(plain['eTag'], isNull);
      expect(plain['length'], isNull);
      expect(plain['touched'], isA<int>());

      // What the file holds is what CacheObject reads back.
      final read = CacheObject.fromMap(full);
      expect(read.id, stored.id);
      expect(read.key, stored.key);
      expect(read.url, stored.url);
      expect(read.relativePath, stored.relativePath);
      expect(read.validTill, stored.validTill);
      expect(read.touched, touched);
      expect(read.eTag, stored.eTag);
      expect(read.length, stored.length);
    });
  });

  group('database repository', () {
    // One database per test, shared by every repository the test opens, so
    // that records written through one instance are read through the next.
    MapTileCacheDatabase? database;

    setUp(() => database = null);

    tearDown(() async {
      await database?.close();
      database = null;
    });

    repositoryContract(() async {
      database ??= MapTileCacheDatabase.withExecutor(NativeDatabase.memory());
      final repo = MapTileCacheRepository(database!);
      await repo.open();
      return repo;
    });
  }, skip: skip);
}

CacheObject record(
  String key, {
  String? url,
  String? relativePath,
  DateTime? validTill,
  DateTime? touched,
  String? eTag,
  int? length = 100,
}) => CacheObject(
  url ?? key,
  key: key,
  relativePath: relativePath ?? '${key.hashCode.toRadixString(16)}.png',
  validTill: validTill ?? DateTime(2027, 1, 1),
  touched: touched,
  eTag: eTag,
  length: length,
);

const keyA = 'https://tile.openstreetmap.org/12/2345/1234.png';
const keyB = 'https://tiles.stadiamaps.com/tiles/outdoors/10/1/2@2x.png';
const keyC =
    'https://tiles.api-maps.yandex.ru/v1/tiles/?lang=ru_RU&l=map'
    '&projection=web_mercator&maptype=map&x=9962&y=5889&z=14&scale=2.0';

/// The contract itself. [open] returns an open repository over the same
/// store every time it is called within one test, so a record written
/// through one instance is read through the next.
void repositoryContract(OpenRepository open) {
  test('insert gives the record an id and get finds it by key', () async {
    final repo = await open();
    addTearDown(repo.close);
    final before = DateTime.now();
    final stored = await repo.insert(
      record(
        keyB,
        url: '$keyB?api_key=k1',
        relativePath: 'b.png',
        validTill: DateTime(2027, 3, 4),
        eTag: '"e"',
        length: 123,
      ),
    );
    expect(stored.id, isNotNull);
    expect(stored.key, keyB);

    final found = await repo.get(keyB);
    expect(found, isNotNull);
    expect(found!.id, stored.id);
    expect(found.key, keyB);
    expect(found.url, '$keyB?api_key=k1');
    expect(found.relativePath, 'b.png');
    expect(found.validTill, DateTime(2027, 3, 4));
    expect(found.eTag, '"e"');
    expect(found.length, 123);
    // Touched at insertion, since nothing said otherwise.
    expect(found.touched, isNotNull);
    expect(found.touched!.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse);

    expect(await repo.get('https://tile.openstreetmap.org/9/9/9.png'), isNull);
    expect(await repo.get(''), isNull);
  });

  test('a touch time handed in is kept when asked to', () async {
    final repo = await open();
    addTearDown(repo.close);
    final touched = DateTime(2026, 1, 2, 3, 4, 5);
    await repo.insert(record(keyA, touched: touched), setTouchedToNow: false);
    expect((await repo.get(keyA))!.touched, touched);
  });

  test('update changes the fields under the same id', () async {
    final repo = await open();
    addTearDown(repo.close);
    final stored = await repo.insert(record(keyA, length: 1));
    final changed = stored.copyWith(
      length: 2,
      eTag: 'x',
      validTill: DateTime(2028, 5, 6),
      relativePath: 'moved.png',
    );

    expect(await repo.update(changed), 1);

    final found = (await repo.get(keyA))!;
    expect(found.id, stored.id);
    expect(found.length, 2);
    expect(found.eTag, 'x');
    expect(found.validTill, DateTime(2028, 5, 6));
    expect(found.relativePath, 'moved.png');
    expect(await repo.getAllObjects(), hasLength(1));
  });

  test('updateOrInsert inserts without an id and updates with one', () async {
    final repo = await open();
    addTearDown(repo.close);
    await repo.updateOrInsert(record(keyA, length: 1));
    final stored = (await repo.get(keyA))!;
    expect(stored.id, isNotNull);

    await repo.updateOrInsert(stored.copyWith(length: 3));
    await repo.updateOrInsert(record(keyB));

    expect((await repo.get(keyA))!.length, 3);
    expect((await repo.get(keyA))!.id, stored.id);
    expect(
      (await repo.getAllObjects()).map((o) => o.key),
      unorderedEquals([keyA, keyB]),
    );
  });

  test('delete and deleteAll remove by id and say how many went', () async {
    final repo = await open();
    addTearDown(repo.close);
    final a = await repo.insert(record(keyA));
    final b = await repo.insert(record(keyB));
    final c = await repo.insert(record(keyC));

    expect(await repo.delete(a.id!), 1);
    expect(await repo.delete(a.id!), 0);
    expect(await repo.get(keyA), isNull);
    // The cleanup hands over an empty list whenever nothing is due.
    expect(await repo.deleteAll(const <int>[]), 0);
    expect(await repo.deleteAll([b.id!, c.id!, 999999]), 2);
    expect(await repo.getAllObjects(), isEmpty);
  });

  test('getAllObjects lists every record with its fields', () async {
    final repo = await open();
    addTearDown(repo.close);
    await repo.insert(record(keyA, length: 1));
    await repo.insert(record(keyB, length: 2));
    await repo.insert(record(keyC, length: null));

    final all = await repo.getAllObjects();
    expect(all.map((o) => o.key), unorderedEquals([keyA, keyB, keyC]));
    expect(all.map((o) => o.length), unorderedEquals([1, 2, null]));
    expect(all.map((o) => o.id).toSet(), hasLength(3));
  });

  test('getOldObjects answers the records touched before maxAge', () async {
    final repo = await open();
    addTearDown(repo.close);
    final now = DateTime.now();
    await repo.insert(
      record(keyA, touched: now.subtract(const Duration(days: 400))),
      setTouchedToNow: false,
    );
    await repo.insert(
      record(keyB, touched: now.subtract(const Duration(days: 10))),
      setTouchedToNow: false,
    );
    await repo.insert(record(keyC));

    expect(
      (await repo.getOldObjects(const Duration(days: 365))).map((o) => o.key),
      [keyA],
    );
    expect(
      (await repo.getOldObjects(const Duration(days: 5))).map((o) => o.key),
      unorderedEquals([keyA, keyB]),
    );
    expect(await repo.getOldObjects(const Duration(days: 500)), isEmpty);
  });

  test('getObjectsOverCapacity answers the least recently touched beyond '
      'the capacity and nothing under it', () async {
    final repo = await open();
    addTearDown(repo.close);
    final now = DateTime.now();
    final keys = <int, String>{};
    for (var daysAgo = 1; daysAgo <= 5; daysAgo++) {
      final key = 'https://tile.openstreetmap.org/10/$daysAgo/0.png';
      keys[daysAgo] = key;
      await repo.insert(
        record(key, touched: now.subtract(Duration(days: daysAgo))),
        setTouchedToNow: false,
      );
    }

    expect(await repo.getObjectsOverCapacity(5), isEmpty);
    expect(await repo.getObjectsOverCapacity(10), isEmpty);
    expect(
      (await repo.getObjectsOverCapacity(3)).map((o) => o.key),
      unorderedEquals([keys[5], keys[4]]),
    );
  });

  test('records outlive the repository instance', () async {
    final first = await open();
    final a = await first.insert(
      record(keyA, relativePath: 'a.png', eTag: '"a"', length: 11),
    );
    await first.insert(record(keyB));
    expect(await first.close(), isTrue);

    final second = await open();
    addTearDown(second.close);
    expect(
      (await second.getAllObjects()).map((o) => o.key),
      unorderedEquals([keyA, keyB]),
    );
    final found = (await second.get(keyA))!;
    expect(found.id, a.id);
    expect(found.relativePath, 'a.png');
    expect(found.eTag, '"a"');
    expect(found.length, 11);
    expect(found.validTill, DateTime(2027, 1, 1));
  });

  test('the cache manager over the repository stores, serves and removes '
      'a tile by key', () async {
    final repo = await open();
    addTearDown(repo.close);
    const cacheKey = 'map_tile_cache_contract';
    final manager = CacheManager(
      Config(cacheKey, repo: repo, fileSystem: IOFileSystem(cacheKey)),
    );
    // The store schedules its cleanup after the first read; running it at
    // once keeps it inside the test instead of ten seconds after it.
    manager.store.cleanupRunMinInterval = Duration.zero;
    final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));

    final file = await manager.putFile(
      '$keyB?api_key=k1',
      bytes,
      key: keyB,
      fileExtension: 'png',
    );
    expect(file.existsSync(), isTrue);
    final stored = (await repo.get(keyB))!;
    expect(stored.url, '$keyB?api_key=k1');
    expect(stored.relativePath, file.uri.pathSegments.last);

    final cached = await manager.getFileFromCache(keyB);
    expect(cached, isNotNull);
    expect(cached!.file.readAsBytesSync(), bytes);
    expect(await manager.getFileFromCache('$keyB?api_key=k1'), isNull);

    await manager.removeFile(keyB);
    expect(await repo.get(keyB), isNull);
    expect(file.existsSync(), isFalse);
    // Let the immediate cleanup finish before the repository closes.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
}
