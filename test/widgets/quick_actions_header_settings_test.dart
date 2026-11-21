import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/quick_actions_header_settings.dart';
import 'package:meshcore_open/screens/quick_actions_settings_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    // Desktop preference initialization can perform real path/file I/O.
    // Keep it outside the widget test's fake-async zone.
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  testWidgets('noise selector enables an independent fixed-step refresh setting', (tester) async {
    final service = AppSettingsService();
    addTearDown(service.dispose);
    final popupBefore = service.settings.quickActions.toJson();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: service,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const QuickActionsSettingsScreen(),
      ),
    ));
    final selector = find.byKey(const ValueKey('quick-actions-header-display'));
    await tester.scrollUntilVisible(
      selector,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(selector);
    await tester.pumpAndSettle();
    final dropdown = tester.widget<DropdownButton<QuickActionsHeaderDisplay>>(selector);
    expect(dropdown.items!.firstWhere((item) => item.value == QuickActionsHeaderDisplay.noise).enabled, isTrue);
    expect(dropdown.items!.firstWhere((item) => item.value == QuickActionsHeaderDisplay.extraHops).enabled, isFalse);
    expect(dropdown.value, QuickActionsHeaderDisplay.noise);
    final defaultInterval = find.byKey(const ValueKey('quick-actions-header-interval'));
    expect(tester.widget<Slider>(find.descendant(
      of: defaultInterval, matching: find.byType(Slider),
    )).value, 5);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Icon').last);
    await tester.pumpAndSettle();
    expect(defaultInterval, findsNothing);
    await tester.tap(selector);
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    await tester.tap(find.text('Noise level').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(service.settings.quickActionsHeader.display, QuickActionsHeaderDisplay.noise);
    final interval = find.byKey(const ValueKey('quick-actions-header-interval'));
    await tester.ensureVisible(interval);
    final slider = find.descendant(of: interval, matching: find.byType(Slider));
    expect(tester.widget<Slider>(slider).divisions, 6);
    for (var step = 0; step < QuickActionsHeaderSettings.allowedIntervalsMs.length; step++) {
      tester.widget<Slider>(slider).onChanged!(step.toDouble());
      await tester.pump();
      expect(service.settings.quickActionsHeader.intervalMsFor(QuickActionsHeaderDisplay.noise),
          QuickActionsHeaderSettings.allowedIntervalsMs[step]);
    }
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    await tester.tap(find.text('Icon').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(service.settings.quickActionsHeader.display, QuickActionsHeaderDisplay.icon);
    expect(interval, findsNothing);
    expect(service.settings.quickActionsHeader.intervalMsFor(QuickActionsHeaderDisplay.noise), 10000);
    expect(service.settings.quickActions.toJson(), popupBefore);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
