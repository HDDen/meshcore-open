import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';
import 'package:meshcore_open/widgets/radio_stats_entry.dart';

// What the air-activity dot promises, pinned before its blinking moves off a
// timer. Active, it blinks with a 400 ms half-period, blue then the outline
// colour; inactive, it stays the outline colour and never changes; becoming
// inactive stops the blink at once, becoming active starts it. The tests read
// the colour the dot hands its [PulseDot], so what drives the blink can
// change underneath.

Widget _dot({required bool active}) => MaterialApp(
  home: Scaffold(body: Center(child: AirActivityDot(active: active))),
);

Color _color(WidgetTester tester) =>
    tester.widget<PulseDot>(find.byType(PulseDot)).color;

const Duration _half = Duration(milliseconds: 400);

void main() {
  testWidgets('an active dot blinks blue and out every 400 ms', (
    tester,
  ) async {
    await tester.pumpWidget(_dot(active: true));
    expect(_color(tester), MeshPalette.blue);

    await tester.pump(_half);
    expect(_color(tester), isNot(MeshPalette.blue));

    await tester.pump(_half);
    expect(_color(tester), MeshPalette.blue);

    await tester.pump(_half);
    expect(_color(tester), isNot(MeshPalette.blue));
  });

  testWidgets('an inactive dot rests on the outline colour', (tester) async {
    await tester.pumpWidget(_dot(active: false));
    final rest = _color(tester);
    expect(rest, isNot(MeshPalette.blue));

    await tester.pump(_half);
    await tester.pump(_half);
    expect(_color(tester), rest);
  });

  testWidgets('becoming inactive stops the blink at once', (tester) async {
    await tester.pumpWidget(_dot(active: true));
    await tester.pump(_half);
    expect(_color(tester), isNot(MeshPalette.blue));

    await tester.pumpWidget(_dot(active: false));
    final rest = _color(tester);
    expect(rest, isNot(MeshPalette.blue));

    await tester.pump(_half);
    await tester.pump(_half);
    expect(_color(tester), rest);
  });

  testWidgets('becoming active starts the blink', (tester) async {
    await tester.pumpWidget(_dot(active: false));
    await tester.pump(_half);

    await tester.pumpWidget(_dot(active: true));
    expect(_color(tester), MeshPalette.blue);

    await tester.pump(_half);
    expect(_color(tester), isNot(MeshPalette.blue));

    await tester.pump(_half);
    expect(_color(tester), MeshPalette.blue);
  });
}
