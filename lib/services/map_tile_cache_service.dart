import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/app_settings.dart';
import 'app_settings_service.dart';

enum MapRasterSourcePreset {
  osmAuto('osm_auto'),
  osmStandard('osm_standard'),
  osmDark('osm_dark'),
  osmDarkHC('osm_darkHC'),
  stamenTerrain('stamen_terrain'),
  alidadeSmoothDark('alidade_smooth_dark'),
  outdoors('outdoors'),
  osmBright('osm_bright'),
  outdoorsDark('outdoors_dark'),
  outdoorsDarkHC('outdoors_darkHC'),
  osmBrightDark('osm_bright_dark'),
  osmBrightDarkHC('osm_bright_darkHC'),
  yandex('yandex'),
  yandexDark('yandex_dark');

  const MapRasterSourcePreset(this.id);

  final String id;

  static MapRasterSourcePreset fromId(String id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return MapRasterSourcePreset.osmAuto;
  }
}

enum MapRasterEndpointPreset {
  standard('standard'),
  standard2x('standard_2x'),
  eu('eu'),
  eu2x('eu_2x');

  const MapRasterEndpointPreset(this.id);

  final String id;

  static MapRasterEndpointPreset fromId(String id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return MapRasterEndpointPreset.standard;
  }
}

@immutable
class MapRasterSourceDefinition {
  const MapRasterSourceDefinition({
    required this.id,
    required this.label,
    required this.description,
    this.isStadia = false,
    this.isYandex = false,
    this.allowsBulkDownload = false,
    this.maxRequestsPerSecond,
    this.consoleUrl,
  });

  final String id;
  final String label;
  final String description;
  final bool isStadia;
  final bool isYandex;
  final bool allowsBulkDownload;

  /// Ceiling the bulk downloader keeps to, where the provider states one.
  final int? maxRequestsPerSecond;

  /// Where the user issues their own key. Shown as a link when picking the
  /// source, so it stays out of the one-line summary in settings.
  final String? consoleUrl;
}

@immutable
class MapRasterEndpointDefinition {
  const MapRasterEndpointDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.host,
    this.scaleSuffix = '',
  });

  final String id;
  final String label;
  final String description;
  final String host;
  final String scaleSuffix;
}

class MapRasterSourceCatalog {
  static const MapRasterSourceDefinition osmAuto = MapRasterSourceDefinition(
    id: 'osm_auto',
    label: 'OpenStreetMap Auto',
    description:
        'Automatically uses OpenStreetMap Standard or Dark from the app theme',
  );
  static const MapRasterSourceDefinition osmStandard =
      MapRasterSourceDefinition(
        id: 'osm_standard',
        label: 'OpenStreetMap Standard',
        description: 'Direct tiles from tile.openstreetmap.org',
      );
  static const MapRasterSourceDefinition osmDark = MapRasterSourceDefinition(
    id: 'osm_dark',
    label: 'OpenStreetMap Dark',
    description: 'Standard OpenStreetMap tiles with an inverted dark filter',
  );
  static const MapRasterSourceDefinition osmDarkHC = MapRasterSourceDefinition(
    id: 'osm_darkHC',
    label: 'OpenStreetMap Dark High Contrast',
    description:
        'Standard OpenStreetMap tiles with an inverted high contrast dark filter',
  );

