import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/map_tile_cache_service.dart';

// Two things the service promises around its cache manager: the record
// repository is not touched until a map needs it, and the inventory sweeps
// orphaned files only when it is allowed to.

/// A repository that counts how often it is opened, delegating everything
/// else to the package's JSON repository.
class _CountingRepository implements CacheInfoRepository {
  _CountingRepository(this._inner);

  final JsonCacheInfoRepository _inner;
  int opens = 0;

  @override
  Future<bool> open() {
    opens++;
    return _inner.open();
  }

  @override
  Future<bool> close() => _inner.close();

  @override
  Future<bool> exists() => _inner.exists();

  @override
  Future<void> deleteDataFile() => _inner.deleteDataFile();

  @override
  Future<CacheObject?> get(String key) => _inner.get(key);

  @override
  Future<List<CacheObject>> getAllObjects() => _inner.getAllObjects();

  @override
  Future<CacheObject> insert(
    CacheObject cacheObject, {
    bool setTouchedToNow = true,
  }) => _inner.insert(cacheObject, setTouchedToNow: setTouchedToNow);

  @override
  Future<int> update(CacheObject cacheObject, {bool setTouchedToNow = true}) =>
      _inner.update(cacheObject, setTouchedToNow: setTouchedToNow);

  @override
  Future<dynamic> updateOrInsert(CacheObject cacheObject) =>
      _inner.updateOrInsert(cacheObject);

  @override
  Future<int> delete(int id) => _inner.delete(id);

  @override
  Future<int> deleteAll(Iterable<int> ids) => _inner.deleteAll(ids);

  @override
  Future<List<CacheObject>> getObjectsOverCapacity(int capacity) =>
      _inner.getObjectsOverCapacity(capacity);

  @override
  Future<List<CacheObject>> getOldObjects(Duration maxAge) =>
      _inner.getOldObjects(maxAge);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;
  var cacheIndex = 0;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mco_tile_service_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    // A sweep started by a test lists the directory in the background.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    tempDir.deleteSync(recursive: true);
  });

  String nextCacheKey() => 'map_tile_cache_service_${cacheIndex++}';

  JsonCacheInfoRepository jsonRepository(String cacheKey) =>
      JsonCacheInfoRepository.withFile(
        File('${tempDir.path}${Platform.pathSeparator}$cacheKey.json'),
      );

  test('the record repository is opened at the first use of the tile '
      'provider, not when the service is built', () async {
    final repository = _CountingRepository(jsonRepository(nextCacheKey()));
    final service = MapTileCacheService(
      appSettingsService: AppSettingsService(),
      recordRepository: repository,
    );
    addTearDown(service.dispose);

    expect(repository.opens, 0);

    final provider = service.tileProvider;
    expect(repository.opens, 1);
    expect(identical(service.tileProvider, provider), isTrue);
    expect(identical(service.cacheManager, service.cacheManager), isTrue);
    expect(repository.opens, 1);
  });

  group('orphan sweep', () {
    Future<({MapTileCacheService service, File orphan})> build({
      required bool sweepOrphanedFiles,
    }) async {
      final cacheKey = nextCacheKey();
      final directory = Directory(
        '${tempDir.path}${Platform.pathSeparator}$cacheKey',
      )..createSync(recursive: true);
      final orphan = File('${directory.path}${Platform.pathSeparator}old.png')
        ..writeAsBytesSync(const [1])
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 3)),
        );
      final manager = CacheManager(
        Config(
          cacheKey,
          repo: jsonRepository(cacheKey),
          fileSystem: IOFileSystem(cacheKey),
        ),
      );
      final service = MapTileCacheService(
        appSettingsService: AppSettingsService(),
        cacheManager: manager,
        sweepOrphanedFiles: sweepOrphanedFiles,
      );
      addTearDown(service.dispose);
      return (service: service, orphan: orphan);
    }

    test('an inventory read with the sweep off leaves an old orphan alone',
        () async {
      final built = await build(sweepOrphanedFiles: false);
      await built.service.getCachedTileInventory();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(built.orphan.existsSync(), isTrue);
    });

    test('an inventory read with the sweep on deletes it', () async {
      final built = await build(sweepOrphanedFiles: true);
      await built.service.getCachedTileInventory();
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (built.orphan.existsSync() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(built.orphan.existsSync(), isFalse);
    });
  });
}
