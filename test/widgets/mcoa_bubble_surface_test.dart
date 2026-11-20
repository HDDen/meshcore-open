import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoa_theme_options.dart';
import 'package:meshcore_open/theme/mcoa_theme_style.dart';
import 'package:meshcore_open/widgets/chat_bubble_box.dart';
import 'package:meshcore_open/widgets/mcoa_bubble_surface.dart';
import 'package:meshcore_open/widgets/mcoa_chat_bubble_box.dart';
import 'package:meshcore_open/widgets/mcoa_message_metadata_spacing.dart';

void main() {
  testWidgets('metadata backing extends behind rounded messages in both directions', (tester) async {
    const radius = BorderRadius.all(Radius.circular(16));
    for (final outgoing in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        theme: McoaThemeStyle.apply(ThemeData.dark(), const McoaThemeOptions(
          separateIncomingMetadata: true,
          separateOutgoingMetadata: true,
          colors: {
            'incoming_metadata_background': Colors.red,
            'outgoing_metadata_background': Colors.blue,
          },
        )),
        home: Scaffold(body: Align(
          alignment: Alignment.topLeft,
          child: McoaChatBubbleBox(
            outgoing: outgoing,
            duration: const Duration(milliseconds: 100),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: radius),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 100, height: 40),
                McoaMessageMetadataSpacing(height: 10, messageBottomPadding: 8),
                SizedBox(width: 100, height: 30),
              ],
            ),
          ),
        )),
      ));
      await tester.pumpAndSettle();
      final surface = tester.renderObject<RenderMcoaBubbleSurface>(find.byType(McoaBubbleSurface));
      expect(surface.messageRect.height, 58);
      expect(surface.metadataRect.height, 30);
      expect(surface, paints
        ..rrect(
          rrect: radius.toRRect(Offset.zero & surface.size),
          color: outgoing ? Colors.blue : Colors.red,
        )
        ..rrect(rrect: radius.toRRect(surface.messageRect), color: Colors.white));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('separation preserves natural and intrinsic widths, padding and hit tests', (tester) async {
    const decoration = BoxDecoration(
      color: Colors.white,
      border: Border.fromBorderSide(BorderSide()),
      borderRadius: BorderRadius.all(Radius.circular(16)),
    );
    var taps = 0;
    Widget app({bool enabled = false, bool outgoingEnabled = false, bool outgoing = false, bool visible = true}) => MaterialApp(
      theme: McoaThemeStyle.apply(ThemeData.dark(), McoaThemeOptions(
        separateIncomingMetadata: enabled, separateOutgoingMetadata: outgoingEnabled,
      )),
      home: Scaffold(body: Align(
        alignment: Alignment.topLeft,
        child: McoaChatBubbleBox(
          outgoing: outgoing, metadataVisible: visible,
          duration: const Duration(milliseconds: 100),
          constraints: const BoxConstraints(maxWidth: 250),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: decoration,
          child: IntrinsicWidth(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                key: const ValueKey('body-tap-target'),
                behavior: HitTestBehavior.opaque,
                onTap: () { taps++; },
                child: const SizedBox(key: ValueKey('body'), width: 80, height: 40),
              ),
              McoaMessageMetadataSpacing(height: 10, messageBottomPadding: enabled ? 8 : 0),
              const SizedBox(key: ValueKey('metadata'), width: 120, height: 30),
            ],
          )),
        ),
      )),
    );
    await tester.pumpWidget(app());
    final baselineWidth = tester.getSize(find.byType(McoaChatBubbleBox)).width;
    final bodyOrigin = tester.getTopLeft(find.byKey(const ValueKey('body')));
    expect(find.byType(ChatBubbleBox), findsOneWidget);
    expect(find.byType(McoaBubbleSurface), findsNothing);
    await tester.tap(find.byKey(const ValueKey('body-tap-target')));
    expect(taps, 1);
    await tester.pumpWidget(app(enabled: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(McoaChatBubbleBox)).width, baselineWidth);
    expect(tester.getTopLeft(find.byKey(const ValueKey('body'))), bodyOrigin);
    final surface = tester.renderObject<RenderMcoaBubbleSurface>(find.byType(McoaBubbleSurface));
    expect(surface.messageRect.bottom, 9 + 40 + 10 + 8);
    expect(surface.metadataRect.top, surface.messageRect.bottom);
    expect(surface.metadataRect.height, 30 + 9);
    expect(surface.metadataRect.width, baselineWidth);
    expect(tester.widget<McoaBubbleSurface>(find.byType(McoaBubbleSurface)).decoration, decoration);
    await tester.tap(find.byKey(const ValueKey('body-tap-target')));
    expect(taps, 2);
    await tester.pumpWidget(app(outgoingEnabled: true, outgoing: true));
    await tester.pumpAndSettle();
    expect(find.byType(McoaBubbleSurface), findsOneWidget);
    expect(tester.getSize(find.byType(McoaChatBubbleBox)).width, baselineWidth);
    await tester.tap(find.byKey(const ValueKey('body-tap-target')));
    expect(taps, 3);
    await tester.pumpWidget(app(outgoingEnabled: true));
    await tester.pumpAndSettle();
    expect(find.byType(McoaBubbleSurface), findsNothing);
    for (final outgoing in [true, false]) {
      await tester.pumpWidget(app(enabled: true, outgoing: outgoing, visible: outgoing));
      await tester.pumpAndSettle();
      expect(find.byType(McoaBubbleSurface), findsNothing);
      expect(find.byType(ChatBubbleBox), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