  /// Yandex Tiles API. The `projection=web_mercator` parameter is what makes
  /// this usable at all: Yandex draws in elliptical Mercator by default, which
  /// would put every tile kilometres off the EPSG:3857 grid flutter_map uses.
  static const MapRasterSourceDefinition yandex = MapRasterSourceDefinition(
    id: 'yandex',
    label: 'Yandex Maps',
    description: '© Яндекс. Needs your own Tiles API key',
    isYandex: true,
    allowsBulkDownload: true,
    maxRequestsPerSecond: MapTileCacheService.yandexMaxRequestsPerSecond,
    consoleUrl: 'https://yandex.ru/maps-api/console',
  );
  /// The same tiles with `theme=dark`. A separate source rather than a flag on
  /// the one above, because the theme rides in the request and therefore in
  /// the cache key: the two are different tiles on disk and have to be counted
  /// and downloaded as different sources.
  static const MapRasterSourceDefinition yandexDark =
      MapRasterSourceDefinition(
        id: 'yandex_dark',
        label: 'Yandex Maps Dark',
        description: '© Яндекс. Needs your own Tiles API key',
        isYandex: true,
        allowsBulkDownload: true,
        maxRequestsPerSecond: MapTileCacheService.yandexMaxRequestsPerSecond,
        consoleUrl: 'https://yandex.ru/maps-api/console',
      );
  static const MapRasterSourceDefinition stamenTerrain =
      MapRasterSourceDefinition(
        id: 'stamen_terrain',
        label: 'Stamen Terrain',
        description: 'Terrain-focused style with hill shading',
        isStadia: true,
        allowsBulkDownload: true,
      );
  static const MapRasterSourceDefinition alidadeSmoothDark =
      MapRasterSourceDefinition(
        id: 'alidade_smooth_dark',
        label: 'Alidade Smooth Dark',
        description: 'Dark basemap with smooth contrast',
        isStadia: true,
        allowsBulkDownload: true,
      );
  static const MapRasterSourceDefinition outdoors = MapRasterSourceDefinition(
    id: 'outdoors',
    label: 'Outdoors',
    description: 'Outdoor-focused map with trails and terrain context',
    isStadia: true,
    allowsBulkDownload: true,
  );
  static const MapRasterSourceDefinition osmBright = MapRasterSourceDefinition(
    id: 'osm_bright',
    label: 'OSM Bright',
    description: 'Bright general-purpose OpenStreetMap style',
    isStadia: true,
    allowsBulkDownload: true,
  );
  static const MapRasterSourceDefinition outdoorsDark =
      MapRasterSourceDefinition(
        id: 'outdoors',
        label: 'Outdoors Dark',
        description: 'Dark version of the Outdoors map style',
        isStadia: true,
        allowsBulkDownload: true,
      );
  static const MapRasterSourceDefinition outdoorsDarkHC =
      MapRasterSourceDefinition(
        id: 'outdoors',
        label: 'Outdoors Dark High Contrast',
        description: 'High contrast dark version of the Outdoors map style',
        isStadia: true,
        allowsBulkDownload: true,
      );
  static const MapRasterSourceDefinition osmBrightDark =
      MapRasterSourceDefinition(
        id: 'osm_bright',
        label: 'OSM Bright Dark',
        description: 'Dark version of the OSM Bright map style',
        isStadia: true,
        allowsBulkDownload: true,
      );
  static const MapRasterSourceDefinition osmBrightDarkHC =
      MapRasterSourceDefinition(
        id: 'osm_bright',
        label: 'OSM Bright Dark High Contrast',
        description: 'High contrast dark version of the OSM Bright map style',
        isStadia: true,
        allowsBulkDownload: true,
      );

  static MapRasterSourceDefinition fromPreset(MapRasterSourcePreset preset) {
    switch (preset) {
      case MapRasterSourcePreset.osmAuto:
        return osmAuto;
      case MapRasterSourcePreset.osmStandard:
        return osmStandard;
      case MapRasterSourcePreset.osmDark:
        return osmDark;
      case MapRasterSourcePreset.osmDarkHC:
        return osmDarkHC;
      case MapRasterSourcePreset.alidadeSmoothDark:
        return alidadeSmoothDark;
      case MapRasterSourcePreset.outdoors:
        return outdoors;
      case MapRasterSourcePreset.outdoorsDark:
        return outdoorsDark;
      case MapRasterSourcePreset.outdoorsDarkHC:
        return outdoorsDarkHC;
      case MapRasterSourcePreset.osmBright:
        return osmBright;
      case MapRasterSourcePreset.osmBrightDark:
        return osmBrightDark;
      case MapRasterSourcePreset.osmBrightDarkHC:
        return osmBrightDarkHC;
      case MapRasterSourcePreset.stamenTerrain:
        return stamenTerrain;
      case MapRasterSourcePreset.yandex:
        return yandex;
      case MapRasterSourcePreset.yandexDark:
        return yandexDark;
    }
  }

  static MapRasterSourceDefinition fromSettings(AppSettings settings) {
    return fromPreset(MapRasterSourcePreset.fromId(settings.mapRasterSourceId));
  }
}

class MapRasterEndpointCatalog {
  static const MapRasterEndpointDefinition standard =
      MapRasterEndpointDefinition(
        id: 'standard',
        label: 'Standard Endpoint',
        description: 'Global CDN routing to the fastest Stadia server',
        host: 'tiles.stadiamaps.com',
      );
  static const MapRasterEndpointDefinition standard2x =
      MapRasterEndpointDefinition(
        id: 'standard_2x',
        label: 'Standard Endpoint (@2x)',
        description: 'Global Stadia endpoint with HiDPI raster tiles',
        host: 'tiles.stadiamaps.com',
        scaleSuffix: '@2x',
      );
  static const MapRasterEndpointDefinition eu = MapRasterEndpointDefinition(
    id: 'eu',
    label: 'EU Endpoint',
    description: 'Route tile requests to Stadia EU servers',
    host: 'tiles-eu.stadiamaps.com',
  );
  static const MapRasterEndpointDefinition eu2x = MapRasterEndpointDefinition(
    id: 'eu_2x',
    label: 'EU Endpoint (@2x)',
    description: 'EU Stadia endpoint with HiDPI raster tiles',
    host: 'tiles-eu.stadiamaps.com',
    scaleSuffix: '@2x',
  );

