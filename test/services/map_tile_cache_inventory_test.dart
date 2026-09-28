import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/map_tile_cache_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What the map cache screen and the bulk downloader read out of the record
// repository: one CachedTileInfo per tile record, attributed to its source by
// host, path and query, plus the byte total. Pinned on the JSON repository
// the desktop uses today, since a repository of our own has to give the
// screen the same numbers for the same records.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;
  var cacheIndex = 0;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mco_tile_inventory_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    PrefsManager.reset();
    // Reading the inventory starts the orphan sweep in the background; give
    // it the moment it needs to list the directory before the directory goes.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    tempDir.deleteSync(recursive: true);
  });

  const osm = 'https://tile.openstreetmap.org/12/2345/1234.png';
  const stadia = 'https://tiles.stadiamaps.com/tiles/outdoors/10/1/2@2x.png';
  const stadiaEu = 'https://tiles-eu.stadiamaps.com/tiles/osm_bright/12/3/4.png';
  const yandex =
      'https://tiles.api-maps.yandex.ru/v1/tiles/?lang=ru_RU&l=map'
      '&projection=web_mercator&maptype=map&x=9962&y=5889&z=14&scale=2.0';
  const yandexDark =
      'https://tiles.api-maps.yandex.ru/v1/tiles/?lang=en_US&l=map'
      '&projection=web_mercator&maptype=map&x=1&y=2&z=3&scale=1&theme=dark';
  const noTile = 'https://example.test/favicon.ico';
  const noNumbers = 'https://example.test/a/b/c.png';

  CacheObject record(String key, {int? length}) => CacheObject(
    key,
    key: key,
    relativePath: '${key.hashCode.toRadixString(16)}.png',
    validTill: DateTime(2027, 1, 1),
    length: length,
  );

  /// A service over a cache manager whose repository holds [records]. Each
  /// call takes a cache key of its own, since the orphan sweep runs once per
  /// key and process.
  Future<({MapTileCacheService service, AppSettingsService settings})> build(
    List<CacheObject> records,
  ) async {
    final cacheKey = 'map_tile_cache_inventory_${cacheIndex++}';
    final repo = JsonCacheInfoRepository.withFile(
      File('${tempDir.path}${Platform.pathSeparator}$cacheKey.json'),
    );
    final manager = CacheManager(
      Config(
        cacheKey,
        repo: repo,
        fileSystem: IOFileSystem(cacheKey),
        stalePeriod: MapTileCacheService.cacheLifetime,
        maxNrOfCacheObjects: 200000,
      ),
    );
    await repo.open();
    for (final record in records) {
      await repo.insert(record);
    }
    final settings = AppSettingsService();
    final service = MapTileCacheService(
      appSettingsService: settings,
      cacheManager: manager,
    );
    addTearDown(service.dispose);
    return (service: service, settings: settings);
  }

  test('every tile record is listed under its source with its coordinates, '
      'and the byte total counts every record', () async {
    final built = await build([
      record(osm, length: 5000),
      record(stadia, length: 7000),
      record(stadiaEu, length: 6000),
      record(yandex, length: 25160),
      record(yandexDark, length: 8000),
      record(noTile, length: 300),
      record(noNumbers, length: null),
    ]);

    final inventory = await built.service.getCachedTileInventory();

    expect(inventory.totalBytes, 5000 + 7000 + 6000 + 25160 + 8000 + 300);
    final byKey = {for (final tile in inventory.tiles) tile.key: tile};
    expect(
      byKey.keys,
      unorderedEquals([osm, stadia, stadiaEu, yandex, yandexDark]),
    );

    void check(
      String key, {
      required String host,
      required String sourceId,
      required int zoom,
      required int x,
      required int y,
      required int length,
    }) {
      final tile = byKey[key]!;
      expect(tile.host, host, reason: key);
      expect(tile.sourceId, sourceId, reason: key);
      expect(tile.zoom, zoom, reason: key);
      expect(tile.x, x, reason: key);
      expect(tile.y, y, reason: key);
      expect(tile.length, length, reason: key);
    }

    check(
      osm,
      host: 'tile.openstreetmap.org',
      sourceId: 'osm_standard',
      zoom: 12,
      x: 2345,
      y: 1234,
      length: 5000,
    );
    check(
      stadia,
      host: 'tiles.stadiamaps.com',
      sourceId: 'outdoors',
      zoom: 10,
      x: 1,
      y: 2,
      length: 7000,
    );
    check(
      stadiaEu,
      host: 'tiles-eu.stadiamaps.com',
      sourceId: 'osm_bright',
      zoom: 12,
      x: 3,
      y: 4,
      length: 6000,
    );
    check(
      yandex,
      host: MapTileCacheService.yandexTileHost,
      sourceId: 'yandex',
      zoom: 14,
      x: 9962,
      y: 5889,
      length: 25160,
    );
    check(
      yandexDark,
      host: MapTileCacheService.yandexTileHost,
      sourceId: 'yandex_dark',
      zoom: 3,
      x: 1,
      y: 2,
      length: 8000,
    );
  });

  test('an empty repository gives an empty inventory', () async {
    final built = await build(const []);
    final inventory = await built.service.getCachedTileInventory();
    expect(inventory.tiles, isEmpty);
    expect(inventory.totalBytes, 0);
  });

  test('the active source filter follows the settings', () async {
    final built = await build([
      record(osm, length: 1),
      record(stadia, length: 1),
      record(stadiaEu, length: 1),
      record(yandex, length: 1),
      record(yandexDark, length: 1),
    ]);
    final service = built.service;
    final settings = built.settings;
    final tiles = (await service.getCachedTileInventory()).tiles;
    Iterable<String> active() =>
        service.filterTilesForActiveSource(tiles).map((tile) => tile.key);

    // OpenStreetMap Auto, the default.
    expect(active(), [osm]);

    // Stadia on the demo key still names its own tiles, on the endpoint the
    // settings pick: the default is the standard @2x endpoint.
    await settings.setMapRasterSourceId('outdoors');
    expect(active(), [stadia]);
    await settings.setMapTileEndpointId('eu');
    expect(active(), isEmpty);
    await settings.setMapRasterSourceId('osm_bright');
    expect(active(), [stadiaEu]);

    // Yandex without a key is OpenStreetMap; with one, its own theme only.
    await settings.setMapRasterSourceId('yandex');
    expect(active(), [osm]);
    await settings.setMapYandexApiKey('a-key');
    expect(active(), [yandex]);
    await settings.setMapRasterSourceId('yandex_dark');
    expect(active(), [yandexDark]);
  });
}
