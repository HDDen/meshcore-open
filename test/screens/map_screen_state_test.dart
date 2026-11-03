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
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/screens/channel_message_path_screen.dart';
import 'package:meshcore_open/screens/path_trace_map.dart';
import 'package:meshcore_open/screens/map_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/map_tile_cache_service.dart';
import 'package:meshcore_open/services/path_history_service.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/services/wardrive_service.dart';
import 'package:meshcore_open/services/ui_view_state_service.dart';
import 'package:meshcore_open/services/ui_view_state_service.dart';
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

/// Controls only device replies; setNodeLocation still uses the real frame
/// builder and the inherited sendFrame recorder.
class _LocationConnector extends _FakeConnector {
  bool connected = true;
  bool failRefresh = false;
  int refreshCount = 0;
  LatLng? reportedPosition;

  @override
  bool get isConnected => connected;

  @override
  double? get selfLatitude => reportedPosition?.latitude;

  @override
  double? get selfLongitude => reportedPosition?.longitude;

  void publishPosition(LatLng position) {
    reportedPosition = position;
    notifyListeners();
  }

  @override
  Future<void> refreshDeviceInfo() async {
    refreshCount++;
    if (failRefresh) {
      throw StateError('Synthetic SELF_INFO request failure');
    }
  }
}

class _PathLocationConnector extends _LocationConnector {
  final _frames = StreamController<Uint8List>.broadcast();
  int positionRefreshCount = 0;

  @override
  Stream<Uint8List> get receivedFrames => _frames.stream;

  @override
  Future<({double latitude, double longitude})?> refreshSelfLocation({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    positionRefreshCount++;
    final position = reportedPosition;
    return position == null
        ? null
        : (latitude: position.latitude, longitude: position.longitude);
  }

  void completeTrace() {
    final request = sentFrames.singleWhere((frame) => frame[0] == cmdSendTracePath);
    // TRACE request: [cmd][tag x4][auth x4][flags][path]. The SENT
    // response has a reserved byte before the tag; the request does not.
    final tag = request.sublist(1, 5);
    _frames.add(Uint8List.fromList([
      respCodeSent, 0, ...tag, 0x88, 0x13, 0, 0,
    ]));
    _frames.add(Uint8List.fromList([
      pushCodeTraceData, 0, 1, 0,
      ...tag, 0, 0, 0, 0,
      0x12, 12, 16,
    ]));
  }

  @override
  void dispose() {
    unawaited(_frames.close());
    super.dispose();
  }
}

class _PhoneLocationWardrive extends WardriveService {
  _PhoneLocationWardrive(super.connector, this.phonePosition);

  final LatLng? phonePosition;

  @override
  Future<({double latitude, double longitude})?> requestPhoneLocation() async {
    final position = phonePosition;
    return position == null
        ? null
        : (latitude: position.latitude, longitude: position.longitude);
  }
}

/// TRACE transport is recorded, never answered automatically. Each result
/// route is closed before its timeout; editing must send nothing at all.
class _TraceBuilderConnector extends _PathLocationConnector {
  _TraceBuilderConnector(this.width) {
    reportedPosition = const LatLng(55.70, 37.60);
  }

  final int width;
  int radioSeed = 0xE0;

  @override
  Uint8List? get selfPublicKey => Uint8List.fromList(
    List<int>.generate(32, (index) => (radioSeed + index) & 0xFF),
  );

  @override
  int get pathHashByteWidth => width;