  static const List<MapRasterEndpointDefinition> presets = [
    standard,
    standard2x,
    eu,
    eu2x,
  ];

  static MapRasterEndpointDefinition fromSettings(AppSettings settings) {
    final preset = MapRasterEndpointPreset.fromId(settings.mapTileEndpointId);
    switch (preset) {
      case MapRasterEndpointPreset.standard2x:
        return standard2x;
      case MapRasterEndpointPreset.eu:
        return eu;
      case MapRasterEndpointPreset.eu2x:
        return eu2x;
      case MapRasterEndpointPreset.standard:
        return standard;
    }
  }
}

class MapTileCacheProgress {
  final int completed;
  final int total;
  final int failed;

  const MapTileCacheProgress({
    required this.completed,
    required this.total,
    required this.failed,
  });
}

class MapTileCacheResult {
  final int total;
  final int downloaded;
  final int failed;

  const MapTileCacheResult({
    required this.total,
    required this.downloaded,
    required this.failed,
  });
}

class CachedTileInfo {
  final String key;
  final String host;
  final String sourceId;
  final int zoom;
  final int x;
  final int y;
  final int length;

  const CachedTileInfo({
    required this.key,
    required this.host,
    required this.sourceId,
    required this.zoom,
    required this.x,
    required this.y,
    required this.length,
  });
}

class CachedTileInventory {
  final List<CachedTileInfo> tiles;
  final int totalBytes;

  const CachedTileInventory({required this.tiles, required this.totalBytes});
}

class MapTileCacheService extends ChangeNotifier {
  static const String cacheKey = 'map_tile_cache';
  static const String userAgentPackageName = 'com.meshcore.open';

  /// Names the app and links back to it, which is what the OpenStreetMap tile
  /// policy asks for — a library default like `flutter_map (...)` is on their
  /// list of agents to block.
  static const String userAgent =
      'MCO (+https://github.com/zjs81/meshcore-open)';

  /// Yandex is served a browser agent instead: their tile endpoint is built
  /// for web clients and answers them without argument.
  static const String yandexUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36';
  static const String yandexTileHost = 'tiles.api-maps.yandex.ru';

  /// Kept under the published 30 rps so a burst cannot trip the key.
  static const int yandexMaxRequestsPerSecond = 25;

  /// How long tiles are kept and treated as fresh. Deliberately long: the app
  /// is used where there may be no network for months.
  static const Duration cacheLifetime = Duration(days: 365);
  static const String _osmUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Yandex serves map captions in a handful of languages only; anything else
  /// falls back to English rather than failing the request.
  static const Map<String, String> _yandexLanguages = {
    'ru': 'ru_RU',
    'uk': 'uk_UA',
    'tr': 'tr_TR',
  };
  static const int defaultMinZoom = 10;
  static const int defaultMaxZoom = 15;

  final AppSettingsService appSettingsService;
  final BaseCacheManager cacheManager;
  late final TileProvider tileProvider;

  MapTileCacheService({
    required this.appSettingsService,
    BaseCacheManager? cacheManager,
  }) : cacheManager =
           cacheManager ??
           RateLimitedTileCacheManager(
             Config(
               cacheKey,
               stalePeriod: cacheLifetime,
               maxNrOfCacheObjects: 200000,
               fileService: PinnedFreshnessFileService(
                 pinnedHost: yandexTileHost,
                 lifetime: cacheLifetime,
               ),
             ),
             throttledHost: yandexTileHost,
             maxRequestsPerSecond: yandexMaxRequestsPerSecond,
           ) {
    tileProvider = CachedNetworkTileProvider(
      cacheManager: this.cacheManager,
      urlSigner: signTileUrl,
      headersFor: headersForUrl,
      // Seeded so TileLayer's putIfAbsent leaves the agent alone.
      headers: {'User-Agent': userAgent},
    );
    appSettingsService.addListener(_handleSettingsChanged);
  }

  MapRasterSourceDefinition get source {
    final selectedSource = MapRasterSourceCatalog.fromSettings(
      appSettingsService.settings,
    );
    if (selectedSource.isYandex &&
        appSettingsService.settings.effectiveMapYandexApiKey.isEmpty) {
      // Without a key the map really is OpenStreetMap, so the cache inventory
      // and the bulk downloader must treat it as such.
      return MapRasterSourceCatalog.osmStandard;
    }
    if (!selectedSource.isStadia ||
        !selectedSource.allowsBulkDownload ||
        !appSettingsService.settings.usesstadiaDemo) {
      return selectedSource;
    }
    return MapRasterSourceDefinition(
      id: selectedSource.id,
      label: selectedSource.label,
      description: selectedSource.description,
      isStadia: selectedSource.isStadia,
      allowsBulkDownload: false, // Explicitly disable bulk download for demo.
    );
  }

