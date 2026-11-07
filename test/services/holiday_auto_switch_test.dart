import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/custom_theme.dart';
import 'package:meshcore_open/models/holiday_schedule.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  test('U19c: calendar keeps the nearest holiday through its own day', () {
    expect(activeHolidayFor(DateTime(2026, 11, 8)), isNull);
    final thanksgiving = activeHolidayFor(DateTime(2026, 11, 9))!;
    expect(thanksgiving.holiday, ThemeHoliday.thanksgiving);
    expect(thanksgiving.date, DateTime(2026, 11, 26));
    expect(thanksgiving.daysAway, 17);

    final christmas = DateTime(2026, 12, 25, 23, 59);
    expect(activeHolidayFor(christmas)?.holiday, ThemeHoliday.christmas);
    expect(nextHolidayThemeChangeAfter(christmas), DateTime(2026, 12, 26));
    final newYear = activeHolidayFor(DateTime(2026, 12, 26))!;
    expect(newYear.holiday, ThemeHoliday.newYear);
    expect(newYear.date, DateTime(2027));
    expect(nextHolidayThemeChangeAfter(DateTime(2026, 12, 26)), DateTime(2027, 1, 2));
    expect(activeHolidayFor(DateTime(2027, 1, 2)), isNull);
  });

  testWidgets('U19c: opt-in uses one foreground boundary and resumes from date', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 13, 20);
    var clockReads = 0;
    final service = AppSettingsService(clock: () {
      clockReads++;
      return now;
    });
    addTearDown(service.dispose);
    await service.loadSettings();
    service.setHolidayThemeForeground(true);
    expect(service.settings.holidayAnimationsEnabled, isFalse);
    expect(service.settings.holidayAutoSwitch, isFalse);
    expect(clockReads, 0);
    final manual = CustomTheme.presets.first;
    await service.setActiveTheme(manual.id);
    await service.setHolidayAutoSwitch(true);
    expect(clockReads, 1);
    expect(service.activeCustomTheme, manual);
    final saved = PrefsManager.instance.getString('app_settings');

    const threeHours = Duration(hours: 3);
    now = now.add(threeHours);
    await tester.pump(threeHours);
    expect(clockReads, 1);
    const oneHour = Duration(hours: 1);
    now = now.add(oneHour);
    await tester.pump(oneHour);
    expect(service.activeCustomTheme?.id, ThemeHoliday.halloween.themeId);
    expect(service.chosenCustomTheme, manual);
    expect(PrefsManager.instance.getString('app_settings'), saved);

    service.setHolidayThemeForeground(false);
    final beforeBackground = clockReads;
    const twentyDays = Duration(days: 20);
    now = now.add(twentyDays);
    await tester.pump(twentyDays);
    expect(clockReads, beforeBackground);
    service.setHolidayThemeForeground(true);
    expect(service.activeCustomTheme, manual);
    expect(PrefsManager.instance.getString('app_settings'), saved);
    await service.setHolidayAutoSwitch(false);
    final afterDisable = clockReads;
    await tester.pump(const Duration(days: 30));
    expect(clockReads, afterDisable);
  });

  test('U19c: a manual choice persists for one occurrence only', () async {
    var now = DateTime(2026, 10, 31);
    final service = AppSettingsService(clock: () => now);
    addTearDown(service.dispose);
    await service.loadSettings();
    final preset = CustomTheme.presets.first;
    await service.setActiveTheme(preset.id);
    await service.setHolidayAutoSwitch(true);
    final halloween = service.autoHolidayTheme!;
    expect(halloween.id, ThemeHoliday.halloween.themeId);

    await service.setActiveTheme(halloween.id);
    expect(service.chosenCustomTheme, preset);
    await service.setActiveTheme(preset.id);
    expect(service.activeCustomTheme, preset);
    final reopened = AppSettingsService(clock: () => now);
    addTearDown(reopened.dispose);
    await reopened.loadSettings();
    expect(reopened.activeCustomTheme, preset);

    now = DateTime(2026, 11, 26);
    reopened.setHolidayThemeForeground(true);
    expect(reopened.activeCustomTheme?.id, ThemeHoliday.thanksgiving.themeId);
    reopened.setHolidayThemeForeground(false);
    await reopened.setThemeMode('dark');
    expect(reopened.activeCustomTheme, isNull);
    expect(reopened.settings.themeMode, 'dark');
  });
}
