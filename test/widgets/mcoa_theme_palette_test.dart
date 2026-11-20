import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoa_theme_options.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/channel_widget_color_picker.dart';
import 'package:meshcore_open/widgets/mcoa_theme_palette.dart';

void main() {
  testWidgets('shared HSV palette and HEX stay synchronized and preserve alpha', (tester) async {
    var selected = const Color(0x80FF0000);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: Center(child: AlertDialog(content: SizedBox(
        width: 300,
        child: StatefulBuilder(builder: (context, setState) => McoaThemePalette(
          color: selected,
          onChanged: (color) => setState(() {
            selected = color;
          }),
        )),
      )))),
    ));
    final palette = find.byType(ChannelColorPalette);
    final gestures = find.descendant(of: palette, matching: find.byType(GestureDetector));
    expect(gestures, findsNWidgets(2));
    final square = tester.getRect(gestures.first);
    await tester.tapAt(square.topLeft + Offset(square.width / 2, square.height / 2));
    await tester.pump();
    expect(selected.a, const Color(0x80FF0000).a);
    expect(selected, isNot(const Color(0x80FF0000)));
    final hue = tester.getRect(gestures.last);
    await tester.tapAt(hue.topLeft + Offset(hue.width / 2, hue.height / 2));
    await tester.pump();
    expect(HSVColor.fromColor(selected).hue, closeTo(180, 2));
    expect(selected.a, const Color(0x80FF0000).a);
    final hex = find.byType(TextField);
    expect(tester.widget<TextField>(hex).controller!.text, McoaThemeOptions.hex(selected));
    await tester.enterText(hex, '#123456');
    await tester.pump();
    expect(selected, const Color(0xFF123456));
    expect(tester.widget<ChannelColorPalette>(palette).color, selected);
    expect(tester.widget<TextField>(hex).controller!.text, '#123456');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