  MapRasterEndpointDefinition get endpoint =>
      MapRasterEndpointCatalog.fromSettings(appSettingsService.settings);

  /// Adds the Yandex request signature when a secret is configured. Other
  /// sources pass through untouched.
  String signTileUrl(String url) {
    if (!url.contains(yandexTileHost)) return url;
    final secret = appSettingsService.settings.effectiveMapYandexSigningSecret;
    if (secret.isEmpty) return url;
    return signYandexUrl(url, secret);
  }

  String get urlTemplate => _buildUrlTemplate(appSettingsService.settings);

  TileBuilder? get tileBuilder => null;

  static bool shouldApplyDarkFilterForSettings(
    AppSettings settings,
    Brightness brightness,
  ) {
    switch (MapRasterSourcePreset.fromId(settings.mapRasterSourceId)) {
      case MapRasterSourcePreset.osmDark:
      case MapRasterSourcePreset.osmDarkHC:
      case MapRasterSourcePreset.outdoorsDark:
      case MapRasterSourcePreset.outdoorsDarkHC:
      case MapRasterSourcePreset.osmBrightDark:
      case MapRasterSourcePreset.osmBrightDarkHC:
        return true;
      case MapRasterSourcePreset.osmAuto:
        return brightness == Brightness.dark;
      case MapRasterSourcePreset.osmStandard:
      case MapRasterSourcePreset.stamenTerrain:
      case MapRasterSourcePreset.alidadeSmoothDark:
      case MapRasterSourcePreset.outdoors:
      case MapRasterSourcePreset.osmBright:
      case MapRasterSourcePreset.yandex:
      // Dark from the provider, like alidadeSmoothDark above: inverting it
      // here would turn it back into a light map.
      case MapRasterSourcePreset.yandexDark:
        return false;
    }
  }

  static bool _isHighContrastDarkPreset(MapRasterSourcePreset preset) {
    switch (preset) {
      case MapRasterSourcePreset.osmDarkHC:
      case MapRasterSourcePreset.outdoorsDarkHC:
      case MapRasterSourcePreset.osmBrightDarkHC:
        return true;
      case MapRasterSourcePreset.osmAuto:
      case MapRasterSourcePreset.osmStandard:
      case MapRasterSourcePreset.osmDark:
      case MapRasterSourcePreset.stamenTerrain:
      case MapRasterSourcePreset.alidadeSmoothDark:
      case MapRasterSourcePreset.outdoors:
      case MapRasterSourcePreset.outdoorsDark:
      case MapRasterSourcePreset.osmBright:
      case MapRasterSourcePreset.osmBrightDark:
      case MapRasterSourcePreset.yandex:
      case MapRasterSourcePreset.yandexDark:
        return false;
    }
  }

  static const ColorFilter _darkMapFilter = ColorFilter.matrix([
    -0.0850,
    -0.2861,
    -0.0289,
    0,
    120,
    -0.0957,
    -0.3218,
    -0.0325,
    0,
    140,
    -0.1169,
    -0.3934,
    -0.0397,
    0,
    170,
    0,
    0,
    0,
    1,
    0,
  ]);
  static const ColorFilter _darkHCMapFilter = ColorFilter.matrix([
    0.7634200013,
    -1.9008999332,
    -0.1915199924,
    0,
    338.15,
    -0.5665799987,
    -0.5720999709,
    -0.1915199924,
    0,
    338.15,
    -0.5665799987,
    -1.9008999332,
    1.1384799335,
    0,
    338.15,
    0,
    0,
    0,
    1,
    0,
  ]);

  CacheManager get _concreteCacheManager => cacheManager as CacheManager;

  Map<String, String> headersForUrl(String url) => {
    'User-Agent': url.contains(yandexTileHost) ? yandexUserAgent : userAgent,
  };

  Widget buildTileLayer(BuildContext context, {double opacity = 1}) {
    Widget layer = TileLayer(
      urlTemplate: urlTemplate,
      tileProvider: tileProvider,
      tileBuilder: tileBuilder,
      userAgentPackageName: userAgentPackageName,
      maxZoom: 19,
      // Flutter caches failed image loads too, and the default strategy keeps
      // them forever: one tile lost to a rate limit or a dropped connection
      // stays a grey square for the rest of the session. Dropping error tiles
      // once they leave the viewport means coming back to the area retries
      // them through the normal request queue.
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
    );

    final shouldApplyDarkFilter = shouldApplyDarkFilterForSettings(
      appSettingsService.settings,
      Theme.of(context).brightness,
    );

    if (shouldApplyDarkFilter) {
      final activePreset = MapRasterSourcePreset.fromId(
        appSettingsService.settings.mapRasterSourceId,
      );
      final filter = _isHighContrastDarkPreset(activePreset)
          ? _darkHCMapFilter
          : _darkMapFilter;
      layer = ColorFiltered(colorFilter: filter, child: layer);
    }

    if (opacity < 1) {
      layer = Opacity(opacity: opacity, child: layer);
    }

    return layer;
  }

