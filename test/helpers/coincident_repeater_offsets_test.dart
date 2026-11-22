import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:meshcore_open/helpers/coincident_repeater_offsets.dart';

void main() {
  const point = LatLng(45, 39);

  test('only the four highest zoom levels spread identical coordinates', () {
    final positions = {'b': point, 'a': point, 'alone': const LatLng(46, 39)};
    expect(coincidentRepeaterOffsets(positions, zoom: 14.999, maxZoom: 18), isEmpty);
    for (final zoom in [15.0, 16.0, 17.0, 18.0]) {
      final offsets = coincidentRepeaterOffsets(positions, zoom: zoom, maxZoom: 18);
      expect(offsets.keys, unorderedEquals(['a', 'b']));
      expect((offsets['a']! - offsets['b']!).distance, closeTo(42, 0.001));
    }
    expect(positions['a'], point);
    expect(positions['b'], point);
  });

  test('three repeaters nearly touch and retain stable public key order', () {
    final first = coincidentRepeaterOffsets(
      {'c': point, 'a': point, 'b': point}, zoom: 18, maxZoom: 18,
    );
    final second = coincidentRepeaterOffsets(
      {'b': point, 'c': point, 'a': point}, zoom: 18, maxZoom: 18,
    );
    expect(first, second);
    for (final a in first.keys) {
      for (final b in first.keys.where((key) => key != a)) {
        expect((first[a]! - first[b]!).distance, closeTo(42, 0.001));
      }
    }
  });

  test('coordinates outside eight metres stay in independent groups', () {
    final offsets = coincidentRepeaterOffsets({
      'a': point, 'b': point,
      'c': const LatLng(45.001, 39), 'd': const LatLng(45.001, 39),
      'near': const LatLng(45.0001, 39),
    }, zoom: 18, maxZoom: 18);
    expect(offsets.containsKey('near'), isFalse);
    expect(offsets['a'], offsets['c']);
    expect(offsets['b'], offsets['d']);
  });

  test('eight metre threshold groups near points but excludes distant ones', () {
    const distance = Distance(roundResult: false);
    final near = distance.offset(point, 7.9, 90);
    final outside = distance.offset(point, 8.1, 270);
    expect(distance(point, near), lessThan(8));
    expect(distance(point, outside), greaterThan(8));
    final positions = {'a': point, 'b': near, 'c': outside};
    final offsets = coincidentRepeaterOffsets(positions, zoom: 18, maxZoom: 18);
    expect(offsets.keys, unorderedEquals(['a', 'b']));
    expect(positions['b'], near);
  });

  test('neighbour chains do not create groups wider than eight metres', () {
    const distance = Distance(roundResult: false);
    final positions = {
      'a': point,
      'b': distance.offset(point, 6, 90),
      'c': distance.offset(point, 12, 90),
    };
    final first = coincidentRepeaterOffsets(positions, zoom: 18, maxZoom: 18);
    final reverse = coincidentRepeaterOffsets(
      Map.fromEntries(positions.entries.toList().reversed), zoom: 18, maxZoom: 18,
    );
    expect(first.keys, unorderedEquals(['a', 'b']));
    expect(first, reverse);
  });

  test('projection removes original point differences from visual spacing', () {
    const distance = Distance(roundResult: false);
    final near = distance.offset(point, 7, 90);
    final pixels = {'a': const Offset(100, 100), 'b': const Offset(120, 100)};
    final offsets = coincidentRepeaterOffsets(
      {'a': point, 'b': near}, zoom: 18, maxZoom: 18,
      project: (p) => p == point ? pixels['a']! : pixels['b']!,
    );
    final a = pixels['a']! + offsets['a']!;
    final b = pixels['b']! + offsets['b']!;
    expect((a - b).distance, closeTo(42, 0.001));
    expect((a + b) / 2, const Offset(110, 100));
  });

  test('projection uses the nearest world across the date line', () {
    const a = LatLng(0, 179.99999);
    const b = LatLng(0, -179.99999);
    final offsets = coincidentRepeaterOffsets(
      {'a': a, 'b': b}, zoom: 18, maxZoom: 18, worldWidth: 1000,
      project: (p) => Offset(p == a ? 999 : 1, 100),
    );
    expect(offsets['a']!.distance, lessThan(23));
    expect(offsets['b']!.distance, lessThan(23));
  });

  test('spatial grouping also works across the date line and near the poles', () {
    for (final origin in [const LatLng(0, 179.99999), const LatLng(89.99999, 39)]) {
      const distance = Distance(roundResult: false);
      final near = distance.offset(origin, 5, 90);
      expect(coincidentRepeaterOffsets(
        {'a': origin, 'b': near}, zoom: 18, maxZoom: 18,
      ).keys, unorderedEquals(['a', 'b']));
    }
  });

  test('larger groups stay compact without overlapping marker centers', () {
    final offsets = coincidentRepeaterOffsets({
      for (var i = 0; i < 18; i++) 'key$i': point,
    }, zoom: 18, maxZoom: 18);
    expect(offsets, hasLength(18));
    for (final a in offsets.keys) {
      expect(offsets[a]!.distance, lessThanOrEqualTo(84.001));
      for (final b in offsets.keys.where((key) => key != a)) {
        expect((offsets[a]! - offsets[b]!).distance, greaterThanOrEqualTo(41.999));
      }
    }
  });

  test('marker and top anchored label receive the same pixel translation', () {
    const offset = Offset(21, -35);
    for (final dimensions in [(40.0, 40.0, Alignment.center),
                              (120.0, 24.0, Alignment.topCenter)]) {
      final (width, height, base) = dimensions;
      final shifted = shiftedMarkerAlignment(
        base: base, offset: offset, width: width, height: height,
      );
      expect((shifted.x - base.x) * width / 2, closeTo(offset.dx, 0.001));
      expect((shifted.y - base.y) * height / 2, closeTo(offset.dy, 0.001));
    }
  });
}
