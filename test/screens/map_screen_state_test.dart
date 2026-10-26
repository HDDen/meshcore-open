import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mco_service/mco_service.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/map_session_zoom.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/screens/map_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/map_tile_cache_service.dart';
import 'package:meshcore_open/services/path_history_service.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/services/wardrive_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/utils/app_route_observer.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What the map screen promises about staying current, pinned before its build
// learns to skip work: a node that appears while another page covers the map
// is on the map after the return, a marker follows new coordinates and a
// label a new name, the search lists the nodes whose name matches, and the
// wardrive coverage follows the samples. The map is driven through a fake
// connector whose node list the tests change by hand.

class _FakeConnector extends MeshCoreConnector {
  final List<Contact> nodes = [];
  final List<Uint8List> sentFrames = [];

  @override
  bool get hasReadableSession => true;

  @override
  bool get isConnected => true;

  @override
  Uint8List? get selfPublicKey =>
      Uint8List.fromList(List<int>.generate(32, (i) => 0xF0 + i));

  @override
  List<Contact> get contacts => List.unmodifiable(nodes);

  @override
  List<Contact> get allContacts => List.unmodifiable(nodes);

  @override
  List<Contact> get allContactsUnfiltered => List.unmodifiable(nodes);

  @override
  Future<void> getChannels({int? maxChannels, bool force = false}) async {}

  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    sentFrames.add(frame);
  }

  /// Adds [contact] or replaces the node with its key, and notifies, as an
  /// advert does.
  void replace(Contact contact) {
    final index = nodes.indexWhere(
      (node) => node.publicKeyHex == contact.publicKeyHex,
    );
    if (index < 0) {
      nodes.add(contact);
    } else {
      nodes[index] = contact;
    }
    notifyListeners();
  }
}

Contact _node(int seed, String name, double latitude, double longitude) =>
    Contact(
      publicKey: Uint8List.fromList(
        List<int>.generate(32, (i) => i == 0 ? seed : (seed * 7 + i) & 0xFF),
      ),
      name: name,
      type: advTypeChat,
      pathLength: 0,
      path: Uint8List(0),
      latitude: latitude,
      longitude: longitude,
      lastSeen: DateTime.now(),
    );

Contact _nodeWithoutLocation(int seed, String name) => Contact(
  publicKey: Uint8List.fromList(
    List<int>.generate(32, (i) => i == 0 ? seed : (seed * 7 + i) & 0xFF),
  ),
  name: name,
  type: advTypeChat,
  pathLength: 0,
  path: Uint8List(0),
  lastSeen: DateTime.now(),
);

Map<String, Object?> _sample(String id, double latitude, double longitude) => {
  'id': id,
  'lat': latitude,
  'lon': longitude,
  'timestamp': '2026-09-28T10:00:00.000Z',
  'pingSuccess': true,
  'publicKeyHex': 'aa11',
  'snr': 5.0,
  'rssi': -90,
};