  Future<void> clearCache() async {
    await cacheManager.emptyCache();
  }

  Future<CachedTileInventory> getCachedTileInventory() async {
    final repo = _concreteCacheManager.config.repo;
    await repo.open();
    final objects = await repo.getAllObjects();
    final tiles = <CachedTileInfo>[];
    int totalBytes = 0;

    for (final object in objects) {
      totalBytes += object.length ?? 0;
      final tile = _parseCachedTile(object);
      if (tile != null) {
        tiles.add(tile);
      }
    }

    return CachedTileInventory(tiles: tiles, totalBytes: totalBytes);
  }

  List<CachedTileInfo> filterTilesForActiveSource(
    Iterable<CachedTileInfo> tiles,
  ) {
    final activeSource = source;
    if (activeSource.isYandex) {
      return tiles
          .where(
            (tile) =>
                tile.sourceId == activeSource.id &&
                tile.host == yandexTileHost,
          )
          .toList();
    }
    if (!activeSource.isStadia) {
      return tiles
          .where(
            (tile) =>
                tile.sourceId == MapRasterSourceCatalog.osmStandard.id &&
                tile.host == 'tile.openstreetmap.org',
          )
          .toList();
    }

    final activeEndpoint = endpoint;
    return tiles
        .where(
          (tile) =>
              tile.sourceId == activeSource.id &&
              tile.host == activeEndpoint.host,
        )
        .toList();
  }

  int countTilesForBounds(
    Iterable<CachedTileInfo> tiles, {
    LatLngBounds? bounds,
    required int minZoom,
    required int maxZoom,
  }) {
    if (bounds == null) return 0;
    final safeMin = math.min(minZoom, maxZoom);
    final safeMax = math.max(minZoom, maxZoom);
    return tiles.where((tile) {
      if (tile.zoom < safeMin || tile.zoom > safeMax) {
        return false;
      }
      final tileBounds = _tileBoundsForTile(tile.x, tile.y, tile.zoom);
      return _boundsIntersect(bounds, tileBounds);
    }).length;
  }

  List<Polygon> buildCachedTilePolygons(
    Iterable<CachedTileInfo> tiles, {
    required int zoom,
    LatLngBounds? visibleBounds,
    int limit = 250,
  }) {
    final polygons = <Polygon>[];
    for (final tile in tiles) {
      if (tile.zoom != zoom) continue;
      final tileBounds = _tileBoundsForTile(tile.x, tile.y, tile.zoom);
      if (visibleBounds != null &&
          !_boundsIntersect(visibleBounds, tileBounds)) {
        continue;
      }
      polygons.add(
        Polygon(
          points: [
            tileBounds.northWest,
            tileBounds.northEast,
            tileBounds.southEast,
            tileBounds.southWest,
          ],
          borderStrokeWidth: 0.6,
          color: const Color(0x5532A852),
          borderColor: const Color(0xCC2F8F46),
        ),
      );
      if (polygons.length >= limit) break;
    }
    return polygons;
  }

  int estimateTileCount(LatLngBounds bounds, int minZoom, int maxZoom) {
    final safeMin = math.min(minZoom, maxZoom);
    final safeMax = math.max(minZoom, maxZoom);
    int total = 0;

    for (int zoom = safeMin; zoom <= safeMax; zoom++) {
      final tileBounds = _tileBoundsForBounds(bounds, zoom);
      final xCount = tileBounds.maxX - tileBounds.minX + 1;
      final yCount = tileBounds.maxY - tileBounds.minY + 1;
      total += xCount * yCount;
    }
    return total;
  }