  void completeCurrentTrace() {
    final request = sentFrames.lastWhere((frame) => frame.first == cmdSendTracePath);
    final tag = request.sublist(1, 5);
    final flags = request[9];
    final path = request.sublist(10);
    final width = 1 << (flags & 3);
    _frames.add(Uint8List.fromList([
      respCodeSent, 0, ...tag, 0x88, 0x13, 0, 0,
    ]));
    _frames.add(Uint8List.fromList([
      pushCodeTraceData, 0, path.length, flags,
      ...tag, 0, 0, 0, 0,
      ...path, ...List<int>.filled(path.length ~/ width + 1, 16),
    ]));
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
    _FakeConnector? connectorOverride,
    Widget? screenOverride,
    bool requestPhoneLocation = false,
    WardriveService Function(MeshCoreConnector)? wardriveFactory,
    UiViewStateService? viewState,
  }) async {
    MapSessionZoom.remember(zoom);
    final connector = connectorOverride ?? _FakeConnector();
    connector.nodes.addAll(nodes);
    final settings = AppSettingsService();
    // The phone location request notifies the wardrive service from inside
    // the map's first build, which the test framework reports as an error;
    // the map centres on its nodes instead.
    await settings.updateSettings(
      settings.settings.copyWith(alwaysRequestMapLocation: requestPhoneLocation),
    );
    final wardrive = wardriveFactory?.call(connector) ?? WardriveService(connector);
    final sections = SettingsSectionsService();
    final paths = PathHistoryService(StorageService());
    final view = viewState ?? UiViewStateService();
    addTearDown(() {
      if (viewState == null) view.dispose();
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
          ChangeNotifierProvider<UiViewStateService>.value(value: view),
          ChangeNotifierProvider<WardriveService>.value(value: wardrive),
          ChangeNotifierProvider<SettingsSectionsService>.value(
            value: sections,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: [appRouteObserver],
          home: screenOverride ?? const MapScreen(),
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

  group('U06b3 baseline: fork path-trace builder', () {
    List<int> hop(int width, int first) =>
        List<int>.generate(width, (index) => first + index);

    String hex(List<int> bytes) => bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();

    Contact repeater(List<int> prefix, String name, double latitude) {
      final key = Uint8List(32)..setRange(0, prefix.length, prefix);
      return _node(prefix.first, name, latitude, 37.62).copyWith(
        publicKey: key,
        type: advTypeRepeater,
      );
    }

    Finder editor(WidgetTester tester) {
      final l10n = AppLocalizations.of(tester.element(find.byType(MapScreen)));
      return find.byWidgetPredicate(
        (widget) => widget is TextField &&
            widget.decoration?.hintText == l10n.map_tapToAdd,
      );
    }

    String editorText(WidgetTester tester) =>
        tester.widget<TextField>(editor(tester)).controller!.text;

    Future<void> edit(WidgetTester tester, String text) async {
      await tester.enterText(editor(tester), text);
      tester.widget<TextField>(editor(tester)).focusNode!.unfocus();
      await _pumpFrames(tester);
    }

    void addMarker(WidgetTester tester, Contact contact) {
      // Use the real marker callback at a deterministic location. Camera
      // projection and an overlay covering a marker are outside this test.
      final marker = tester
          .widgetList<MarkerLayer>(find.byType(MarkerLayer))
          .expand((layer) => layer.markers)
          .singleWhere((marker) => marker.key == ValueKey('node:${contact.publicKeyHex}'));
      final gesture = marker.child as GestureDetector;
      expect(gesture.onTap, isNotNull);
      gesture.onTap!();
    }

    testWidgets('U06b3: close, reopen and a new map preserve the session draft and mode', (tester) async {
      final view = UiViewStateService();
      addTearDown(view.dispose);
      try {
        await _Harness.pump(
          tester, nodes: [], zoom: 15,
          connectorOverride: _TraceBuilderConnector(1), viewState: view,
          screenOverride: MapScreen(
            initialTracePath: Uint8List.fromList([0x10, 0x11, 0x20, 0x21]),
            initialTraceHashByteWidth: 2,
          ),
        );
        final l10n = AppLocalizations.of(tester.element(find.byType(MapScreen)));
        await tester.tap(find.text(l10n.map_pathTraceModeAsEntered));
        await _pumpFrames(tester);
        await tester.tap(find.text(l10n.common_close));
        await _pumpFrames(tester);
        expect(editor(tester), findsNothing);
        expect(view.mapPathTrace.active, isFalse);
        await tester.tap(find.byTooltip(l10n.contacts_pathTrace));
        await _pumpFrames(tester);
        expect(editorText(tester), '1011,2021');
        expect(view.mapPathTrace.returnPath, isFalse);
        await _Harness.unmount(tester);
        final next = await _Harness.pump(
          tester, nodes: [], zoom: 15, viewState: view,
          connectorOverride: _TraceBuilderConnector(1),
        );
        expect(editorText(tester), '1011,2021');
        expect(view.mapPathTrace.hashByteWidth, 2);
        expect(view.mapPathTrace.returnPath, isFalse);
        expect(next.connector.sentFrames, isEmpty);
      } finally {
        await _Harness.unmount(tester);
      }
    });

    testWidgets('U06b3: explicit routes override the draft and region routes keep it isolated', (tester) async {
      final view = UiViewStateService();
      addTearDown(view.dispose);
      try {
        view.mapPathTrace.pathBytes.add(0x11);
        await _Harness.pump(
          tester, nodes: [], zoom: 15, viewState: view,
          connectorOverride: _TraceBuilderConnector(1),
          screenOverride: MapScreen(initialTracePath: Uint8List.fromList([0x22])),
        );
        expect(editorText(tester), '22');
        expect(view.mapPathTrace.pathBytes, [0x22]);
        await _Harness.unmount(tester);
        final target = repeater([0x33], 'Region target', 55.73);
        final regional = await _Harness.pump(
          tester, nodes: [target], zoom: 15, viewState: view,
          connectorOverride: _TraceBuilderConnector(1),
          screenOverride: MapScreen(
            initialTracePath: Uint8List.fromList([0x33]), regionRequestTarget: target,
          ),
        );
        await edit(tester, '44,33');
        expect(editorText(tester), '44,33');
        expect(view.mapPathTrace.pathBytes, [0x22]);
        expect(regional.connector.sentFrames, isEmpty);
      } finally {
        await _Harness.unmount(tester);
      }
    });

    for (final invalidate in ['route', 'mode', 'radio']) {
      testWidgets('U06b3: last result reopens without sending and invalidates on $invalidate changes', (tester) async {
        final view = UiViewStateService();
        addTearDown(view.dispose);
        try {
          final connector = _TraceBuilderConnector(1);
          await _Harness.pump(
            tester, nodes: [repeater([0x10], 'First', 55.71), repeater([0x20], 'Second', 55.72)],
            zoom: 15, viewState: view, connectorOverride: connector,
            screenOverride: MapScreen(initialTracePath: Uint8List.fromList([0x10, 0x20])),
          );
          final l10n = AppLocalizations.of(tester.element(find.byType(MapScreen)));
          await tester.tap(find.text(l10n.map_runTrace));
          await _pumpFrames(tester);
          final live = tester.widget<PathTraceMapScreen>(find.byType(PathTraceMapScreen));
          connector.completeCurrentTrace();
          await _pumpFrames(tester);
          final saved = view.mapPathTrace.lastResult;
          expect(saved, isNotNull);
          Navigator.of(tester.element(find.byType(PathTraceMapScreen))).pop();
          await _pumpFrames(tester);
          await tester.tap(find.text(l10n.map_pathTraceViewLast));
          await _pumpFrames(tester);
          final replay = tester.widget<PathTraceMapScreen>(find.byType(PathTraceMapScreen));
          expect(replay.initialTraceFrame, orderedEquals(saved!.frame));
          expect(connector.sentFrames.where((frame) => frame.first == cmdSendTracePath), hasLength(1));
          Navigator.of(tester.element(find.byType(PathTraceMapScreen))).pop();
          await _pumpFrames(tester);
          if (invalidate == 'route') {
            await edit(tester, '10,30');
            await edit(tester, '10,20'); // Same bytes must not accept an old callback.
          } else if (invalidate == 'mode') {
            await tester.tap(find.text(l10n.map_pathTraceModeAsEntered));
            await _pumpFrames(tester);
          } else {
            connector.radioSeed++;
            connector.notifyListeners();
            await _pumpFrames(tester);
          }
          live.onTraceResult!(saved);
          expect(view.mapPathTrace.lastResult, isNull);
          expect(find.text(l10n.map_pathTraceViewLast), findsNothing);
          expect(connector.sentFrames.where((frame) => frame.first == cmdSendTracePath), hasLength(1));
        } finally {
          await _Harness.unmount(tester);
        }
      });
    }

    for (final width in [1, 2, 3]) {
      testWidgets('manual edits and removal preserve $width-byte hops without contacts', (tester) async {
        try {
          final connector = _TraceBuilderConnector(1);
          await _Harness.pump(
            tester,
            nodes: [],
            zoom: 15,
            connectorOverride: connector,
            screenOverride: MapScreen(
              initialTracePath: Uint8List.fromList([...hop(width, 0x10), ...hop(width, 0x20)]),
              initialTraceHashByteWidth: width,
            ),
          );
          final l10n = AppLocalizations.of(tester.element(find.byType(MapScreen)));
          expect(editorText(tester), '${hex(hop(width, 0x10))},${hex(hop(width, 0x20))}');
          final first = hex(hop(width, 0xA0));
          final second = hex(hop(width, 0xB0));
          final invalid = List<String>.filled(width * 2, 'Z').join();
          await edit(tester, ' ${first.toLowerCase()},, $invalid, ${second.toLowerCase()}, F ');
          expect(editorText(tester), '$first,$second');
          await tester.tap(find.text(l10n.map_removeLast));
          await _pumpFrames(tester);
          expect(editorText(tester), first);
          await tester.tap(find.text(l10n.map_removeLast));
          await _pumpFrames(tester);
          expect(editorText(tester), isEmpty);
          expect(connector.sentFrames, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await _Harness.unmount(tester);
        }
      });

      testWidgets('region request keeps its target last when adding a $width-byte hop', (tester) async {
        try {
          final connector = _TraceBuilderConnector(width);
          final first = repeater(hop(width, 0x10), 'First relay', 55.71);
          final middle = repeater(hop(width, 0x20), 'Middle relay', 55.72);
          final target = repeater(hop(width, 0x30), 'Region target', 55.73);
          await _Harness.pump(
            tester,
            nodes: [first, middle, target],
            zoom: 15,
            connectorOverride: connector,
            screenOverride: MapScreen(
              initialTracePath: Uint8List.fromList([...hop(width, 0x10), ...hop(width, 0x30)]),
              initialTraceHashByteWidth: width,
              regionRequestTarget: target,
            ),
          );
          final l10n = AppLocalizations.of(tester.element(find.byType(MapScreen)));
          addMarker(tester, middle);
          await _pumpFrames(tester);
          final expected = [hex(hop(width, 0x10)), hex(hop(width, 0x20)), hex(hop(width, 0x30))].join(',');
          expect(editorText(tester), expected);
          addMarker(tester, target);
          await _pumpFrames(tester);
          expect(editorText(tester), expected); // No duplicate terminal hop.
          expect(find.text(l10n.contacts_requestRegions), findsOneWidget);
          expect(find.text(l10n.map_runTrace), findsNothing);
          expect(find.text(l10n.map_runTraceWithReturnPath), findsNothing);
          expect(connector.sentFrames, isEmpty);
        } finally {
          await _Harness.unmount(tester);
        }
      });

      for (final roundTrip in [false, true]) {
        testWidgets('explicit trace preserves route width and editor on return: width=$width roundTrip=$roundTrip', (tester) async {
          try {
            // The route's explicit width takes precedence over the radio's
            // current mode, including expansion from 3-byte to 4-byte TRACE hops.
            final connector = _TraceBuilderConnector(1);
            final first = repeater(hop(width, 0x10), 'Outbound first', 55.71);
            final second = repeater(hop(width, 0x20), 'Outbound second', 55.72);
            final path = Uint8List.fromList([...hop(width, 0x10), ...hop(width, 0x20)]);
            await _Harness.pump(
              tester,
              nodes: [first, second],
              zoom: 15,
              connectorOverride: connector,
              screenOverride: MapScreen(initialTracePath: path, initialTraceHashByteWidth: width),
            );
            final l10n = AppLocalizations.of(tester.element(find.byType(MapScreen)));
            final original = editorText(tester);
            expect(connector.sentFrames, isEmpty);
            await tester.tap(find.text(roundTrip
                ? l10n.map_pathTraceModeRoundTrip : l10n.map_pathTraceModeAsEntered));
            await _pumpFrames(tester);
            await tester.tap(find.text(l10n.map_runTrace));
            await _pumpFrames(tester);
            final result = tester.widget<PathTraceMapScreen>(find.byType(PathTraceMapScreen));
            expect(result.path, orderedEquals(path));
            expect(result.pathHashByteWidth, width);
            expect(result.flipPathAround, roundTrip);
            expect(result.revealMapManually, isTrue);
            final frame = connector.sentFrames.singleWhere((frame) => frame.first == cmdSendTracePath);
            final traceWidth = width == 3 ? 4 : width;
            expect(frame[9], width - 1);
            expect(frame.sublist(10), orderedEquals([
              ...first.publicKey.take(traceWidth),
              ...second.publicKey.take(traceWidth),
              if (roundTrip) ...first.publicKey.take(traceWidth),
            ]));
            Navigator.of(tester.element(find.byType(PathTraceMapScreen))).pop();
            await _pumpFrames(tester);
            expect(find.byType(PathTraceMapScreen), findsNothing);
            expect(editorText(tester), original);
            expect(connector.sentFrames.where((frame) => frame.first == cmdSendTracePath), hasLength(1));
          } finally {
            await _Harness.unmount(tester);
          }
        });
      }
    }
  });

  group('U06b1 baseline: setting my location on the main map', () {
    const position = LatLng(55.762345, 37.654321);

    Future<AppLocalizations> openConfirmation(WidgetTester tester) async {
      final l10n = AppLocalizations.of(
        tester.element(find.byType(MapScreen)),
      );
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.options.onLongPress, isNotNull);
      // Exercise the current map callback with a deterministic coordinate;
      // tile loading and camera projection are outside this baseline.
      map.options.onLongPress!(
        const TapPosition(Offset(200, 200), Offset(200, 200)),
        position,
      );
      await _pumpFrames(tester);
      await tester.tap(find.text(l10n.map_setAsMyLocation));
      await _pumpFrames(tester);
      expect(find.text(l10n.map_setLocationConfirmTitle), findsOneWidget);
      expect(
        find.text(l10n.map_setLocationConfirmBody('55.762345', '37.654321')),
        findsOneWidget,
      );
      return l10n;
    }

    for (final scenario in ['cancel', 'confirmed', 'refresh error', 'disconnect']) {
      testWidgets(scenario, (tester) async {
        try {
          final connector = _LocationConnector();
          await _Harness.pump(
            tester,
            nodes: [_node(1, 'Synthetic location anchor', 55.75, 37.62)],
            zoom: 15,
            connectorOverride: connector,
          );
          final writesBefore = connector.sentFrames.length;
          final refreshesBefore = connector.refreshCount;
          final l10n = await openConfirmation(tester);
          // Opening menus and the confirmation must never send coordinates.
          expect(connector.sentFrames, hasLength(writesBefore));
          expect(connector.refreshCount, refreshesBefore);

          if (scenario == 'cancel') {
            await tester.tap(find.widgetWithText(TextButton, l10n.common_cancel));
            await _pumpFrames(tester);
            expect(connector.sentFrames, hasLength(writesBefore));
            expect(connector.refreshCount, refreshesBefore);
          } else {
            connector.connected = scenario != 'disconnect';
            connector.failRefresh = scenario == 'refresh error';
            await tester.tap(
              find.widgetWithText(FilledButton, l10n.map_setLocationAction),
            );
            await tester.pump();

            if (scenario == 'disconnect') {
              await _pumpFrames(tester);
              expect(connector.sentFrames, hasLength(writesBefore));
              expect(connector.refreshCount, refreshesBefore);
              expect(find.text(l10n.map_locationSetSuccess), findsNothing);
            } else {
              expect(
                connector.sentFrames.skip(writesBefore).toList(),
                [buildSetAdvertLatLonFrame(position.latitude, position.longitude)],
              );
              expect(connector.refreshCount, refreshesBefore + 1);

              if (scenario == 'confirmed') {
                // A successful write or unrelated SELF_INFO is insufficient.
                expect(find.text(l10n.map_locationSetSuccess), findsNothing);
                connector.publishPosition(const LatLng(55.70, 37.60));
                await tester.pump(const Duration(milliseconds: 300));
                expect(find.text(l10n.map_locationSetSuccess), findsNothing);
                // Keep the existing micro-degree rounding tolerance.
                connector.publishPosition(
                  LatLng(
                    position.latitude + 1e-6,
                    position.longitude - 1e-6,
                  ),
                );
                await _pumpFrames(tester);
                expect(find.text(l10n.map_locationSetSuccess), findsOneWidget);
                expect(find.text(l10n.map_locationSetFailed), findsNothing);
                expect(connector.refreshCount, refreshesBefore + 1);
              } else {
                await _pumpFrames(tester);
                final failure = find.text(l10n.map_locationSetFailed);
                expect(failure, findsOneWidget);
                expect(find.text(l10n.map_locationSetSuccess), findsNothing);
                final surface = find.ancestor(
                  of: failure,
                  matching: find.byType(Material),
                ).first;
                expect(
                  tester.widget<Material>(surface).color,
                  Theme.of(tester.element(find.byType(MapScreen))).colorScheme.error,
                );
              }
            }
          }
          expect(tester.takeException(), isNull);
        } finally {
          // Dispose the map before its services and its overlay timeout.
          await _Harness.unmount(tester);
        }
      });
    }
  });

  group('U06b1: path map location actions and phone-first display', () {
    const nodePosition = LatLng(54.50, 36.50);
    const phonePosition = LatLng(55.70, 37.60);
    const selectedPosition = LatLng(55.762345, 37.654321);

    for (final trace in [false, true]) {
      for (final secondaryTap in [false, true]) {
        for (final hasPhone in [false, true]) {
          testWidgets(
            '${trace ? 'trace' : 'channel'} map ${secondaryTap ? 'right click' : 'long press'}, phone=$hasPhone',
            (tester) async {
              try {
                final connector = _PathLocationConnector()
                  ..reportedPosition = nodePosition;
                final path = Uint8List.fromList([0x12]);
                final screen = trace
                    ? PathTraceMapScreen(title: 'Synthetic trace', path: path)
                    : ChannelMessagePathMapScreen(
                        message: ChannelMessage(
                          senderName: 'Synthetic sender',
                          text: 'Synthetic path message',
                          timestamp: DateTime.utc(2026),
                          receivedAt: DateTime.utc(2026),
                          isOutgoing: false,
                          pathLength: 1,
                          pathBytes: path,
                          pathHashWidth: 1,
                        ),
                        channelMessage: true,
                      );
                await _Harness.pump(
                  tester,
                  nodes: [
                    _node(0x12, 'Synthetic path hop', 55.75, 37.62)
                        .copyWith(type: advTypeRepeater),
                  ],
                  zoom: 15,
                  connectorOverride: connector,
                  screenOverride: screen,
                  requestPhoneLocation: true,
                  wardriveFactory: (connector) => _PhoneLocationWardrive(
                    connector,
                    hasPhone ? phonePosition : null,
                  ),
                );
                if (trace) {
                  connector.completeTrace();
                  await _pumpFrames(tester);
                }
                expect(
                  find.byType(FlutterMap),
                  findsOneWidget,
                  reason: 'A matching trace reply must reveal the map before testing its actions',
                );
                final l10n = AppLocalizations.of(
                  tester.element(find.byType(FlutterMap)),
                );
                expect(
                  _markerPoints(tester),
                  contains(hasPhone ? phonePosition : nodePosition),
                );
                final writesBefore = connector.sentFrames.length;
                final positionRefreshes = connector.positionRefreshCount;

                Future<void> openConfirmation() async {
                  final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
                  final callback = secondaryTap
                      ? map.options.onSecondaryTap
                      : map.options.onLongPress;
                  expect(callback, isNotNull);
                  callback!(
                    const TapPosition(Offset(200, 200), Offset(200, 200)),
                    selectedPosition,
                  );
                  await _pumpFrames(tester);
                  expect(find.text(l10n.map_setLocationConfirmTitle), findsOneWidget);
                  expect(connector.sentFrames, hasLength(writesBefore));
                }

                await openConfirmation();
                await tester.tap(find.widgetWithText(TextButton, l10n.common_cancel));
                await _pumpFrames(tester);
                expect(connector.sentFrames, hasLength(writesBefore));

                await openConfirmation();
                await tester.tap(
                  find.widgetWithText(FilledButton, l10n.map_setLocationAction),
                );
                await tester.pump();
                expect(find.text(l10n.map_locationSetSuccess), findsNothing);
                connector.publishPosition(selectedPosition);
                await _pumpFrames(tester);
                expect(find.text(l10n.map_locationSetSuccess), findsOneWidget);
                expect(
                  connector.sentFrames.skip(writesBefore).toList(),
                  [buildSetAdvertLatLonFrame(
                    selectedPosition.latitude,
                    selectedPosition.longitude,
                  )],
                );
                // No extra location reads or trace requests after setting it.
                expect(connector.positionRefreshCount, positionRefreshes);
                expect(
                  _markerPoints(tester),
                  contains(hasPhone ? phonePosition : selectedPosition),
                );
                expect(_markerPoints(tester), isNot(contains(nodePosition)));
                expect(tester.takeException(), isNull);
              } finally {
                await _Harness.unmount(tester);
              }
            },
          );
        }
      }
    }
  });

  group('U06b2: fork map filters and active badge', () {
    void expectFilterCount(WidgetTester tester, int count) {
      final l10n = AppLocalizations.of(tester.element(find.byType(MapScreen)));
      final finder = find.descendant(
        of: find.byTooltip(l10n.map_filterNodes),
        matching: find.byType(Badge),
      );
      expect(finder, findsOneWidget);
      final badge = tester.widget<Badge>(finder);
      expect(badge.isLabelVisible, count > 0);
      expect((badge.label! as Text).data, '$count');
    }

    testWidgets('quick filters collapse, persist and reopen without radio work', (tester) async {
      try {
        final nodes = [_node(1, 'Synthetic filter contact', 55.75, 37.62)];
        final harness = await _Harness.pump(tester, nodes: nodes, zoom: 15);
        final l10n = AppLocalizations.of(tester.element(find.byType(MapScreen)));
        final writes = harness.connector.sentFrames.length;
        expect(find.byType(SegmentedButton<MapSourceOption>), findsNothing);
        expect(find.text(l10n.time_allTime), findsOneWidget);
        expect(find.text(l10n.map_repeaters), findsOneWidget);
        expect(find.text(l10n.map_chatNodes), findsOneWidget);
        expect(find.text(l10n.map_groupChip), findsOneWidget);

        await tester.tap(find.text(l10n.listFilter_filters));
        await _pumpFrames(tester);
        expect(find.text(l10n.time_allTime), findsNothing);
        expect(find.text(l10n.map_repeaters), findsNothing);
        expect(find.text(l10n.map_chatNodes), findsNothing);
        expect(PrefsManager.instance.getBool('map_node_filters_expanded_v1'), isFalse);
        expect(harness.connector.sentFrames, hasLength(writes));
        expect(harness.wardrive.isRunning, isFalse);
        expect(harness.wardrive.lastPhoneLocationAt, isNull);

        await _Harness.unmount(tester);
        final reopened = await _Harness.pump(tester, nodes: nodes, zoom: 15);
        final reopenedWrites = reopened.connector.sentFrames.length;
        expect(find.text(l10n.time_allTime), findsNothing);
        await tester.tap(find.text(l10n.listFilter_filters));
        await _pumpFrames(tester);
        expect(find.text(l10n.time_allTime), findsOneWidget);
        expect(find.text(l10n.map_groupChip), findsOneWidget);
        expect(PrefsManager.instance.getBool('map_node_filters_expanded_v1'), isTrue);
        expect(reopened.connector.sentFrames, hasLength(reopenedWrites));
        expect(find.byType(SegmentedButton<MapSourceOption>), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _Harness.unmount(tester);
      }
    });

    testWidgets('quick type filters and sheet switches share visibility and settings', (tester) async {
      try {
        const chatPoint = LatLng(55.75, 37.62);
        const repeaterPoint = LatLng(55.80, 37.70);
        const roomPoint = LatLng(55.90, 37.85);
        final harness = await _Harness.pump(
          tester,
          nodes: [
            _node(1, 'Synthetic chat', chatPoint.latitude, chatPoint.longitude),
            _node(2, 'Synthetic repeater', repeaterPoint.latitude, repeaterPoint.longitude)
                .copyWith(type: advTypeRepeater),
            _node(3, 'Synthetic room', roomPoint.latitude, roomPoint.longitude)
                .copyWith(type: advTypeRoom),
          ],
          zoom: 15,
        );
        final mapContext = tester.element(find.byType(MapScreen));
        final settings = mapContext.read<AppSettingsService>();
        final l10n = AppLocalizations.of(mapContext);
        final writes = harness.connector.sentFrames.length;
        expect(_markerPoints(tester), containsAll([chatPoint, repeaterPoint, roomPoint]));
        expectFilterCount(tester, 1);

        final repeaterChip = find.text(l10n.map_repeaters);
        await tester.ensureVisible(repeaterChip);
        await tester.pump();
        expect(repeaterChip.hitTestable(), findsOneWidget);
        await tester.tap(repeaterChip);
        await _pumpFrames(tester);
        expect(_markerPoints(tester), isNot(contains(repeaterPoint)));
        expect(_markerPoints(tester), containsAll([chatPoint, roomPoint]));
        expectFilterCount(tester, 2);
        final chatChip = find.text(l10n.map_chatNodes);
        await tester.ensureVisible(chatChip);
        await tester.pump();
        expect(chatChip.hitTestable(), findsOneWidget);
        await tester.tap(chatChip);
        await _pumpFrames(tester);
        expect(_markerPoints(tester), isNot(contains(chatPoint)));
        expect(_markerPoints(tester), contains(roomPoint));
        expectFilterCount(tester, 3);

        await tester.tap(find.byTooltip(l10n.map_filterNodes));
        await _pumpFrames(tester);
        final chatSwitch = find.widgetWithText(SwitchListTile, l10n.map_chatNodes);
        final repeaterSwitch = find.widgetWithText(SwitchListTile, l10n.map_repeaters);
        expect(chatSwitch, findsOneWidget);
        expect(repeaterSwitch, findsOneWidget);
        expect(tester.widget<SwitchListTile>(chatSwitch).value, isFalse);
        expect(tester.widget<SwitchListTile>(repeaterSwitch).value, isFalse);
        await tester.ensureVisible(chatSwitch);
        await tester.tap(chatSwitch);
        await _pumpFrames(tester);
        expect(settings.settings.mapShowChatNodes, isTrue);
        expect(settings.settings.mapShowRepeaters, isFalse);
        Navigator.of(tester.element(chatSwitch)).pop();
        await _pumpFrames(tester);
        expect(_markerPoints(tester), containsAll([chatPoint, roomPoint]));
        expect(_markerPoints(tester), isNot(contains(repeaterPoint)));
        expectFilterCount(tester, 2);
        expect(harness.connector.sentFrames, hasLength(writes));
        expect(harness.wardrive.isRunning, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await _Harness.unmount(tester);
      }
    });

    testWidgets('badge counts restrictions, ignores view modes and survives collapsing', (tester) async {
      try {
        final harness = await _Harness.pump(
          tester,
          nodes: [_node(0x0A, 'Synthetic badge contact', 55.75, 37.62)],
          zoom: 15,
        );
        final mapContext = tester.element(find.byType(MapScreen));
        final settings = mapContext.read<AppSettingsService>();
        final l10n = AppLocalizations.of(mapContext);
        final writes = harness.connector.sentFrames.length;
        // The fork defaults to a seven-day limit. It is already an active
        // restriction; zero means all limits have actually been cleared.
        expectFilterCount(tester, 1);
        await settings.setMapTimeFilterHours(0);
        await _pumpFrames(tester);
        final initial = settings.settings;
        expectFilterCount(tester, 0);

        await settings.setMapClusterNodes(!initial.mapClusterNodes);
        await settings.setMapShowOverlaps(!initial.mapShowOverlaps);
        await settings.setMapKeyPrefix('   ');
        await settings.setMapKeyPrefixEnabled(true);
        await _pumpFrames(tester);
        expectFilterCount(tester, 0);
        await settings.setMapKeyPrefix('0A');
        await _pumpFrames(tester);
        expectFilterCount(tester, 1);
        await settings.setMapTimeFilterHours(6);
        await _pumpFrames(tester);
        expectFilterCount(tester, 2);

        await settings.updateSettings(settings.settings.copyWith(
          mapShowChatNodes: false,
          mapShowRepeaters: false,
          mapShowOtherNodes: false,
          mapShowMarkers: false,
          mapShowGuessedLocations: false,
          mapShowDiscoveryContacts: false,
        ));
        await _pumpFrames(tester);
        expectFilterCount(tester, 8);
        final recent = find.text(l10n.map_recent);
        await tester.ensureVisible(recent);
        await tester.pump();
        expect(recent.hitTestable(), findsOneWidget);
        await tester.tap(recent);
        await _pumpFrames(tester);
        expectFilterCount(tester, 9);

        final filters = find.text(l10n.listFilter_filters);
        await tester.ensureVisible(filters);
        await tester.pump();
        await tester.tap(filters);
        await _pumpFrames(tester);
        expect(find.text(l10n.map_recent), findsNothing);
        expectFilterCount(tester, 9);
        await tester.tap(filters);
        await _pumpFrames(tester);
        final allTime = find.text(l10n.time_allTime);
        await tester.ensureVisible(allTime);
        await tester.pump();
        expect(allTime.hitTestable(), findsOneWidget);
        await tester.tap(allTime);
        await settings.updateSettings(initial);
        await _pumpFrames(tester);
        expectFilterCount(tester, 0);
        expect(find.byType(SegmentedButton<MapSourceOption>), findsNothing);
        expect(harness.connector.sentFrames, hasLength(writes));
        expect(harness.wardrive.isRunning, isFalse);
        expect(harness.wardrive.lastPhoneLocationAt, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await _Harness.unmount(tester);
      }
    });

    testWidgets('time and trimmed case-insensitive key prefix keep their current effects', (tester) async {
      try {
        const first = LatLng(55.75, 37.62);
        const second = LatLng(55.80, 37.70);
        const old = LatLng(55.90, 37.85);
        final harness = await _Harness.pump(
          tester,
          nodes: [
            _node(0x0A, 'Synthetic A', first.latitude, first.longitude),
            _node(0x0B, 'Synthetic B', second.latitude, second.longitude),
            _node(0x0C, 'Synthetic old', old.latitude, old.longitude).copyWith(
              lastSeen: DateTime.now().subtract(const Duration(days: 2)),
            ),
          ],
          zoom: 15,
        );
        final settings = tester.element(find.byType(MapScreen)).read<AppSettingsService>();
        final writes = harness.connector.sentFrames.length;
        await settings.setMapTimeFilterHours(6);
        await _pumpFrames(tester);
        expect(_markerPoints(tester), containsAll([first, second]));
        expect(_markerPoints(tester), isNot(contains(old)));
        await settings.setMapKeyPrefix(' 0A ');
        await settings.setMapKeyPrefixEnabled(true);
        await _pumpFrames(tester);
        expect(_markerPoints(tester), contains(first));
        expect(_markerPoints(tester), isNot(contains(second)));
        await settings.setMapKeyPrefixEnabled(false);
        await settings.setMapTimeFilterHours(0);
        await _pumpFrames(tester);
        expect(_markerPoints(tester), containsAll([first, second, old]));
        await settings.setMapKeyPrefix('   ');
        await settings.setMapKeyPrefixEnabled(true);
        await _pumpFrames(tester);
        expect(_markerPoints(tester), containsAll([first, second, old]));
        expect(harness.connector.sentFrames, hasLength(writes));
        expect(harness.wardrive.lastPhoneLocationAt, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await _Harness.unmount(tester);
      }
    });
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
