import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../helpers/coincident_repeater_offsets.dart';

/// Keeps all marker coordinates and gestures intact while spreading hit boxes.
class CoincidentRepeaterMarkerLayer extends StatefulWidget {
  const CoincidentRepeaterMarkerLayer({
    super.key,
    required this.markers,
    required this.repeaterKeys,
    required this.maxZoom,
  });
  final List<Marker> markers;
  final Set<String> repeaterKeys;
  final double maxZoom;

  @override
  State<CoincidentRepeaterMarkerLayer> createState() =>
      _CoincidentRepeaterMarkerLayerState();
}

class _CoincidentRepeaterMarkerLayerState
    extends State<CoincidentRepeaterMarkerLayer> {
  List<Marker>? _previous;
  Set<String> _keys = const {};
  double? _spreadZoom;
  MarkerLayer? _layer;

  String? _id(Key? key, String prefix) {
    if (key is! ValueKey<String> || !key.value.startsWith(prefix)) {
      return null;
    }
    final id = key.value.substring(prefix.length);
    return widget.repeaterKeys.contains(id) ? id : null;
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final zoom = camera.zoom;
    final active = zoom >= widget.maxZoom - 3;
    final spreadZoom = active ? zoom : null;
    if (!identical(_previous, widget.markers) ||
        _spreadZoom != spreadZoom ||
        _keys.length != widget.repeaterKeys.length ||
        !_keys.containsAll(widget.repeaterKeys)) {
      _previous = widget.markers;
      _spreadZoom = spreadZoom;
      _keys = Set.unmodifiable(widget.repeaterKeys);
      final positions = {
        for (final marker in widget.markers)
          ?_id(marker.key, 'node:'): marker.point,
      };
      final offsets = coincidentRepeaterOffsets(
        positions,
        zoom: zoom,
        maxZoom: widget.maxZoom,
        project: (point) => camera.projectAtZoom(point),
        worldWidth: camera.getWorldWidthAtZoom(),
      );
      _layer = MarkerLayer(markers: [
        for (final marker in widget.markers) _shift(marker, offsets),
      ]);
    }
    // Reuse the layer widget on camera-only changes. Recreating it on every
    // pan would discard flutter_map's projected-coordinate cache each frame.
    return _layer!;
  }

  Marker _shift(Marker marker, Map<String, Offset> offsets) {
    final id = _id(marker.key, 'node:') ?? _id(marker.key, 'label:');
    final offset = offsets[id];
    if (offset == null) {
      return marker;
    }
    return Marker(
      key: marker.key,
      point: marker.point,
      width: marker.width,
      height: marker.height,
      alignment: shiftedMarkerAlignment(
        base: marker.alignment ?? Alignment.center,
        offset: offset,
        width: marker.width,
        height: marker.height,
      ),
      rotate: marker.rotate,
      child: marker.child,
    );
  }
}
