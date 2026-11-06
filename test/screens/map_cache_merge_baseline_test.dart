import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mco_service/mco_service.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/screens/map_cache_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/map_tile_cache_service.dart';
import 'package:provider/provider.dart';

import '../support/wrapping_label_expectations.dart'
    show expectCompleteWrappingLabel;

final _bounds = LatLngBounds(const LatLng(-1, -1), const LatLng(1, 1));

class _Settings extends AppSettingsService {
  AppSettings value = AppSettings(
    mapCacheBounds: MapTileCacheService.boundsToJson(_bounds),
    mapCacheMinZoom: 3,
    mapCacheMaxZoom: 3,
  );
  int writes = 0;

  @override
  AppSettings get settings => value;

  @override
  Future<void> setMapCacheBounds(Map<String, double>? bounds) async {
    writes++;
    value = value.copyWith(mapCacheBounds: bounds);
    notifyListeners();
  }

  @override
  Future<void> setMapCacheZoomRange(int minZoom, int maxZoom) async {
    writes++;
    value = value.copyWith(mapCacheMinZoom: minZoom, mapCacheMaxZoom: maxZoom);
    notifyListeners();
  }
}

class _Sections extends SettingsSectionsService {
  @override
  bool get allowsRestrictedMapBulkDownload => false;
}

// Keep the real screen, tile-count calculation, source filtering and bounds
// serialization. Replace all tile IO: no image provider, HTTP or cache files.
class _Cache extends MapTileCacheService {
  _Cache(_Settings settings, {required this.allowsDownload})
      : super(appSettingsService: settings);

  final bool allowsDownload;
  final operations = <String>[];
  List<CachedTileInfo> tiles = const [
    CachedTileInfo(
      key: 'synthetic-tile',
      host: 'tile.openstreetmap.org',
      sourceId: 'osm_standard',
      zoom: 3,
      x: 4,
      y: 4,
      length: 1024,
    ),
  ];
  Completer<MapTileCacheResult>? pending;
  MapTileDownloadCancelToken? downloadToken;
  Map<String, double>? requestedBounds;
  int? requestedMinZoom;
  int? requestedMaxZoom;

  @override
  MapRasterSourceDefinition get source => MapRasterSourceDefinition(
    id: 'osm_standard',
    label: 'Synthetic offline map',
    description: 'In-memory test source',
    allowsBulkDownload: allowsDownload,
  );

  @override
  Widget buildTileLayer(BuildContext context, {double opacity = 1}) =>
      const SizedBox.expand();

  @override
  Future<CachedTileInventory> getCachedTileInventory() async {
    operations.add('inventory');
    return CachedTileInventory(
      tiles: List.unmodifiable(tiles),
      totalBytes: tiles.fold<int>(0, (total, tile) => total + tile.length),
    );
  }

  @override
  Future<void> clearCache() async {
    operations.add('clear');
    tiles = const [];
  }

  @override
  Future<MapTileCacheResult> downloadRegion({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    int concurrentDownloads = 8,
    Map<String, String>? headers,
    void Function(MapTileCacheProgress progress)? onProgress,
    MapTileDownloadCancelToken? cancelToken,
  }) {
    operations.add('download');
    requestedBounds = MapTileCacheService.boundsToJson(bounds);
    requestedMinZoom = minZoom;
    requestedMaxZoom = maxZoom;
    downloadToken = cancelToken;
    final result = Completer<MapTileCacheResult>();
    pending = result;
    onProgress?.call(const MapTileCacheProgress(completed: 1, total: 4, failed: 0));
    return result.future;
  }

  void finishCancelled() {
    final result = pending;
    if (result != null && !result.isCompleted) {
      result.complete(const MapTileCacheResult(
        total: 4,
        downloaded: 1,
        failed: 0,
        cancelled: true,
      ));
    }
  }
}

Future<void> _withScreen(
  WidgetTester tester,
  String locale,
  Future<void> Function(AppLocalizations, _Cache, _Settings) run, {
  bool allowsDownload = true,
  Size size = const Size(1000, 1400),
  double textScale = 1,
}) async {
  final settings = _Settings();
  final sections = _Sections();
  final cache = _Cache(settings, allowsDownload: allowsDownload);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  try {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettingsService>.value(value: settings),
        ChangeNotifierProvider<MapTileCacheService>.value(value: cache),
        ChangeNotifierProvider<SettingsSectionsService>.value(value: sections),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const MapCacheScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(MapCacheScreen)));
    await run(l10n, cache, settings);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    cache.finishCancelled();
    await tester.pumpAndSettle();
    cache.dispose();
    sections.dispose();
    settings.dispose();
  }
}

Future<void> _reveal(WidgetTester tester, Finder button) async {
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  expect(button.hitTestable(), findsOneWidget);
}

