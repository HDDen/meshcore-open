import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:meshcore_open/widgets/coincident_repeater_marker_layer.dart';

void main() {
  for (final nearCoordinates in [false, true]) {
    testWidgets('near=$nearCoordinates: all repeaters have independent taps at high zoom', (tester) async {
      final controller = MapController();
      const point = LatLng(45, 39);
      final selected = <String>[];
      final markers = [
        for (final id in ['a', 'b', 'c'])
          Marker(
            key: ValueKey('node:$id'),
            point: nearCoordinates
                ? const Distance().offset(point, ['a', 'b', 'c'].indexOf(id) * 3.0, 90)
                : point,
            width: 40, height: 40,
            child: GestureDetector(
              key: ValueKey('tap:$id'),
              behavior: HitTestBehavior.opaque,
              onTap: () => selected.add(id),
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
        Marker(
          key: const ValueKey('label:a'), point: point,
          width: 120, height: 24, alignment: Alignment.topCenter,
          child: const IgnorePointer(child: Text('A')),
        ),
        Marker(
          key: const ValueKey('node:chat'), point: point,
          child: const IgnorePointer(child: Text('chat')),
        ),
      ];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FlutterMap(
        mapController: controller,
        options: const MapOptions(initialCenter: point, initialZoom: 14.9, maxZoom: 18),
        children: [CoincidentRepeaterMarkerLayer(
          markers: markers, repeaterKeys: const {'a', 'b', 'c'}, maxZoom: 18,
        )],
      ))));
      await tester.pump();
      Marker marker(String key) => tester.widget<MarkerLayer>(find.byType(MarkerLayer))
          .markers.singleWhere((m) => m.key == ValueKey(key));
      expect(marker('node:a'), same(markers[0]));
      for (final zoom in [15.0, 18.0]) {
        controller.move(point, zoom);
        await tester.pump();
        for (final id in ['a', 'b', 'c']) {
          await tester.tap(find.byKey(ValueKey('tap:$id')));
          await tester.pump();
          expect(selected.last, id);
          expect(marker('node:$id').point,
              markers.singleWhere((m) => m.key == ValueKey('node:$id')).point);
        }
        final firstCenter = tester.getCenter(find.byKey(const ValueKey('tap:a')));
        final secondCenter = tester.getCenter(find.byKey(const ValueKey('tap:b')));
        expect((firstCenter - secondCenter).distance, closeTo(42, 0.01));
        expect(marker('node:a').child, same(markers[0].child));
        final node = marker('node:a');
        final label = marker('label:a');
        expect(label.alignment!.x * label.width / 2,
            closeTo(node.alignment!.x * node.width / 2, 0.001));
        expect((label.alignment!.y + 1) * label.height / 2,
            closeTo(node.alignment!.y * node.height / 2, 0.001));
        expect(marker('node:chat'), same(markers.last));
      }
      expect(selected, ['a', 'b', 'c', 'a', 'b', 'c']);
      controller.move(point, 14.9);
      await tester.pump();
      expect(marker('node:a'), same(markers[0]));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }
}
