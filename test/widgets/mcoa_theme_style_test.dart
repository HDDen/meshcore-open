import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoa_theme_options.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/custom_theme.dart';
import 'package:meshcore_open/theme/mcoa_theme_style.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';
import 'package:meshcore_open/widgets/mention_chip.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';
import 'package:meshcore_open/widgets/reply_quote_box.dart';

void main() {
  testWidgets('name brightness changes colored names only and explicit ink wins', (tester) async {
    const fallback = Color(0xFF336699);
    const explicit = Color(0xFFAA55BB);
    Widget app(McoaThemeOptions options) => MaterialApp(
      themeAnimationStyle: AnimationStyle.noAnimation,
      theme: MeshTheme.fromCustom(CustomTheme(
        id: 'custom:name-brightness',
        name: 'Names',
        background: Colors.white,
        accent: Colors.blue,
        mcoa: options,
      )),
      home: Builder(builder: (context) => Column(children: [
        Text('colored', style: TextStyle(
          color: McoaThemeStyle.senderNameColor(context, fallback, colored: true),
        )),
        Text('monochrome', style: TextStyle(
          color: McoaThemeStyle.senderNameColor(context, fallback, colored: false),
        )),
      ])),
    );
    await tester.pumpWidget(app(const McoaThemeOptions(incomingSenderNameBrightness: 50)));
    expect(tester.widget<Text>(find.text('colored')).style!.color!.computeLuminance(),
        greaterThan(fallback.computeLuminance()));
    expect(tester.widget<Text>(find.text('monochrome')).style!.color, fallback);
    await tester.pumpWidget(app(const McoaThemeOptions(
      incomingSenderNameBrightness: 50,
      colors: {'incoming_sender_name': explicit},
    )));
    expect(tester.widget<Text>(find.text('colored')).style!.color, explicit);
    expect(tester.widget<Text>(find.text('monochrome')).style!.color, explicit);
    expect(tester.takeException(), isNull);
  });

  testWidgets('badge colors do not tint hop text; only hop text overrides do', (tester) async {
    Widget app(Color? hopText) => MaterialApp(
      themeAnimationStyle: AnimationStyle.noAnimation,
      theme: MeshTheme.fromCustom(CustomTheme(
        id: 'custom:hop-independence',
        name: 'Hops',
        background: Colors.white,
        accent: Colors.blue,
        mcoa: McoaThemeOptions(colors: {
          'incoming_badges': Colors.red,
          'outgoing_badges': Colors.orange,
          'incoming_hop_text': ?hopText,
          'outgoing_hop_text': ?hopText,
        }),
      )),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: Column(children: [
        for (final outgoing in [false, true])
          McoaMessageScope(
            outgoing: outgoing,
            child: RouteChip(key: ValueKey('hops-$outgoing'), isDirect: true, hops: 2),
          ),
      ])),
    );
    for (final color in <Color?>[null, Colors.green]) {
      await tester.pumpWidget(app(color));
      await tester.pump();
      for (final outgoing in [false, true]) {
        final root = find.byKey(ValueKey('hops-$outgoing'));
        final text = tester.widget<Text>(find.descendant(of: root, matching: find.byType(Text)));
        expect(text.style!.color,
            color ?? Theme.of(tester.element(root)).colorScheme.onSurfaceVariant);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('directional quote and mention colors use the enclosing message', (tester) async {
    const incoming = Color(0xFF114477);
    const outgoing = Color(0xFFAA2233);
    final theme = CustomTheme(
      id: 'custom:colors',
      name: 'Colors',
      background: Colors.white,
      accent: Colors.blue,
      mcoa: McoaThemeOptions(colors: {
        'status_bar': Colors.green,
        'header': Colors.black,
        'header_text': Colors.yellow,
        for (final direction in ['incoming', 'outgoing'])
          for (final part in ['mention_text', 'quote_text', 'mention_border',
              'quote_background', 'mention_background', 'hop_border', 'hop_background', 'hop_text'])
            '${direction}_$part': direction == 'incoming' ? incoming : outgoing,
      }),
    );
    final data = MeshTheme.fromCustom(theme);
    expect(data.appBarTheme.backgroundColor, Colors.black);
    expect(data.appBarTheme.foregroundColor, Colors.yellow);
    expect(data.appBarTheme.systemOverlayStyle!.statusBarColor, Colors.green);
    await tester.pumpWidget(MaterialApp(
      theme: data,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: Column(children: [
        for (final outgoing in [false, true])
          McoaMessageScope(
            outgoing: outgoing,
            child: Column(children: [
              for (final simplified in [false, true])
                MentionChip(
                  key: ValueKey('mention-$outgoing-$simplified'),
                  senderName: 'Alice',
                  textScale: 1,
                  simplified: simplified,
                  textStyle: const TextStyle(color: Colors.black),
                ),
              RouteChip(
                key: ValueKey('hops-$outgoing'),
                isDirect: true,
                hops: 2,
                foregroundColor: Colors.purple,
              ),
              ReplyQuoteBox(
                authorName: 'Alice',
                text: 'quote-$outgoing',
                textScale: 1,
              ),
            ]),
          ),
      ])),
    ));
    await tester.pump();
    for (final isOutgoing in [false, true]) {
      final expected = isOutgoing ? outgoing : incoming;
      final hops = find.byKey(ValueKey('hops-$isOutgoing'));
      final hopBox = tester.widget<Container>(find.descendant(
        of: hops, matching: find.byType(Container),
      )).decoration! as BoxDecoration;
      expect(hopBox.color, expected);
      expect((hopBox.border! as Border).top.color, expected);
      expect(tester.widget<Text>(find.descendant(
        of: hops, matching: find.byType(Text),
      )).style!.color, expected);
      for (final simplified in [false, true]) {
        final root = find.byKey(ValueKey('mention-$isOutgoing-$simplified'));
        final text = tester.widget<Text>(find.descendant(
          of: root, matching: find.text('@Alice'),
        ));
        expect(text.style!.color, simplified ? Colors.black : expected);
        final decoration = tester.widget<Container>(
          find.descendant(of: root, matching: find.byType(Container)),
        ).decoration;
        if (simplified) {
          expect(decoration, isNull);
        } else {
          final box = decoration! as BoxDecoration;
          expect(box.color, expected);
          expect((box.border! as Border).top.color, expected);
        }
      }
      expect(tester.widget<Text>(find.text('quote-$isOutgoing')).style!.color, expected);
    }
    expect(tester.takeException(), isNull);
  });
}
