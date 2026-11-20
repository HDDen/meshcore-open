import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/link_handler.dart';
import 'package:meshcore_open/helpers/mcoa_theme_options.dart';
import 'package:meshcore_open/helpers/signal_reading_text.dart';
import 'package:meshcore_open/models/custom_theme.dart';
import 'package:meshcore_open/theme/mcoa_theme_style.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';
import 'package:meshcore_open/widgets/formatted_message_text.dart';

Iterable<TextSpan> _spans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _spans(child);
    }
  }
}

void main() {
  testWidgets('message links and underlines follow direction and refresh cached spans', (tester) async {
    Widget app(Color incoming, Color outgoing) => MaterialApp(
      themeAnimationStyle: AnimationStyle.noAnimation,
      theme: MeshTheme.fromCustom(CustomTheme(
        id: 'custom:links',
        name: 'Links',
        background: Colors.white,
        accent: Colors.blue,
        mcoa: McoaThemeOptions(colors: {
          'incoming_link': incoming,
          'outgoing_link': outgoing,
        }),
      )),
      home: Scaffold(body: Column(children: [
        for (final outgoing in [false, true])
          McoaMessageScope(
            outgoing: outgoing,
            child: FormattedMessageText(
              key: ValueKey('body-$outgoing'),
              text: 'First line\nhttps://localhost',
              style: const TextStyle(color: Colors.black),
              textScale: 1,
              simplified: false,
            ),
          ),
      ])),
    );
    await tester.pumpWidget(app(Colors.red, Colors.green));
    final initialState = tester.state(find.byKey(const ValueKey('body-false')));
    for (final palette in [
      [Colors.red, Colors.green],
      [Colors.purple, Colors.blue],
    ]) {
      await tester.pumpWidget(app(palette[0], palette[1]));
      await tester.pump();
      for (final outgoing in [false, true]) {
        final root = find.byKey(ValueKey('body-$outgoing'));
        final rich = tester.widget<RichText>(find.descendant(
          of: root, matching: find.byType(RichText),
        ));
        final link = _spans(rich.text).singleWhere((span) => span.text == 'https://localhost');
        final color = palette[outgoing ? 1 : 0];
        expect(link.style!.color, color);
        expect(link.style!.decorationColor, color);
        expect(link.style!.decoration, TextDecoration.underline);
      }
    }
    expect(tester.state(find.byKey(const ValueKey('body-false'))), same(initialState));
    final context = tester.element(find.byType(Scaffold));
    expect(LinkHandler.configuredLinkColor(context), isNull);
    expect(LinkHandler.defaultLinkStyle(context, const TextStyle()).color,
        const Color(0xFFE65100));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('signal override changes only colors, preserving readings and spacing', () {
    final original = signalReadingSpans(
      snr: 4.8, rssi: -89, spreadingFactor: 7, afterHopList: true,
    ).cast<TextSpan>();
    final overridden = signalReadingSpans(
      snr: 4.8, rssi: -89, spreadingFactor: 7, afterHopList: true,
      colorOverride: Colors.purple,
    ).cast<TextSpan>();
    expect(overridden.map((span) => span.text), original.map((span) => span.text));
    expect(overridden.map((span) => span.style!.color), everyElement(Colors.purple));
    expect(signalReadingSpans(
      snr: null, rssi: null, spreadingFactor: null, afterHopList: false,
      colorOverride: Colors.purple,
    ), isEmpty);
  });
}