/// Lets the map's asynchronous setup and the stores behind it run: removed
/// markers, the location choice, the wardrive samples.
Future<void> _pumpFrames(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Iterable<LatLng> _markerPoints(WidgetTester tester) => tester
    .widgetList<MarkerLayer>(find.byType(MarkerLayer, skipOffstage: false))
    .expand((layer) => layer.markers)
    .map((marker) => marker.point);

int _polygonCount(WidgetTester tester) => tester
    .widgetList<PolygonLayer>(find.byType(PolygonLayer, skipOffstage: false))
    .fold(0, (count, layer) => count + layer.polygons.length);

class _Harness {
  _Harness(this.connector, this.wardrive);

  final _FakeConnector connector;
  final WardriveService wardrive;

  /// The map over the usual providers, with [nodes] known to the connector
  /// and the session zoom at [zoom], which decides whether labels show.
  static Future<_Harness> pump(
    WidgetTester tester, {
    required List<Contact> nodes,
    required double zoom,
  }) async {
    MapSessionZoom.remember(zoom);
    final connector = _FakeConnector()..nodes.addAll(nodes);
    final settings = AppSettingsService();
    // The phone location request notifies the wardrive service from inside
    // the map's first build, which the test framework reports as an error;
    // the map centres on its nodes instead.
    await settings.updateSettings(
      settings.settings.copyWith(alwaysRequestMapLocation: false),
    );
    final wardrive = WardriveService(connector);
    final sections = SettingsSectionsService();
    final paths = PathHistoryService(StorageService());
    addTearDown(() {
      wardrive.dispose();
      sections.dispose();
      paths.dispose();
      settings.dispose();
      connector.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
          ChangeNotifierProvider<AppSettingsService>.value(value: settings),
          ChangeNotifierProvider<MapTileCacheService>(
            create: (_) => MapTileCacheService(appSettingsService: settings),
          ),
          ChangeNotifierProvider<PathHistoryService>.value(value: paths),
          ChangeNotifierProvider<WardriveService>.value(value: wardrive),
          ChangeNotifierProvider<SettingsSectionsService>.value(
            value: sections,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: [appRouteObserver],
          home: const MapScreen(),
        ),
      ),
    );
    await _pumpFrames(tester);
    return _Harness(connector, wardrive);
  }

  /// Takes the map down while the services behind it are still alive: the
  /// map's dispose reaches the wardrive service, and a test that failed
  /// would otherwise leave the map to the next test's first frame.
  static Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }
}

