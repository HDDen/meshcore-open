import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/services/network_map/network_map_api_client.dart';
import 'package:meshcore_open/services/network_map/network_map_availability.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';
import 'package:meshcore_open/widgets/network_map_online_layer.dart';

// The renderer reads only these snapshots. Do not construct a real controller:
// that would create an HTTP client and obscure the disabled feature's boundary.
class _SnapshotController extends ChangeNotifier
    implements NetworkMapOnlineController {
  _SnapshotController(this.repeaters, this.links);

  @override
  final List<NetworkMapRepeater> repeaters;
  @override
  final List<NetworkMapLink> links;
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
}) {
  final latitude = 55.75 + index * 0.001;
  final longitude = 37.62 + index * 0.001;
  return NetworkMapRepeater(
    key: 'synthetic-$index',
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
    locationSource: 'advert',
    confidence: 1,
    status: status,
    confirmed: confirmed,
    sightings: 1,
    firstSeen: null,
    lastSeen: null,
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
    expect(lines[0].color, MapPalette.router.withValues(alpha: 0.85));
    expect(lines[1].color, MapPalette.router.withValues(alpha: 0.6));

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
