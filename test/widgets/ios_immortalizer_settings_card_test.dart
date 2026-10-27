import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/ios_immortalizer_power_options.dart';
import 'package:meshcore_open/widgets/ios_immortalizer_settings_card.dart';

Finder _control(String key, Type type) => find.descendant(
  of: find.byKey(ValueKey('ios-immortalizer-$key')), matching: find.byType(type),
);

void main() {
  for (final locale in ['ru', 'en']) {
    testWidgets('audio controls preserve values and sliders commit only on release ($locale)', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var options = const IosImmortalizerPowerOptions();
      final saved = <IosImmortalizerPowerOptions>[];
      await tester.pumpWidget(MaterialApp(
        locale: Locale(locale), supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: SingleChildScrollView(child: StatefulBuilder(
          builder: (context, setState) => IosImmortalizerSettingsCard(options: options,
            onChanged: (next) => setState(() { options = next; saved.add(next); })),
        ))),
      ));
      final bufferFinder = _control('buffer', Slider);
      final loopFinder = _control('loop', Slider);
      final l10n = AppLocalizations.of(tester.element(find.byType(IosImmortalizerSettingsCard)));
      var buffer = tester.widget<Slider>(bufferFinder);
      expect([buffer.min, buffer.max, buffer.divisions, buffer.value], [0, 200, 20, 0]);
      expect(buffer.label, l10n.powerSaving_iosImmortalizerSystem);
      final loop = tester.widget<Slider>(loopFinder);
      expect([loop.min, loop.max, loop.divisions, loop.value], [1, 10, 9, 1]);

      await tester.ensureVisible(bufferFinder);
      final rect = tester.getRect(bufferFinder);
      final drag = await tester.startGesture(Offset(rect.left + 24, rect.center.dy));
      await drag.moveBy(Offset(rect.width / 2, 0));
      await tester.pump();
      expect(saved, isEmpty);
      await drag.up();
      await tester.pumpAndSettle();
      expect(saved.length, 1);
      expect(options.audioBufferMilliseconds, greaterThan(0));
      expect(options.audioBufferMilliseconds % 10, 0);
      final remembered = options.audioBufferMilliseconds;
      final mode = find.byKey(const ValueKey('ios-immortalizer-audio-mode'));
      await tester.ensureVisible(mode);
      await tester.tap(mode);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.powerSaving_iosImmortalizerWithoutAudio).last);
      await tester.pumpAndSettle();
      expect(options.withoutAudio, isTrue);
      buffer = tester.widget<Slider>(bufferFinder);
      expect(buffer.onChanged, isNull);
      expect(tester.widget<Slider>(loopFinder).onChanged, isNull);
      expect(tester.widget<DropdownButton<bool>>(
        find.byKey(const ValueKey('ios-immortalizer-sample-rate'))).onChanged, isNull);
      expect(tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('ios-immortalizer-pause-frames'))).onChanged, isNotNull);
      expect(options.audioBufferMilliseconds, remembered);
      await tester.tap(mode);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.powerSaving_iosImmortalizerOriginal).last);
      await tester.pumpAndSettle();
      expect(options.audioBufferMilliseconds, remembered);
      expect(tester.widget<Slider>(bufferFinder).onChanged, isNotNull);
      expect(tester.takeException(), isNull);
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

  testWidgets('a preset card is read-only including mode and both sliders', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SingleChildScrollView(
        child: IosImmortalizerSettingsCard(options: IosImmortalizerPowerOptions()),
      )),
    ));
    for (final tile in tester.widgetList<SwitchListTile>(find.byType(SwitchListTile))) {
      expect(tile.onChanged, isNull);
    }
    for (final dropdown in tester.widgetList<DropdownButton<bool>>(find.byType(DropdownButton<bool>))) {
      expect(dropdown.onChanged, isNull);
    }
    expect(tester.widget<Slider>(_control('buffer', Slider)).onChanged, isNull);
    expect(tester.widget<Slider>(_control('loop', Slider)).onChanged, isNull);
  });
}