  Future<MapTileCacheResult> downloadRegion({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    int concurrentDownloads = 8,
    Map<String, String>? headers,
    void Function(MapTileCacheProgress progress)? onProgress,
  }) async {
    final safeMin = math.min(minZoom, maxZoom);
    final safeMax = math.max(minZoom, maxZoom);
    final total = estimateTileCount(bounds, safeMin, safeMax);
    final overrideHeaders = headers;
    final safeConcurrency = math.max(1, concurrentDownloads);
    final currentTemplate = urlTemplate;
    // Pacing lives in RateLimitedTileCacheManager so map rendering and this
    // downloader draw from one counter rather than two independent ones.
    int completed = 0;
    int failed = 0;

    final pending = <Future<void>>[];
    Future<void> queueDownload(String url) async {
      final future = cacheManager
          .downloadFile(
            url,
            key: tileCacheKey(url),
            authHeaders: overrideHeaders ?? headersForUrl(url),
          )
          .then((_) {
            completed += 1;
          })
          .catchError((_) {
            completed += 1;
            failed += 1;
          })
          .whenComplete(() {
            onProgress?.call(
              MapTileCacheProgress(
                completed: completed,
                total: total,
                failed: failed,
              ),
            );
          });

      pending.add(future);
      if (pending.length >= safeConcurrency) {
        await Future.wait(pending);
        pending.clear();
      }
    }

    for (int zoom = safeMin; zoom <= safeMax; zoom++) {
      final tileBounds = _tileBoundsForBounds(bounds, zoom);
      for (int x = tileBounds.minX; x <= tileBounds.maxX; x++) {
        for (int y = tileBounds.minY; y <= tileBounds.maxY; y++) {
          final url = signTileUrl(
            _buildTileUrl(x, y, zoom, urlTemplate: currentTemplate),
          );
          await queueDownload(url);
        }
      }
    }

    if (pending.isNotEmpty) {
      await Future.wait(pending);
    }

    return MapTileCacheResult(
      total: total,
      downloaded: completed - failed,
      failed: failed,
    );
  }

  static Map<String, double> boundsToJson(LatLngBounds bounds) {
    return {
      'north': bounds.north,
      'south': bounds.south,
      'east': bounds.east,
      'west': bounds.west,
    };
  }

  static LatLngBounds? boundsFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final north = (json['north'] as num?)?.toDouble();
    final south = (json['south'] as num?)?.toDouble();
    final east = (json['east'] as num?)?.toDouble();
    final west = (json['west'] as num?)?.toDouble();
    if (north == null || south == null || east == null || west == null) {
      return null;
    }
    return LatLngBounds.unsafe(
      north: north,
      south: south,
      east: east,
      west: west,
    );
  }

  void _handleSettingsChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    appSettingsService.removeListener(_handleSettingsChanged);
    super.dispose();
  }

  _TileBounds _tileBoundsForBounds(LatLngBounds bounds, int zoom) {
    final north = _clampLatitude(bounds.north);
    final south = _clampLatitude(bounds.south);
    final maxIndex = (1 << zoom) - 1;

    final minX = _lonToTileX(bounds.west, zoom, maxIndex);
    final maxX = _lonToTileX(bounds.east, zoom, maxIndex);
    final minY = _latToTileY(north, zoom, maxIndex);
    final maxY = _latToTileY(south, zoom, maxIndex);

    return _TileBounds(
      minX: math.min(minX, maxX),
      maxX: math.max(minX, maxX),
      minY: math.min(minY, maxY),
      maxY: math.max(minY, maxY),
    );
  }

  static String _yandexLang(AppSettings settings) {
    final code =
        settings.languageOverride ??
        ui.PlatformDispatcher.instance.locale.languageCode;
    return _yandexLanguages[code.toLowerCase()] ?? 'en_US';
  }

  String _buildUrlTemplate(AppSettings settings) {
    final source = MapRasterSourceCatalog.fromSettings(settings);
    if (source.isYandex) {
      final apiKey = settings.effectiveMapYandexApiKey;
      if (apiKey.isEmpty) return _osmUrlTemplate;
      final scale = AppSettings.formatMapYandexTileScale(
        settings.mapYandexTileScale,
      );
      final theme = source.id == MapRasterSourceCatalog.yandexDark.id
          ? '&theme=dark'
          : '';
      return 'https://$yandexTileHost/v1/tiles/'
          '?apikey=${Uri.encodeQueryComponent(apiKey)}'
          '&lang=${_yandexLang(settings)}'
          '&l=map'
          '&projection=web_mercator'
          '&maptype=map'
          '&x={x}&y={y}&z={z}'
          // The signature, added by signTileUrl(), must stay the last
          // parameter, so anything new goes above it.
          '&scale=$scale'
          '$theme';
    }
    if (!source.isStadia) {
      return _osmUrlTemplate;
    }
    final endpoint = MapRasterEndpointCatalog.fromSettings(settings);
    final apiKey = settings.effectiveMapTileApiKey;
    final base =
        'https://${endpoint.host}/tiles/${source.id}/{z}/{x}/{y}${endpoint.scaleSuffix}.png';
    final query = Uri(queryParameters: {'api_key': apiKey}).query;
    return '$base?$query';
  }

  CachedTileInfo? _parseCachedTile(CacheObject object) {
    final uri = Uri.tryParse(object.key);
    if (uri == null) return null;
    if (uri.host == yandexTileHost) {
      // Yandex passes the tile coordinates as query parameters rather than
      // path segments.
      final zoom = int.tryParse(uri.queryParameters['z'] ?? '');
      final x = int.tryParse(uri.queryParameters['x'] ?? '');
      final y = int.tryParse(uri.queryParameters['y'] ?? '');
      if (zoom == null || x == null || y == null) return null;
      // Both Yandex sources share a host, so the theme is what tells their
      // tiles apart. `tileCacheKey` drops only `apikey` and `signature`, so it
      // is still here to be read — and it has to be, or the dark source would
      // count and clear the light one's tiles as its own.
      final isDark = uri.queryParameters['theme'] == 'dark';
      return CachedTileInfo(
        key: object.key,
        host: uri.host,
        sourceId: isDark
            ? MapRasterSourceCatalog.yandexDark.id
            : MapRasterSourceCatalog.yandex.id,
        zoom: zoom,
        x: x,
        y: y,
        length: object.length ?? 0,
      );
    }
    final segments = uri.pathSegments;

    if (segments.length >= 3 &&
        segments[segments.length - 3].isNotEmpty &&
        segments[segments.length - 2].isNotEmpty) {
      final zoom = int.tryParse(segments[segments.length - 3]);
      final x = int.tryParse(segments[segments.length - 2]);
      final ySegment = segments.last;
      final yString = ySegment.split('.').first.replaceAll('@2x', '');
      final y = int.tryParse(yString);

      if (zoom == null || x == null || y == null) {
        return null;
      }

      var sourceId = MapRasterSourceCatalog.osmStandard.id;
      if (segments.length >= 5 && segments[0] == 'tiles') {
        sourceId = segments[1];
      }

      return CachedTileInfo(
        key: object.key,
        host: uri.host,
        sourceId: sourceId,
        zoom: zoom,
        x: x,
        y: y,
        length: object.length ?? 0,
      );
    }

    return null;
  }

  int _lonToTileX(double lon, int zoom, int maxIndex) {
    final n = 1 << zoom;
    final value = ((lon + 180.0) / 360.0 * n).floor();
    return value.clamp(0, maxIndex);
  }

  int _latToTileY(double lat, int zoom, int maxIndex) {
    final n = 1 << zoom;
    final rad = lat * math.pi / 180.0;
    final value =
        ((1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * n)
            .floor();
    return value.clamp(0, maxIndex);
  }

  double _clampLatitude(double lat) {
    const maxLat = 85.05112878;
    return lat.clamp(-maxLat, maxLat);
  }

  LatLngBounds _tileBoundsForTile(int x, int y, int zoom) {
    return LatLngBounds.unsafe(
      north: _tileYToLat(y, zoom),
      south: _tileYToLat(y + 1, zoom),
      east: _tileXToLon(x + 1, zoom),
      west: _tileXToLon(x, zoom),
    );
  }

  double _tileXToLon(int x, int zoom) {
    final n = 1 << zoom;
    return x / n * 360.0 - 180.0;
  }

  double _tileYToLat(int y, int zoom) {
    final n = math.pi - (2.0 * math.pi * y) / (1 << zoom);
    return 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  bool _boundsIntersect(LatLngBounds a, LatLngBounds b) {
    return a.west <= b.east &&
        a.east >= b.west &&
        a.south <= b.north &&
        a.north >= b.south;
  }

  String _buildTileUrl(int x, int y, int zoom, {required String urlTemplate}) {
    return urlTemplate
        .replaceAll('{z}', zoom.toString())
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString());
  }
}

