import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/painting.dart' show Alignment;
import 'package:latlong2/latlong.dart';

/// Compact pixel offsets for repeaters within eight metres of each other.
/// Geographic coordinates never change; the caller moves marker anchors only.
Map<String, Offset> coincidentRepeaterOffsets(
  Map<String, LatLng> positions, {
  required double zoom,
  required double maxZoom,
  double spacing = 42,
  Offset Function(LatLng)? project,
  double worldWidth = 0,
}) {
  if (zoom < maxZoom - 5 || spacing <= 0) {
    return const {};
  }
  final groups = <List<String>>[];
  // Index group anchors in Earth-centred cells. This works across the date line
  // and near the poles without scanning every distant repeater for each point.
  final cells = <(int, int, int), List<int>>{};
  const distance = Distance(roundResult: false);
  final keys = positions.keys.where((key) {
    final point = positions[key]!;
    return point.latitude.isFinite && point.longitude.isFinite;
  }).toList()..sort();
  for (final key in keys) {
    final point = positions[key]!;
    final cell = _earthCell(point);
    final candidates = <int>{};
    for (var x = -1; x <= 1; x++) {
      for (var y = -1; y <= 1; y++) {
        for (var z = -1; z <= 1; z++) {
          candidates.addAll(
            cells[(cell.$1 + x, cell.$2 + y, cell.$3 + z)] ?? const [],
          );
        }
      }
    }
    final ordered = candidates.toList()..sort();
    int? match;
    for (final index in ordered) {
      // Complete-link grouping prevents A-B-C chains from spreading a whole
      // street when only neighbouring pairs are within eight metres.
      if (groups[index].every((other) => distance(point, positions[other]!) <= 8)) {
        match = index;
        break;
      }
    }
    if (match == null) {
      (cells[cell] ??= []).add(groups.length);
      groups.add([key]);
    } else {
      groups[match].add(key);
    }
  }
  final result = <String, Offset>{};
  for (final keys in groups) {
    if (keys.length < 2) {
      continue;
    }
    final projected = {
      for (final key in keys) key: project?.call(positions[key]!) ?? Offset.zero,
    };
    if (worldWidth > 0) {
      final anchor = projected[keys.first]!;
      for (final key in keys) {
        final value = projected[key]!;
        final worlds = ((value.dx - anchor.dx) / worldWidth).round();
        projected[key] = Offset(value.dx - worlds * worldWidth, value.dy);
      }
    }
    final center =
        projected.values.reduce((a, b) => a + b) / keys.length.toDouble();
    var placed = 0;
    var ring = 1;
    while (placed < keys.length) {
      final count = math.min(keys.length - placed, 6 * ring);
      final radius = keys.length <= 6
          ? spacing / (2 * math.sin(math.pi / count))
          : spacing * ring;
      for (var i = 0; i < count; i++) {
        final angle = -math.pi / 2 + 2 * math.pi * i / count;
        result[keys[placed + i]] =
            center -
            projected[keys[placed + i]]! +
            Offset(radius * math.cos(angle), radius * math.sin(angle));
      }
      placed += count;
      ring++;
    }
  }
  return result;
}

// A 16 m cell safely contains the eight-metre neighbour search in the 27
// adjacent cells, allowing for the spherical/ellipsoidal Earth approximation.
(int, int, int) _earthCell(LatLng point) {
  const radius = 6371000.0;
  final lat = point.latitude * math.pi / 180;
  final lon = point.longitude * math.pi / 180;
  final horizontal = radius * math.cos(lat);
  return (
    (horizontal * math.cos(lon) / 16).floor(),
    (horizontal * math.sin(lon) / 16).floor(),
    (radius * math.sin(lat) / 16).floor(),
  );
}

/// flutter_map positions a marker at point - size/2 + size*alignment/2.
/// Moving the alignment moves the entire hit box, not only its painted child.
Alignment shiftedMarkerAlignment({
  required Alignment base,
  required Offset offset,
  required double width,
  required double height,
}) => Alignment(base.x + 2 * offset.dx / width, base.y + 2 * offset.dy / height);