void main() {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mco_map_state_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(() {
    PrefsManager.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // A tile cache file may still be open; the directory is temporary.
    }
  });

  const alicePoint = LatLng(55.75, 37.62);
  const bobPoint = LatLng(55.80, 37.70);

  testWidgets('a node that appears while another page covers the map is on '
      'the map after the return', (tester) async {
    try {
      final harness = await _Harness.pump(
        tester,
        nodes: [_node(1, 'Alice', 55.75, 37.62)],
        zoom: 15,
      );
      expect(_markerPoints(tester), contains(alicePoint));

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('another page')),
          ),
        ),
      );
      await _pumpFrames(tester);
      expect(find.text('another page'), findsOneWidget);

      harness.connector.replace(_node(2, 'Bob', 55.80, 37.70));
      await _pumpFrames(tester);

      navigator.pop();
      await _pumpFrames(tester);

      expect(find.text('another page'), findsNothing);
      expect(_markerPoints(tester), contains(bobPoint));
      expect(_markerPoints(tester), contains(alicePoint));
    } finally {
      await _Harness.unmount(tester);
    }
  });

  testWidgets('a marker follows the coordinates of its node', (tester) async {
    try {
      final harness = await _Harness.pump(
        tester,
        nodes: [_node(1, 'Alice', 55.75, 37.62)],
        zoom: 15,
      );
      expect(_markerPoints(tester), contains(alicePoint));

      harness.connector.replace(_node(1, 'Alice', 55.90, 37.90));
      await _pumpFrames(tester);

      expect(_markerPoints(tester), contains(const LatLng(55.90, 37.90)));
      expect(_markerPoints(tester), isNot(contains(alicePoint)));
    } finally {
      await _Harness.unmount(tester);
    }
  });

  testWidgets('a label follows the name of its node', (tester) async {
    try {
      final harness = await _Harness.pump(
        tester,
        nodes: [_node(1, 'Alice', 55.75, 37.62)],
        zoom: 15,
      );
      expect(find.text('Alice'), findsOneWidget);

      harness.connector.replace(_node(1, 'Alicia', 55.75, 37.62));
      await _pumpFrames(tester);

      expect(find.text('Alicia'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
    } finally {
      await _Harness.unmount(tester);
    }
  });

  testWidgets('the search lists the nodes whose name matches', (tester) async {
    try {
      // Below the label zoom, so a name on screen can only be a search
      // result.
      await _Harness.pump(
        tester,
        nodes: [
          _node(1, 'Alice', 55.75, 37.62),
          _node(2, 'Bob', 55.80, 37.70),
        ],
        zoom: 10,
      );
      expect(find.text('Alice'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'ali');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
    } finally {
      await _Harness.unmount(tester);
    }
  });

  // The work the build skips now: under another page the last tree is handed
  // back untouched and built anew once on the return; the search waits for
  // the typing to pause; an advert from a node off the map leaves the node
  // markers as they are; the coverage polygons are reused while the samples
  // stay. Observed through widget and marker identity.
  group('the build skips work', () {
    testWidgets('under another page the last tree is handed back untouched '
        'and built anew once on the return', (tester) async {
      try {
        final harness = await _Harness.pump(
          tester,
          nodes: [_node(1, 'Alice', 55.75, 37.62)],
          zoom: 15,
        );
        MarkerLayer layer() => tester.widgetList<MarkerLayer>(
          find.byType(MarkerLayer, skipOffstage: false),
        ).first;
        final shown = layer();

        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('another page')),
            ),
          ),
        );
        await _pumpFrames(tester);
        harness.connector.replace(_node(2, 'Bob', 55.80, 37.70));
        await _pumpFrames(tester);

        expect(identical(layer(), shown), isTrue, reason: 'not rebuilt');
        expect(_markerPoints(tester), isNot(contains(bobPoint)));

        navigator.pop();
        await _pumpFrames(tester);

        expect(identical(layer(), shown), isFalse, reason: 'built anew');
        expect(_markerPoints(tester), contains(bobPoint));
      } finally {
        await _Harness.unmount(tester);
      }
    });

    testWidgets('the search waits for the typing to pause', (tester) async {
      try {
        await _Harness.pump(
          tester,
          nodes: [
            _node(1, 'Alice', 55.75, 37.62),
            _node(2, 'Bob', 55.80, 37.70),
          ],
          zoom: 10,
        );

        await tester.enterText(find.byType(TextField).first, 'ali');
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Alice'), findsNothing, reason: 'still typing');

        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(find.text('Alice'), findsOneWidget);
      } finally {
        await _Harness.unmount(tester);
      }
    });

    testWidgets('an advert from a node off the map leaves the node markers '
        'as they are', (tester) async {
      try {
        final harness = await _Harness.pump(
          tester,
          nodes: [_node(1, 'Alice', 55.75, 37.62)],
          zoom: 15,
        );
        Marker aliceMarker() => tester
            .widgetList<MarkerLayer>(
              find.byType(MarkerLayer, skipOffstage: false),
            )
            .expand((layer) => layer.markers)
            .firstWhere((marker) => marker.point == alicePoint);
        final before = aliceMarker();
        expect(before.key, isNotNull);

        // A node without a position is on no map, only in the lists.
        harness.connector.replace(_nodeWithoutLocation(3, 'Carol'));
        await _pumpFrames(tester);

        expect(identical(aliceMarker(), before), isTrue);

        harness.connector.replace(_node(1, 'Alicia', 55.75, 37.62));
        await _pumpFrames(tester);

        expect(identical(aliceMarker(), before), isFalse);
      } finally {
        await _Harness.unmount(tester);
      }
    });

    testWidgets('the coverage polygons are reused while the samples stay', (
      tester,
    ) async {
      try {
        final harness = await _Harness.pump(
          tester,
          nodes: [_node(1, 'Alice', 55.75, 37.62)],
          zoom: 15,
        );
        await harness.wardrive.importSamplesJson(
          jsonEncode([_sample('s1', 55.75, 37.62)]),
        );
        harness.wardrive.showMapState();
        await _pumpFrames(tester);
        List<Polygon> polygons() => tester
            .widgetList<PolygonLayer>(
              find.byType(PolygonLayer, skipOffstage: false),
            )
            .first
            .polygons;
        final before = polygons();
        expect(before, isNotEmpty);

        // A notification that changes nothing about the samples.
        harness.connector.replace(_node(2, 'Bob', 55.80, 37.70));
        await _pumpFrames(tester);
        expect(identical(polygons(), before), isTrue);

        await harness.wardrive.importSamplesJson(
          jsonEncode([_sample('s2', 55.95, 37.95)]),
        );
        await _pumpFrames(tester);
        expect(identical(polygons(), before), isFalse);
        expect(polygons().length, before.length + 1);
      } finally {
        await _Harness.unmount(tester);
      }
    });
  });

  testWidgets('the wardrive coverage follows the samples', (tester) async {
    try {
      final harness = await _Harness.pump(
        tester,
        nodes: [_node(1, 'Alice', 55.75, 37.62)],
        zoom: 15,
      );
      expect(_polygonCount(tester), 0);

      await harness.wardrive.importSamplesJson(
        jsonEncode([_sample('s1', 55.75, 37.62)]),
      );
      harness.wardrive.showMapState();
      await _pumpFrames(tester);
      final before = _polygonCount(tester);
      expect(before, greaterThan(0));

      // A second sample in another cell, twenty kilometres away.
      await harness.wardrive.importSamplesJson(
        jsonEncode([_sample('s2', 55.95, 37.95)]),
      );
      await _pumpFrames(tester);

      expect(_polygonCount(tester), before + 1);
    } finally {
      await _Harness.unmount(tester);
    }
  });
  // Предварительные контракты перед исправлением слоёв карточки и FAB.
  // Исходные проверки используют свободную левую часть действий;
  // отдельные регрессии ниже проверяют реальное перекрытие справа.
  group('selected repeater card baseline', () {
    Future<_Harness> selectRepeater(WidgetTester tester) async {
      final repeater = _node(21, 'Layer test relay', 55.75, 37.62)
          .copyWith(type: advTypeRepeater);
      final harness = await _Harness.pump(tester, nodes: [repeater], zoom: 10);
      harness.wardrive.showMapState();
      await _pumpFrames(tester);
      final l10n = AppLocalizations.of(tester.element(find.byType(MapScreen)));
      // Панель wardrive тоже содержит TextField (интервал auto-discovery).
      final search = find.byWidgetPredicate(
        (widget) => widget is TextField &&
            widget.decoration?.hintText == l10n.map_searchHint,
      );
      expect(search, findsOneWidget);
      await tester.enterText(search, repeater.name);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      // find.text также находит EditableText с введённым запросом.
      final result = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == repeater.name,
      );
      expect(result, findsOneWidget);
      final resultRow = find.ancestor(of: result, matching: find.byType(InkWell));
      expect(resultRow, findsOneWidget);
      await tester.tap(resultRow);
      await _pumpFrames(tester);
      return harness;
    }

    Future<void> tapLeft(WidgetTester tester, Finder label) async {
      final rect = tester.getRect(label);
      await tester.tapAt(Offset(rect.left + 4, rect.center.dy));
      await _pumpFrames(tester);
    }

    Finder mapFab(String tag) => find.byWidgetPredicate(
      (widget) => widget is FloatingActionButton && widget.heroTag == tag,
    );

    testWidgets('coverage action toggles without sending discovery', (tester) async {
      try {
        final harness = await selectRepeater(tester);
        final l10n = AppLocalizations.of(tester.element(find.byType(MapScreen)));
        final writes = harness.connector.sentFrames.length;
        expect(find.text(l10n.map_manageRepeater), findsOneWidget);
        await tapLeft(tester, find.text(l10n.map_wardriveShowRepeaterCoverage));
        expect(find.text(l10n.map_wardriveHideRepeaterCoverage), findsOneWidget);
        await tapLeft(tester, find.text(l10n.map_wardriveHideRepeaterCoverage));
        expect(find.text(l10n.map_wardriveShowRepeaterCoverage), findsOneWidget);
        expect(harness.connector.sentFrames, hasLength(writes));
        expect(harness.wardrive.isRunning, isFalse);
      } finally {
        await _Harness.unmount(tester);
      }
    });

    testWidgets('details open a modal above map controls', (tester) async {
      try {
        final harness = await selectRepeater(tester);
        final l10n = AppLocalizations.of(tester.element(find.byType(MapScreen)));
        final writes = harness.connector.sentFrames.length;
        await tapLeft(tester, find.text(l10n.map_details));
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text(l10n.map_wardriveShowRepeaterCoverage).hitTestable(),
            findsOneWidget);
        expect(mapFab('wardrive_discovery').hitTestable(), findsNothing);
        expect(harness.connector.sentFrames, hasLength(writes));
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await _pumpFrames(tester);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text(l10n.map_details), findsOneWidget);
      } finally {
        await _Harness.unmount(tester);
      }
    });

    testWidgets('wardrive control opens its panel without starting GPS or discovery',
        (tester) async {
      try {
        final harness = await _Harness.pump(
          tester, nodes: [_node(21, 'Layer test relay', 55.75, 37.62)], zoom: 10,
        );
        final writes = harness.connector.sentFrames.length;
        expect(harness.wardrive.hasMapState, isFalse);
        expect(mapFab('wardrive_toggle').hitTestable(), findsOneWidget);
        expect(mapFab('wardrive_discovery').hitTestable(), findsOneWidget);
        await tester.tap(mapFab('wardrive_toggle'));
        await _pumpFrames(tester);
        expect(harness.wardrive.hasMapState, isTrue);
        expect(harness.wardrive.isRunning, isFalse);
        expect(harness.connector.sentFrames, hasLength(writes));
      } finally {
        await _Harness.unmount(tester);
      }
    });

    for (final size in [const Size(390, 844), const Size(800, 600)]) {
      testWidgets('selected card receives overlapping controls at width ${size.width}',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          final harness = await selectRepeater(tester);
          final l10n = AppLocalizations.of(tester.element(find.byType(MapScreen)));
          final writes = harness.connector.sentFrames.length;
          final card = find.ancestor(
            of: find.text(l10n.map_details), matching: find.byType(MeshCard),
          );
          expect(card, findsOneWidget);
          final cardRect = tester.getRect(card);
          final cardRender = tester.renderObject(card);
          final before = <String, Rect>{};
          for (final tag in ['wardrive_toggle', 'wardrive_discovery']) {
            final fab = mapFab(tag);
            final fabRect = tester.getRect(fab);
            before[tag] = fabRect;
            final overlap = fabRect.intersect(cardRect);
            expect(overlap.isEmpty, isFalse,
                reason: 'The regression must exercise actual overlap: $tag');
            final targets = tester.hitTestOnBinding(overlap.center).path
                .map((entry) => entry.target).toList();
            expect(targets, contains(cardRender));
            expect(targets, isNot(contains(tester.renderObject(fab))),
                reason: 'Covered control must not receive the card tap: $tag');
          }
          final mapRect = tester.getRect(find.byType(FlutterMap));
          expect(before['wardrive_discovery']!.right,
              closeTo(mapRect.right - kFloatingActionButtonMargin, 0.01));
          final filter = find.ancestor(
            of: find.byIcon(Icons.filter_list),
            matching: find.byType(FloatingActionButton),
          );
          expect(filter, findsOneWidget);
          expect(tester.getRect(filter).bottom,
              closeTo(mapRect.bottom - kFloatingActionButtonMargin, 0.01));

          // Нажатия обычным способом: важен настоящий hit test, а не вызов callback.
          await tester.tap(find.text(l10n.map_wardriveShowRepeaterCoverage));
          await _pumpFrames(tester);
          expect(find.text(l10n.map_wardriveHideRepeaterCoverage), findsOneWidget);
          expect(harness.connector.sentFrames, hasLength(writes));
          final close = find.descendant(of: card, matching: find.byIcon(Icons.close));
          expect(close, findsOneWidget);
          await tester.tap(close);
          await _pumpFrames(tester);
          expect(find.text(l10n.map_details), findsNothing);
          for (final tag in before.keys) {
            expect(mapFab(tag).hitTestable(), findsOneWidget);
            expect(tester.getRect(mapFab(tag)), before[tag]);
          }
          expect(harness.connector.sentFrames, hasLength(writes));
          expect(harness.wardrive.isRunning, isFalse);
        } finally {
          await _Harness.unmount(tester);
        }
      });
    }
  });
}