/// File service that pins how long a host's responses stay fresh.
///
/// Yandex sends its own `Cache-Control`, and honouring it makes the cache
/// re-validate tiles that are already on disk: rate-limit slots are spent on
/// files we hold, redraws of visited areas queue behind the limiter, and an
/// offline region quietly expires while the phone is nowhere near a network.
/// The project keeps tiles for the full cache period on purpose, so freshness
/// is pinned to that instead. Other hosts pass through untouched.
class PinnedFreshnessFileService extends FileService {
  PinnedFreshnessFileService({
    required this.pinnedHost,
    required this.lifetime,
    FileService? inner,
  }) : _inner = inner ?? HttpFileService();

  final String pinnedHost;
  final Duration lifetime;
  final FileService _inner;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final response = await _inner.get(url, headers: headers);
    if (!url.contains(pinnedHost)) return response;
    return _PinnedFreshnessResponse(response, lifetime);
  }
}

class _PinnedFreshnessResponse implements FileServiceResponse {
  _PinnedFreshnessResponse(this._inner, this._lifetime);

  final FileServiceResponse _inner;
  final Duration _lifetime;

  @override
  DateTime get validTill => DateTime.now().add(_lifetime);

  @override
  Stream<List<int>> get content => _inner.content;

  @override
  int? get contentLength => _inner.contentLength;

  @override
  int get statusCode => _inner.statusCode;

  @override
  String? get eTag => _inner.eTag;

  @override
  String get fileExtension => _inner.fileExtension;
}

