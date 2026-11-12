import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/network_map_filters.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/services/network_map/network_map_api_client.dart';
import 'package:meshcore_open/services/network_map/network_map_availability.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';
import 'package:meshcore_open/widgets/network_map_online_layer.dart';

// The renderer reads only these snapshots. Do not construct a real controller:
// that would create an HTTP client and obscure the disabled feature's boundary.
class _SnapshotController extends ChangeNotifier
    implements NetworkMapOnlineController {
  _SnapshotController(this.repeaters, this._links);

  @override
  final List<NetworkMapRepeater> repeaters;
  final List<NetworkMapLink> _links;
  int linkReads = 0;

  @override
  List<NetworkMapLink> get links {
    linkReads++;
    return _links;
  }

  @override
  final LayerHitNotifier<NetworkMapRepeater> hitNotifier = ValueNotifier(null);

  @override
  void dispose() {
    hitNotifier.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Renderer used unexpected controller state: $invocation');
}

NetworkMapRepeater _repeater(
  int index, {
  int type = advTypeRepeater,
  bool confirmed = true,
  NetworkMapRepeaterStatus status = NetworkMapRepeaterStatus.active,
  bool hasBoundary = true,
  String? key,
  String locationSource = 'advert',
  DateTime? lastSeen,
}) {
  final latitude = 55.75 + index * 0.001;
  final longitude = 37.62 + index * 0.001;
  return NetworkMapRepeater(
    key: key ?? 'synthetic-$index',
    name: 'Node $index',
    type: type,
    cell: NetworkMapCell(
      cell: 'cell-$index',
      center: LatLng(latitude, longitude),
      boundary: hasBoundary
          ? [
              LatLng(latitude - 0.0001, longitude),
              LatLng(latitude + 0.0001, longitude - 0.0001),
              LatLng(latitude + 0.0001, longitude + 0.0001),
            ]
          : const [],
    ),
    locationSource: locationSource,
    confidence: 1,
    status: status,
    confirmed: confirmed,
    sightings: 1,
    firstSeen: null,
    lastSeen: lastSeen,
  );
}

NetworkMapLink _link(
  NetworkMapRepeater a,
  NetworkMapRepeater b, {
  required bool confirmed,
}) => NetworkMapLink(
  a: a.key,
  b: b.key,
  aCell: a.cell,
  bCell: b.cell,
  packets: 1,
  snr: 7,
  confirmed: confirmed,
);

void main() {
  test('U18 baseline: the fork keeps the network map unavailable', () {
    expect(networkMapAvailable, isFalse);
  });

  testWidgets('U24 baseline: requests debounce to the latest bounds', (
    tester,
  ) async {
    final requested = <Uri>[];
    final controller = NetworkMapOnlineController(
      client: NetworkMapApiClient(
        client: MockClient((request) async {
          requested.add(request.url);
          return http.Response('{}', 200);
        }),
      ),
    );
    try {
      controller.requestBounds(
        LatLngBounds(const LatLng(51, 32), const LatLng(53, 34)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(requested, isEmpty);

      controller.requestBounds(
        LatLngBounds(const LatLng(54, 36), const LatLng(56, 38)),
      );
      await tester.pump(const Duration(milliseconds: 599));
      expect(requested, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(
        requested.map((uri) => uri.path),
        unorderedEquals(['/v1/repeaters', '/v1/links']),
      );
      expect(
        requested.map((uri) => uri.queryParameters['bbox']),
        everyElement('36.00000,54.00000,38.00000,56.00000'),
      );
      expect(controller.state, NetworkMapLoadState.ready);
    } finally {
      controller.dispose();
    }
  });

  testWidgets('U24 baseline: hiding online drops pending and late results', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final requested = <String>[];
    final controller = NetworkMapOnlineController(
      client: NetworkMapApiClient(
        client: MockClient((request) {
          requested.add(request.url.path);
          return response.future;
        }),
      ),
    );
    final bounds = LatLngBounds(const LatLng(54, 36), const LatLng(56, 38));
    var notifications = 0;
    controller.addListener(() => notifications++);
    try {
      controller.requestBounds(bounds);
      controller.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(requested, isEmpty);
      expect(notifications, 0);

      controller.requestBounds(bounds);
      await tester.pump(const Duration(seconds: 1));
      expect(
        requested,
        unorderedEquals(['/v1/repeaters', '/v1/links']),
      );
      expect(controller.state, NetworkMapLoadState.loading);
      expect(notifications, 1);

      controller.cancel();
      response.complete(http.Response('{}', 200));
      await tester.pump();
      expect(notifications, 1);
    } finally {
      if (!response.isCompleted) {
        response.complete(http.Response('{}', 200));
      }
      controller.dispose();
      await tester.pump();
    }
  });

  testWidgets('U24: turning off links fences the old request immediately', (
    tester,
  ) async {
    final oldLinks = Completer<http.Response>();
    final requested = <String>[];
    final controller = NetworkMapOnlineController(
      client: NetworkMapApiClient(
        client: MockClient((request) async {
          requested.add(request.url.path);
          if (request.url.path == '/v1/links') return oldLinks.future;
          return http.Response('{}', 200);
        }),
      ),
    );
    final bounds = LatLngBounds(const LatLng(54, 36), const LatLng(56, 38));
    const debounce = Duration(milliseconds: 600);
    try {
      controller.requestBounds(bounds);
      await tester.pump(debounce);
      expect(requested, unorderedEquals(['/v1/repeaters', '/v1/links']));
      expect(controller.state, NetworkMapLoadState.loading);

      requested.clear();
      controller.requestBounds(bounds, fetchLinks: false);
      oldLinks.complete(http.Response('{}', 200));
      await tester.pump();
      expect(controller.state, NetworkMapLoadState.loading);
      expect(requested, isEmpty);

      await tester.pump(debounce);
      await tester.pump();
      expect(controller.state, NetworkMapLoadState.ready);
      expect(requested, ['/v1/repeaters']);
      expect(controller.links, isEmpty);

      requested.clear();
      controller.requestBounds(bounds);
      await tester.pump(debounce);
      await tester.pump();
      expect(requested, unorderedEquals(['/v1/repeaters', '/v1/links']));
    } finally {
      if (!oldLinks.isCompleted) {
        oldLinks.complete(http.Response('{}', 200));
      }
      controller.dispose();
      await tester.pump();
    }
  });

  test('U24: online links default to visible and persist independently', () {
    final legacy = AppSettings.fromJson({'map_show_repeaters': false});
    expect(legacy.mapShowOnlineLinks, isTrue);
    final updated = legacy.copyWith(mapShowOnlineLinks: false);
    final reopened = AppSettings.fromJson(updated.toJson());
    expect(reopened.mapShowOnlineLinks, isFalse);
    expect(reopened.mapShowRepeaters, isFalse);
  });

  test('U24: online snapshot respects the map visibility filters', () {
    final now = DateTime.utc(2026, 11, 7, 12);
    final active = _repeater(0, key: 'AB01', lastSeen: now);
    final recent = _repeater(
      1,
      key: 'ab02',
      status: NetworkMapRepeaterStatus.recent,
    );
    final stale = _repeater(
      2,
      key: 'ab03',
      status: NetworkMapRepeaterStatus.stale,
    );
    final old = _repeater(
      3,
      key: 'ab04',
      lastSeen: now.subtract(const Duration(hours: 3)),
    );
    final room = _repeater(4, key: 'ab05', type: advTypeRoom);
    final chat = _repeater(5, key: 'ab06', type: advTypeChat);
    final estimated = _repeater(6, key: 'ab07', locationSource: 'estimated');
    final otherPrefix = _repeater(7, key: 'cd01');
    final nodes = [active, recent, stale, old, room, chat, estimated, otherPrefix];
    final settings = AppSettings().copyWith(
      mapKeyPrefixEnabled: true,
      mapKeyPrefix: ' Ab ',
      mapTimeFilterHours: 2,
      mapShowOtherNodes: false,
      mapShowGuessedLocations: false,
      mapShowChatNodes: false,
    );
    List<NetworkMapRepeater> filter(
      AppSettings config, {
      Set<NetworkMapRepeaterStatus>? statuses,
    }) => filterNetworkMapRepeaters(
      nodes,
      settings: config,
      now: now,
      statuses: statuses,
    );

    expect(filter(settings), [active, recent, stale]);
    expect(
      filter(settings, statuses: {NetworkMapRepeaterStatus.active}),
      [active],
    );
    expect(filter(settings.copyWith(mapShowRepeaters: false)), isEmpty);
    expect(filter(settings.copyWith(mapTimeFilterHours: 0)), [
      active,
      recent,
      stale,
      old,
    ]);
    expect(
      filter(
        settings.copyWith(
          mapShowOtherNodes: true,
          mapShowChatNodes: true,
          mapShowGuessedLocations: true,
          mapKeyPrefixEnabled: false,
          mapTimeFilterHours: 0,
        ),
      ),
      nodes,
    );
  });

  test('U24: links join only visible nodes and are unread when hidden', () {
    final a = _repeater(0);
    final b = _repeater(1);
    final c = _repeater(2);
    final controller = _SnapshotController(
      [a, b, c],
      [_link(a, b, confirmed: true), _link(a, c, confirmed: true)],
    );
    addTearDown(controller.dispose);
    List<Widget> layers({required bool showLinks}) => buildNetworkMapOnlineLayers(
      controller: controller,
      repeaters: [a, b],
      showLinks: showLinks,
      localMarkerKeys: const {},
      onTap: (_) {},
    );

    final shown = layers(showLinks: true);
    final lines = shown.whereType<PolylineLayer>().single.polylines;
    expect(lines.single.points, [a.cell.center, b.cell.center]);
    final hidden = layers(showLinks: false);
    expect(hidden.whereType<PolylineLayer>(), isEmpty);
    expect(controller.linkReads, 1);
    expect(
      hidden.whereType<MarkerLayer>().single.markers.map((marker) => marker.point),
      [a.cell.center, b.cell.center],
    );
  });

  test('U18 baseline: sparse links retain geometry, styles and marker actions', () {
    final repeater = _repeater(0);
    final room = _repeater(
      1,
      type: advTypeRoom,
      confirmed: false,
      status: NetworkMapRepeaterStatus.recent,
    );
    final controller = _SnapshotController(
      [repeater, room],
      [
        _link(repeater, room, confirmed: true),
        _link(room, repeater, confirmed: false),
      ],
    );
    addTearDown(controller.dispose);
    final tapped = <NetworkMapRepeater>[];
    final layers = buildNetworkMapOnlineLayers(
      controller: controller,
      localMarkerKeys: const {},
      onTap: tapped.add,
    );
    final lines = layers.whereType<PolylineLayer>().single.polylines;
    expect(lines, hasLength(2));
    expect(lines[0].points, [repeater.cell.center, room.cell.center]);
    expect(lines[1].points, [room.cell.center, repeater.cell.center]);
    expect(lines.map((line) => line.strokeWidth), [3.5, 2.5]);
    expect(lines.map((line) => line.borderStrokeWidth), [1, 1]);
    expect(lines[0].pattern, const StrokePattern.solid());
    expect(lines[1].pattern, StrokePattern.dashed(segments: const [10, 8]));
    expect(lines.map((line) => line.color), everyElement(MapPalette.router));
    expect(lines.map((line) => line.color.a), everyElement(1.0));
    expect(lines.map((line) => line.borderColor.a), everyElement(1.0));

    final markers = layers.whereType<MarkerLayer>().single.markers;
    expect(markers.map((marker) => marker.point), [
      repeater.cell.center,
      room.cell.center,
    ]);
    for (var index = 0; index < markers.length; index++) {
      final marker = markers[index];
      expect(marker.width, 34);
      expect(marker.height, 34);
      final action = marker.child as GestureDetector;
      final decoration = (action.child! as Container).decoration! as BoxDecoration;
      expect(decoration.boxShadow, hasLength(1));
      final icon = (action.child! as Container).child! as Icon;
      expect(icon.icon, index == 0 ? Icons.router : Icons.meeting_room);
      action.onTap!();
    }
    expect(tapped, [repeater, room]);
  });

  test('U18 baseline: local duplicates retain outlines and invalid cells do not', () {
    final local = _repeater(0);
    final remote = _repeater(1, confirmed: false);
    final noBoundary = _repeater(2, hasBoundary: false);
    final controller = _SnapshotController([local, remote, noBoundary], []);
    addTearDown(controller.dispose);
    final layers = buildNetworkMapOnlineLayers(
      controller: controller,
      localMarkerKeys: {local.key},
      onTap: (_) {},
    );
    final polygonHost = layers.whereType<GestureDetector>().single;
    final polygons =
        (polygonHost.child! as PolygonLayer<NetworkMapRepeater>).polygons;
    expect(polygons.map((polygon) => polygon.hitValue), [local, remote]);
    expect(polygons.first.color, isNull);
    expect(polygons[1].color,
        networkMapStatusColor(remote.status).withValues(alpha: 0.22));
    expect(polygons.map((polygon) => polygon.borderStrokeWidth), [2.5, 2.5]);
    final markers = layers.whereType<MarkerLayer>().single.markers;
    expect(markers.map((marker) => marker.point), [
      remote.cell.center,
      noBoundary.cell.center,
    ]);
  });

  test('U18 baseline: an empty snapshot has no network or controller work', () {
    final controller = _SnapshotController([], []);
    addTearDown(controller.dispose);
    final layers = buildNetworkMapOnlineLayers(
      controller: controller,
      localMarkerKeys: const {},
      onTap: (_) => fail('Empty snapshot cannot produce a repeater action'),
    );
    expect(layers.whereType<PolylineLayer>().single.polylines, isEmpty);
    expect(layers.whereType<MarkerLayer>().single.markers, isEmpty);
    final polygons = layers.whereType<GestureDetector>().single.child!
        as PolygonLayer<NetworkMapRepeater>;
    expect(polygons.polygons, isEmpty);
    expect(controller.hitNotifier.value, isNull);
  });

  testWidgets('U34: dense online markers remain tappable in one painted layer', (
    tester,
  ) async {
    final nodes = List.generate(networkMapMarkerWidgetLimit + 1, _repeater);
    final local = nodes.first;
    final remote = nodes[1];
    final controller = _SnapshotController(nodes, []);
    addTearDown(controller.dispose);
    final tapped = <NetworkMapRepeater>[];
    List<Widget> layers(List<NetworkMapRepeater> visible) =>
        buildNetworkMapOnlineLayers(
          controller: controller,
          repeaters: visible,
          showLinks: false,
          localMarkerKeys: {local.key},
          onTap: tapped.add,
        );

    final atLimit = layers(nodes.take(networkMapMarkerWidgetLimit).toList());
    expect(atLimit.whereType<MarkerLayer>().single.markers,
        hasLength(networkMapMarkerWidgetLimit - 1));
    final aboveLimit = layers(nodes);
    expect(aboveLimit.whereType<MarkerLayer>(), isEmpty);
    final circles = (aboveLimit.single as GestureDetector).child!
        as CircleLayer<NetworkMapRepeater>;
    expect(circles.circles.map((circle) => circle.hitValue), nodes.skip(1));
    expect(circles.circles.first.color, networkMapStatusColor(remote.status));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FlutterMap(
          options: MapOptions(initialCenter: remote.cell.center, initialZoom: 16),
          children: aboveLimit,
        ),
      ),
    ));
    final center = tester.getCenter(find.byType(FlutterMap));
    await tester.tapAt(center);
    await tester.tapAt(center + const Offset(35, 0));
    // The tap outside a circle starts flutter_map's double-tap window.
    await tester.pump(const Duration(milliseconds: 250));
    expect(tapped, [remote]);
    expect(controller.linkReads, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('U34: the link limit counts only visible nondegenerate connections', () {
    final nodes = List.generate(60, _repeater);
    final outside = _repeater(60);
    final sameCell = _repeater(0, key: 'same-cell');
    final links = List.generate(networkMapMaxLinkCount + 1, (index) {
      final from = index % nodes.length;
      final to = (from + 1 + index ~/ nodes.length) % nodes.length;
      return _link(nodes[from], nodes[to], confirmed: index.isEven);
    });
    final records = [
      ...links.take(networkMapMaxLinkCount),
      _link(nodes.first, sameCell, confirmed: true),
      _link(nodes.first, outside, confirmed: true),
    ];
    final controller = _SnapshotController([...nodes, sameCell, outside], records);
    addTearDown(controller.dispose);
    List<Widget> layers({required bool showLinks}) => buildNetworkMapOnlineLayers(
      controller: controller,
      repeaters: [...nodes, sameCell],
      showLinks: showLinks,
      localMarkerKeys: const {},
      onTap: (_) {},
    );

    expect(layers(showLinks: true).whereType<PolylineLayer>().single.polylines,
        hasLength(networkMapMaxLinkCount));
    records.add(links.last);
    expect(layers(showLinks: true).whereType<PolylineLayer>(), isEmpty);
    expect(layers(showLinks: false).whereType<PolylineLayer>(), isEmpty);
    expect(controller.linkReads, 2);
  });

  for (final scenario in [
    (nodes: 30, links: 70, denseNodes: false, denseLinks: false),
    (nodes: 31, links: 70, denseNodes: true, denseLinks: false),
    (nodes: 30, links: 71, denseNodes: false, denseLinks: true),
    (nodes: 31, links: 71, denseNodes: true, denseLinks: true),
  ]) {
    test(
      'U18: ${scenario.nodes} nodes and ${scenario.links} links use independent density limits',
      () {
        final repeaters = List.generate(scenario.nodes, (index) => _repeater(index));
        final links = List.generate(scenario.links, (index) {
          final from = index % repeaters.length;
          final offset = 1 + index ~/ repeaters.length;
          final to = (from + offset) % repeaters.length;
          return _link(repeaters[from], repeaters[to], confirmed: index.isEven);
        });
        final controller = _SnapshotController(repeaters, links);
        addTearDown(controller.dispose);
        final tapped = <NetworkMapRepeater>[];
        final layers = buildNetworkMapOnlineLayers(
          controller: controller,
          localMarkerKeys: {repeaters.first.key},
          onTap: tapped.add,
        );

        final polygonHosts = layers.whereType<GestureDetector>();
        if (scenario.denseNodes) {
          expect(polygonHosts, isEmpty);
        } else {
          final polygons =
              (polygonHosts.single.child! as PolygonLayer<NetworkMapRepeater>)
                  .polygons;
          expect(polygons, hasLength(scenario.nodes));
          expect(polygons.first.color, isNull);
        }
        final markers = layers.whereType<MarkerLayer>().single.markers;
        expect(markers.map((marker) => marker.point), [
          for (final repeater in repeaters.skip(1)) repeater.cell.center,
        ]);
        for (final marker in markers) {
          final action = marker.child as GestureDetector;
          final container = action.child! as Container;
          final decoration = container.decoration! as BoxDecoration;
          expect(decoration.boxShadow, scenario.denseNodes ? isNull : hasLength(1));
        }
        (markers.last.child as GestureDetector).onTap!();
        expect(tapped, [repeaters.last]);

        final lines = layers.whereType<PolylineLayer>().single.polylines;
        expect(lines, hasLength(scenario.links));
        for (var index = 0; index < lines.length; index++) {
          final link = links[index];
          final line = lines[index];
          final fullWidth = link.confirmed ? 3.5 : 2.5;
          expect(line.points, [link.aCell.center, link.bCell.center]);
          expect(line.strokeWidth, scenario.denseLinks ? fullWidth / 2 : fullWidth);
          expect(line.borderStrokeWidth, scenario.denseLinks ? 0 : 1);
          expect(
            line.pattern,
            link.confirmed
                ? const StrokePattern.solid()
                : StrokePattern.dashed(segments: const [10, 8]),
          );
        }
      },
    );
  }
}
