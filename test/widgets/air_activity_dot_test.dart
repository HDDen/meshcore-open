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
// change underneath; they read the phase from the first change rather than
// from the first frame, so a blink that starts a frame later still passes.
// The samples land on the blink's boundaries, where the dot has to be
// deterministic. The last test is the change: under another route the dot
// asks for no frames.

Widget _dot({required bool active}) => MaterialApp(
  home: Scaffold(body: Center(child: AirActivityDot(active: active))),
);

Color _color(WidgetTester tester) =>
    tester.widget<PulseDot>(find.byType(PulseDot)).color;

const Duration _half = Duration(milliseconds: 400);

/// The dot's colour now and after each of [count] further half-periods.
Future<List<Color>> _samples(WidgetTester tester, int count) async {
  final samples = [_color(tester)];
  for (var i = 0; i < count; i++) {
    await tester.pump(_half);
    samples.add(_color(tester));
  }
  return samples;
}

/// A blink: the colour changes within two half-periods and then alternates
/// at every one, blue among the colours.
void _expectBlinking(List<Color> samples) {
  final firstChange = samples.indexWhere((color) => color != samples.first);
  expect(firstChange, inInclusiveRange(1, 2), reason: '$samples');
  for (var i = firstChange + 1; i < samples.length; i++) {
    expect(samples[i], isNot(samples[i - 1]), reason: '$samples');
  }
  expect(samples, contains(MeshPalette.blue));
}

void main() {
  testWidgets('an active dot blinks blue and out every 400 ms', (
    tester,
  ) async {
    await tester.pumpWidget(_dot(active: true));
    expect(_color(tester), MeshPalette.blue);

    _expectBlinking(await _samples(tester, 6));
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

    _expectBlinking(await _samples(tester, 6));
  });

  testWidgets('under another route the dot asks for no frames, and blinks '
      'again once the route is gone', (tester) async {
    await tester.pumpWidget(_dot(active: true));
    await tester.pump(_half);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('over'))),
      ),
    );
    // The route settles once its transition ends; a blink that kept asking
    // for frames under it would never let it.
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(_half);
    await tester.pump(_half);
    expect(tester.binding.hasScheduledFrame, isFalse);

    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    _expectBlinking(await _samples(tester, 6));
  });
}