/// Cache manager that paces requests to a host which publishes a rate ceiling.
///
/// flutter_map asks for every visible tile at once, so a first frame is easily
/// 30+ requests — the whole Yandex allowance — and the pacing therefore has to
/// sit under the tile provider, not only in the bulk downloader. Cache hits
/// skip the queue: an offline map must redraw at full speed.
class RateLimitedTileCacheManager extends CacheManager {
  RateLimitedTileCacheManager(
    super.config, {
    required this.throttledHost,
    required this.maxRequestsPerSecond,
  });

  final String throttledHost;
  final int maxRequestsPerSecond;

  final Stopwatch _elapsed = Stopwatch()..start();
  int _nextSlotMicros = 0;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    if (_isThrottled(url)) {
      final cached = await getFileFromCache(key ?? url);
      if (cached == null || cached.validTill.isBefore(DateTime.now())) {
        await _awaitSlot();
      }
    }
    yield* super.getFileStream(
      url,
      key: key,
      headers: headers,
      withProgress: withProgress,
    );
  }

  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async {
    if (_isThrottled(url)) await _awaitSlot();
    return super.downloadFile(
      url,
      key: key,
      authHeaders: authHeaders,
      force: force,
    );
  }

  bool _isThrottled(String url) => url.contains(throttledHost);

  /// Takes the next slot in the queue.
  ///
  /// The slot is claimed *before* awaiting, which is the whole point: tile
  /// requests arrive in parallel, and reserving afterwards would have every
  /// caller read the same `_nextSlotMicros`, wait the same amount and then
  /// fire together — exactly the burst a zoom or a fast pan produces. Dart's
  /// single thread makes the read-and-bump atomic as long as nothing is
  /// awaited in between.
  Future<void> _awaitSlot() async {
    final gap = (Duration.microsecondsPerSecond / maxRequestsPerSecond).ceil();
    final now = _elapsed.elapsedMicroseconds;
    final slot = math.max(_nextSlotMicros, now);
    _nextSlotMicros = slot + gap;
    final wait = slot - now;
    if (wait > 0) {
      await Future<void>.delayed(Duration(microseconds: wait));
    }
  }
}

/// Cache key for a tile URL.
///
/// Yandex carries the API key and the request signature in the query string,
/// so keying the cache on the raw URL would orphan every stored tile the
/// moment the user reissues either — precisely the offline regions this cache
/// exists to keep. Dropping both also means a tile stays valid when signing is
/// switched on or off.
String tileCacheKey(String url) {
  if (!url.contains(MapTileCacheService.yandexTileHost)) return url;
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final query = Map<String, String>.from(uri.queryParameters)
    ..remove('apikey')
    ..remove('signature');
  return uri.replace(queryParameters: query).toString();
}

/// Signs a Yandex request with the "simple signature" scheme.
///
/// `HMAC-SHA256` over the path and query with the host stripped — the string
/// starts at the leading slash and carries every parameter except `signature`
/// itself — keyed with the Base64UrlSafe-decoded secret. The digest goes back
/// in Base64UrlSafe, padding kept, as the last parameter, which is where the
/// API expects it.
///
/// A secret that will not decode yields an unsigned URL: the "optional" mode
/// accepts those, so a mistyped secret degrades instead of blanking the map.
String signYandexUrl(String url, String secret) {
  final key = _decodeSigningSecret(secret);
  if (key == null) return url;
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final signedPart = uri.query.isEmpty ? uri.path : '${uri.path}?${uri.query}';
  final digest = crypto.Hmac(
    crypto.sha256,
    key,
  ).convert(utf8.encode(signedPart));
  final signature = base64Url.encode(digest.bytes);
  return '$url&signature=$signature';
}

Uint8List? _decodeSigningSecret(String secret) {
  final trimmed = secret.trim();
  if (trimmed.isEmpty) return null;
  try {
    return base64Url.decode(base64Url.normalize(trimmed));
  } on FormatException {
    return null;
  }
}

class CachedNetworkTileProvider extends TileProvider {
  final BaseCacheManager cacheManager;

  /// Applied after the tile coordinates are substituted. Yandex signs the
  /// finished URL, so the signature can only be computed per tile, not baked
  /// into the template.
  final String Function(String url)? urlSigner;

  /// Per-request headers, since the User-Agent differs by host.
  final Map<String, String> Function(String url)? headersFor;

  CachedNetworkTileProvider({
    required this.cacheManager,
    this.urlSigner,
    this.headersFor,
    super.headers,
  });

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    final signedUrl = urlSigner?.call(url) ?? url;
    return CachedNetworkImageProvider(
      signedUrl,
      cacheKey: tileCacheKey(signedUrl),
      cacheManager: cacheManager,
      headers: headersFor?.call(signedUrl) ?? headers,
    );
  }
}

class _TileBounds {
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;

  const _TileBounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });
}
