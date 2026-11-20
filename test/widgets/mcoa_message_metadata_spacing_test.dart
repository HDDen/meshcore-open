import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoa_theme_options.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/custom_theme.dart';
import 'package:meshcore_open/screens/chat_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/mcoa_message_metadata_spacing.dart';
import 'package:meshcore_open/widgets/mcoa_bubble_surface.dart';
import 'package:meshcore_open/widgets/mcoa_theme_editor.dart';
import 'package:meshcore_open/widgets/mcoa_theme_preview.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const baseTheme = CustomTheme(
    id: 'spacing', name: 'Spacing',
    background: Color(0xFF17112A), accent: Color(0xFFA855F7),
  );

  testWidgets('incoming gap has two equal halves without widening chat bubbles', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    final settings = AppSettingsService();
    addTearDown(settings.dispose);
    final before = settings.settings.toJson();

    Widget app(int spacing, {
      bool separate = false, bool separateOutgoing = false,
      int incomingPadding = 0, int outgoingPadding = 0,
      Map<String, Color> colors = const {},
    }) => ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: SingleChildScrollView(
          child: McoaThemePreview(
            theme: baseTheme.copyWith(mcoa: McoaThemeOptions(incomingMetadataSpacing: spacing, separateIncomingMetadata: separate,
              separateOutgoingMetadata: separateOutgoing, incomingMetadataTopPadding: incomingPadding,
              outgoingMetadataTopPadding: outgoingPadding, colors: colors)),
            openedAt: DateTime(2026, 11, 20),
          ),
        )),
      ),
    );
    Finder body(bool outgoing) => find.byKey(ValueKey(
      outgoing ? 'theme-preview-outgoing-body' : 'theme-preview-incoming-body',
    ));
    double gap(bool outgoing) => tester.getTopLeft(find.byType(RouteChip).at(outgoing ? 1 : 0)).dy
        - tester.getBottomLeft(body(outgoing)).dy;
    void expectHalves(double total) {
      expect(find.byType(McoaMessageMetadataSpacing), findsOneWidget);
      final top = find.byKey(const ValueKey('mcoa-metadata-spacing-top'));
      final bottom = find.byKey(const ValueKey('mcoa-metadata-spacing-bottom'));
      expect(tester.getSize(top).height, total / 2);
      expect(tester.getSize(bottom).height, total / 2);
      expect(tester.getBottomLeft(top).dy, tester.getTopLeft(bottom).dy);
    }

    await tester.pumpWidget(app(0, incomingPadding: 9, outgoingPadding: 13));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(McoaMessageMetadataSpacing), findsNothing);
    final incomingGap = gap(false);
    final outgoingGap = gap(true);
    final incomingWidth = tester.getSize(body(false)).width;
    await tester.pumpWidget(app(21));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectHalves(21);
    expect(gap(false), closeTo(incomingGap + 21, 0.01));
    expect(gap(true), closeTo(outgoingGap, 0.01));
    expect(tester.getSize(body(false)).width, incomingWidth);

    // Splitting uses the real incoming bubble; outgoing keeps its original box.
    await tester.pumpWidget(app(21, separate: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(McoaBubbleSurface), findsOneWidget);
    final split = tester.renderObject<RenderMcoaBubbleSurface>(find.byType(McoaBubbleSurface));
    final lowerHalf = find.byKey(const ValueKey('mcoa-metadata-spacing-bottom'));
    final lowerBottom = tester.getBottomLeft(lowerHalf).dy - tester.getTopLeft(find.byType(McoaBubbleSurface)).dy;
    expect(split.messageRect.bottom, closeTo(lowerBottom + 8, 0.01));
    expect(split.metadataRect.height, greaterThan(0));
    expect(split.metadataRect.width, split.messageRect.width);
    expect(tester.getSize(body(false)).width, incomingWidth);
    expect(gap(true), closeTo(outgoingGap, 0.01));
    final messageHeight = split.messageRect.height;
    final metadataHeight = split.metadataRect.height;
    final width = split.size.width;
    await tester.pumpWidget(app(21, separate: true, incomingPadding: 9, colors: const {
      'incoming_metadata_background': Color(0xFF123456),
    }));
    await tester.pumpAndSettle();
    final padded = tester.renderObject<RenderMcoaBubbleSurface>(find.byType(McoaBubbleSurface));
    expect(padded.messageRect.height, messageHeight);
    expect(padded.metadataRect.height, closeTo(metadataHeight + 9, 0.01));
    expect(padded.size.width, width);
    expect(tester.getSize(find.byKey(const ValueKey('mcoa-metadata-top-padding'))).height, 9);
    expect(tester.widget<McoaBubbleSurface>(find.byType(McoaBubbleSurface)).metadataColor, const Color(0xFF123456));
    await tester.pumpWidget(app(21, separate: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('theme-preview-tab-1')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectHalves(21);
    expect(find.byType(McoaBubbleSurface), findsOneWidget);
    await tester.pumpWidget(app(0, separate: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectHalves(0);
    expect(find.byType(McoaBubbleSurface), findsOneWidget);
    await tester.pumpWidget(app(0, incomingPadding: 9, outgoingPadding: 13));
    await tester.pumpAndSettle();
    expect(find.byType(McoaBubbleSurface), findsNothing);
    expect(find.byType(McoaMessageMetadataSpacing), findsNothing);
    await tester.pumpWidget(app(0, separateOutgoing: true));
    await tester.pumpAndSettle();
    for (final tab in [0, 1]) {
      final target = find.byKey(ValueKey('theme-preview-tab-$tab'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(McoaBubbleSurface), findsOneWidget);
      final surface = find.byType(McoaBubbleSurface);
      final originalSurface = tester.renderObject<RenderMcoaBubbleSurface>(surface);
      final originalMessageHeight = originalSurface.messageRect.height;
      final originalMetadataHeight = originalSurface.metadataRect.height;
      final originalWidth = originalSurface.size.width;
      if (tab == 0) {
        expect(find.descendant(of: surface, matching: body(true)), findsOneWidget);
        expect(find.descendant(of: surface, matching: body(false)), findsNothing);
      } else {
        // Direct samples use production ContactMessageBubble, without the
        // channel-only preview body keys.
        final owner = find.ancestor(of: surface, matching: find.byType(ContactMessageBubble));
        expect(owner, findsOneWidget);
        expect(tester.widget<ContactMessageBubble>(owner).message.isOutgoing, isTrue);
      }
      await tester.pumpWidget(app(0, separateOutgoing: true, outgoingPadding: 13, colors: const {
        'outgoing_metadata_background': Color(0xFF654321),
      }));
      await tester.pumpAndSettle();
      final paddedOutgoing = tester.renderObject<RenderMcoaBubbleSurface>(surface);
      expect(paddedOutgoing.messageRect.height, originalMessageHeight);
      expect(paddedOutgoing.metadataRect.height, closeTo(originalMetadataHeight + 13, 0.01));
      expect(paddedOutgoing.size.width, originalWidth);
      expect(tester.widget<McoaBubbleSurface>(surface).metadataColor, const Color(0xFF654321));
      await tester.pumpWidget(app(0, separateOutgoing: true));
      await tester.pumpAndSettle();
    }
    expect(settings.settings.toJson(), before);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('incoming spacing slider updates the draft only', (tester) async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    final settings = AppSettingsService();
    addTearDown(settings.dispose);
    final before = settings.settings.toJson();
    var options = const McoaThemeOptions();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: SingleChildScrollView(child: StatefulBuilder(
          builder: (context, update) => McoaThemeEditor(
            theme: baseTheme.copyWith(mcoa: options),
            onChanged: (value) => update(() { options = value; }),
          ),
        ))),
      ),
    ));
    final toggle = find.byKey(const ValueKey('theme-section-mcoa-incoming-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final slider = find.descendant(
      of: find.byKey(const ValueKey('mcoa-incoming-metadata-spacing')),
      matching: find.byType(Slider),
    );
    await tester.ensureVisible(slider);
    final control = tester.widget<Slider>(slider);
    expect(control.min, 0);
    expect(control.max, 40);
    expect(control.value, 0);
    control.onChanged!(21);
    await tester.pump();
    expect(options.incomingMetadataSpacing, 21);
    final toggleMetadata = find.byKey(const ValueKey('mcoa-separate-incoming-metadata'));
    Finder paddingSlider(String direction) => find.descendant(
      of: find.byKey(ValueKey('mcoa-$direction-metadata-top-padding')),
      matching: find.byType(Slider),
    );
    expect(tester.widget<Slider>(paddingSlider('incoming')).onChanged, isNull);
    expect(tester.widget<SwitchListTile>(toggleMetadata).value, isFalse);
    tester.widget<SwitchListTile>(toggleMetadata).onChanged!(true);
    await tester.pump();
    expect(options.separateIncomingMetadata, isTrue);
    final incomingPadding = tester.widget<Slider>(paddingSlider('incoming'));
    expect(incomingPadding.min, 0);
    expect(incomingPadding.max, 40);
    incomingPadding.onChanged!(7);
    await tester.pump();
    expect(options.incomingMetadataTopPadding, 7);
    final outgoingSection = find.byKey(const ValueKey('theme-section-mcoa-outgoing-toggle'));
    await tester.ensureVisible(outgoingSection);
    await tester.tap(outgoingSection);
    await tester.pumpAndSettle();
    final outgoingToggle = find.byKey(const ValueKey('mcoa-separate-outgoing-metadata'));
    expect(tester.widget<Slider>(paddingSlider('outgoing')).onChanged, isNull);
    expect(tester.widget<SwitchListTile>(outgoingToggle).value, isFalse);
    tester.widget<SwitchListTile>(outgoingToggle).onChanged!(true);
    await tester.pump();
    expect(options.separateOutgoingMetadata, isTrue);
    tester.widget<Slider>(paddingSlider('outgoing')).onChanged!(15);
    await tester.pump();
    expect(options.outgoingMetadataTopPadding, 15);
    expect(options.incomingMetadataTopPadding, 7);
    expect(options.separateIncomingMetadata, isTrue);
    tester.widget<SwitchListTile>(toggleMetadata).onChanged!(false);
    await tester.pump();
    expect(options.separateIncomingMetadata, isFalse);
    expect(options.incomingMetadataTopPadding, 7);
    expect(tester.widget<Slider>(paddingSlider('incoming')).onChanged, isNull);
    expect(tester.widget<Slider>(paddingSlider('outgoing')).onChanged, isNotNull);
    expect(options.separateOutgoingMetadata, isTrue);

    expect(tester.widget<Slider>(slider).value, 21);
    expect(settings.settings.toJson(), before);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