Finder _clearButton(AppLocalizations l10n) =>
    find.widgetWithText(OutlinedButton, l10n.mapCache_clearCacheButton);

Finder _downloadButton(AppLocalizations l10n) =>
    find.widgetWithText(ElevatedButton, l10n.mapCache_downloadTilesButton);

void main() {
  for (final locale in ['en', 'ru']) {
    for (final layout in [
      (name: 'phone', size: const Size(320, 568)),
      (name: 'landscape', size: const Size(568, 360)),
    ]) {
      for (final downloading in [false, true]) {
        testWidgets(
          'U11b6: complete cache action labels fit '
          '($locale, ${layout.name}, scale=2, downloading=$downloading)',
          (tester) async {
            await _withScreen(tester, locale, (l10n, cache, settings) async {
              final before = settings.value.toJson();
              if (downloading) {
                // Start on the roomy viewport; this case tests resizing an
                // active download, while the idle case starts on a phone.
                final download = _downloadButton(l10n);
                await _reveal(tester, download);
                await tester.tap(download);
                await tester.pumpAndSettle();
                await tester.tap(find.widgetWithText(
                  TextButton, l10n.mapCache_downloadAction,
                ));
                await tester.pumpAndSettle();
                tester.view.physicalSize = layout.size;
                await tester.pumpAndSettle();
              }
              expect(tester.takeException(), isNull);

              final useView = find.widgetWithText(
                ElevatedButton, l10n.mapCache_useCurrentView,
              );
              final clearArea = find.widgetWithText(TextButton, l10n.common_clear);
              await _reveal(tester, useView);
              await _reveal(tester, clearArea);
              final useViewRect = tester.getRect(useView);
              final clearAreaRect = tester.getRect(clearArea);
              expect(useViewRect.left, greaterThanOrEqualTo(0));
              expect(clearAreaRect.right, lessThanOrEqualTo(layout.size.width));
              expect(clearAreaRect.left,
                  greaterThanOrEqualTo(useViewRect.right + 11));
              expectCompleteWrappingLabel(
                tester,
                find.descendant(of: useView,
                    matching: find.text(l10n.mapCache_useCurrentView)),
                wraps: layout.name == 'phone',
              );
              expectCompleteWrappingLabel(
                tester,
                find.descendant(of: clearArea, matching: find.text(l10n.common_clear)),
                wraps: layout.name == 'phone',
              );
              expect(tester.widget<ElevatedButton>(useView).onPressed,
                  downloading ? isNull : isNotNull);
              expect(tester.widget<TextButton>(clearArea).onPressed,
                  downloading ? isNull : isNotNull);

              final clear = _clearButton(l10n);
              final other = downloading
                  ? find.widgetWithText(OutlinedButton, l10n.common_cancel)
                  : _downloadButton(l10n);
              await _reveal(tester, clear);
              await _reveal(tester, other);
              final clearRect = tester.getRect(clear);
              final otherRect = tester.getRect(other);
              expect(otherRect.left, greaterThanOrEqualTo(0));
              expect(clearRect.right, lessThanOrEqualTo(layout.size.width));
              expect(clearRect.left, greaterThanOrEqualTo(otherRect.right + 11));
              expectCompleteWrappingLabel(
                tester,
                find.descendant(of: clear,
                    matching: find.text(l10n.mapCache_clearCacheButton)),
                wraps: layout.name == 'phone',
              );
              expectCompleteWrappingLabel(
                tester,
                find.descendant(of: other, matching: find.text(downloading
                    ? l10n.common_cancel : l10n.mapCache_downloadTilesButton)),
                wraps: false,
              );
              expect(tester.widget<OutlinedButton>(clear).onPressed,
                  downloading ? isNull : isNotNull);
              expect(settings.writes, 0);
              expect(settings.value.toJson(), before);
              expect(cache.tiles, hasLength(1));
              expect(cache.operations,
                  downloading ? ['inventory', 'download'] : ['inventory']);

              if (downloading) {
                expect(other.hitTestable(), findsOneWidget);
                await tester.tap(other);
                await tester.pump();
                expect(cache.downloadToken!.isCancelled, isTrue);
                expect(tester.widget<OutlinedButton>(clear).onPressed, isNull);
                cache.finishCancelled();
                await tester.pumpAndSettle();
                expect(tester.widget<OutlinedButton>(clear).onPressed, isNotNull);
                expect(cache.operations, ['inventory', 'download', 'inventory']);
                expect(cache.tiles, hasLength(1));
              } else {
                // Clearing the selection must not clear downloaded tiles or
                // alter the saved zoom range.
                await _reveal(tester, clearArea);
                await tester.tap(clearArea);
                await tester.pumpAndSettle();
                expect(settings.writes, 1);
                expect(settings.value.toJson(),
                    {...before, 'map_cache_bounds': null});
                expect(cache.tiles, hasLength(1));
                expect(cache.operations, ['inventory']);
                expect(tester.widget<TextButton>(clearArea).onPressed, isNull);
                expect(tester.widget<ElevatedButton>(_downloadButton(l10n)).onPressed, isNull);
              }
              expect(tester.takeException(), isNull);
            }, size: downloading ? const Size(1000, 1400) : layout.size,
                textScale: 2);
          },
        );
      }
    }

    testWidgets('U11b6 baseline: clear requires confirmation and preserves map settings ($locale)', (tester) async {
      await _withScreen(tester, locale, (l10n, cache, settings) async {
        final before = settings.value.toJson();
        expect(cache.operations, ['inventory']);
        expect(cache.tiles, hasLength(1));
        final clear = _clearButton(l10n);
        await _reveal(tester, clear);
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(find.text(l10n.mapCache_clearOfflineCachePrompt), findsOneWidget);
        expect(cache.operations, ['inventory']);
        await tester.tap(find.widgetWithText(TextButton, l10n.common_cancel));
        await tester.pumpAndSettle();
        expect(cache.tiles, hasLength(1));
        expect(cache.operations, ['inventory']);

        await tester.tap(clear);
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, l10n.common_clear),
        ));
        await tester.pumpAndSettle();
        expect(cache.operations, ['inventory', 'clear', 'inventory']);
        expect(cache.tiles, isEmpty);
        expect(find.text(l10n.mapCache_offlineCacheCleared), findsOneWidget);
        expect(find.textContaining(l10n.mapCache_summaryCachedTilesForSource(0)),
            findsOneWidget);
        expect(settings.writes, 0);
        expect(settings.value.toJson(), before);
      });
    });

    for (final closeScreen in [false, true]) {
      testWidgets('U11b6 baseline: download protects clear and cancels cooperatively ($locale, close=$closeScreen)', (tester) async {
        await _withScreen(tester, locale, (l10n, cache, settings) async {
          final before = settings.value.toJson();
          final download = _downloadButton(l10n);
          await _reveal(tester, download);
          await tester.tap(download);
          await tester.pumpAndSettle();
          expect(cache.operations, ['inventory']);
          expect(find.text(l10n.mapCache_downloadTilesPrompt(4)), findsOneWidget);
          await tester.tap(find.widgetWithText(TextButton, l10n.common_cancel));
          await tester.pumpAndSettle();
          expect(cache.operations, ['inventory']);

          await tester.tap(download);
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, l10n.mapCache_downloadAction));
          await tester.pumpAndSettle();
          expect(cache.operations, ['inventory', 'download']);
          expect(cache.requestedBounds, MapTileCacheService.boundsToJson(_bounds));
          expect(cache.requestedMinZoom, 3);
          expect(cache.requestedMaxZoom, 3);
          expect(cache.downloadToken, isNotNull);
          expect(cache.downloadToken!.isCancelled, isFalse);
          expect(tester.widget<OutlinedButton>(_clearButton(l10n)).onPressed, isNull);
          expect(find.text(l10n.mapCache_downloadedTiles(1, 4)), findsOneWidget);

          if (closeScreen) {
            await tester.pumpWidget(const SizedBox.shrink());
          } else {
            final cancel = find.widgetWithText(OutlinedButton, l10n.common_cancel);
            await _reveal(tester, cancel);
            await tester.tap(cancel);
            await tester.pump();
            expect(tester.widget<OutlinedButton>(cancel).onPressed, isNull);
            expect(tester.widget<OutlinedButton>(_clearButton(l10n)).onPressed, isNull);
          }
          expect(cache.downloadToken!.isCancelled, isTrue);
          cache.finishCancelled();
          await tester.pumpAndSettle();
          expect(cache.tiles, hasLength(1));
          expect(cache.operations.where((op) => op == 'clear'), isEmpty);
          if (!closeScreen) {
            expect(cache.operations, ['inventory', 'download', 'inventory']);
            expect(tester.widget<OutlinedButton>(_clearButton(l10n)).onPressed, isNotNull);
            expect(find.text(l10n.mapCache_downloadCancelled(1)), findsOneWidget);
          }
          expect(settings.writes, 0);
          expect(settings.value.toJson(), before);
        });
      });
    }

    testWidgets('U11b6 baseline: a restricted source disables bulk download ($locale)', (tester) async {
      await _withScreen(tester, locale, (l10n, cache, settings) async {
        await _reveal(tester, _downloadButton(l10n));
        expect(tester.widget<ElevatedButton>(_downloadButton(l10n)).onPressed, isNull);
        expect(tester.widget<OutlinedButton>(_clearButton(l10n)).onPressed, isNotNull);
        expect(cache.operations, ['inventory']);
        expect(cache.tiles, hasLength(1));
        expect(settings.writes, 0);
      }, allowsDownload: false);
    });
  }
}
