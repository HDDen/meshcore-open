import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/cpu_sleep_options.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/widgets/cpu_sleep_settings_card.dart';

void main() {
  for (final language in ['ru', 'en']) {
    testWidgets('CPU always preserves scenario choices ($language)', (tester) async {
      var value = const CpuSleepOptions(ble: true, proxy: true);
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language), supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: SingleChildScrollView(child: StatefulBuilder(
          builder: (context, setState) => CpuSleepSettingsCard(options: value,
            onChanged: (next) => setState(() { value = next; })),
        ))),
      ));
      await tester.ensureVisible(find.byKey(const ValueKey('power-saving-cpu-always')));
      await tester.tap(find.byKey(const ValueKey('power-saving-cpu-always')));
      await tester.pump();
      expect(value.always, isTrue);
      for (final name in ['ble', 'tcp', 'proxy', 'wardrive']) {
        final tile = tester.widget<CheckboxListTile>(
          find.byKey(ValueKey('power-saving-cpu-$name')));
        expect(tile.onChanged, isNull);
      }
      expect(value.ble && value.proxy, isTrue);
      await tester.tap(find.byKey(const ValueKey('power-saving-cpu-always')));
      await tester.pump();
      expect(value.always, isFalse);
      expect(value.ble && value.proxy, isTrue);
      expect(tester.widget<CheckboxListTile>(find.byKey(
        const ValueKey('power-saving-cpu-tcp'))).onChanged, isNotNull);
    });
  }

  testWidgets('default CPU card is read-only and starts with every permission off', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SingleChildScrollView(child:
        CpuSleepSettingsCard(options: CpuSleepOptions()))),
    ));
    for (final tile in tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile))) {
      expect(tile.onChanged, isNull);
      expect(tile.value, isFalse);
    }
  });

  for (final entry in {
    PowerSavingProfile.economical: 'ble',
    PowerSavingProfile.maximum: 'always',
  }.entries) {
    testWidgets('${entry.key.name} preset displays its protected CPU choice read-only',
        (tester) async {
      final options = PowerSavingSettings(profile: entry.key).effective.cpuSleep;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child:
          CpuSleepSettingsCard(options: options))),
      ));
      for (final key in ['unconditional', 'always', 'ble', 'tcp', 'proxy', 'wardrive']) {
        final tile = tester.widget<CheckboxListTile>(
          find.byKey(ValueKey('power-saving-cpu-$key')));
        expect(tile.value, key == entry.value);
        expect(tile.onChanged, isNull);
      }
    });
  }

  for (final language in ['ru', 'en']) {
    testWidgets('unconditional disables protected choices without erasing them ($language)',
        (tester) async {
      var value = const CpuSleepOptions(always: true, ble: true, proxy: true);
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language), supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: SingleChildScrollView(child: StatefulBuilder(
          builder: (context, setState) => CpuSleepSettingsCard(options: value,
            onChanged: (next) => setState(() { value = next; })),
        ))),
      ));
      final toggle = find.byKey(const ValueKey('power-saving-cpu-unconditional'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(value.unconditional, isTrue);
      for (final name in ['always', 'ble', 'tcp', 'proxy', 'wardrive']) {
        expect(tester.widget<CheckboxListTile>(find.byKey(
          ValueKey('power-saving-cpu-$name'))).onChanged, isNull);
      }
      expect(value.always && value.ble && value.proxy, isTrue);
      await tester.tap(toggle);
      await tester.pump();
      expect(value.unconditional, isFalse);
      expect(value.always && value.ble && value.proxy, isTrue);
      expect(tester.widget<CheckboxListTile>(find.byKey(
        const ValueKey('power-saving-cpu-always'))).onChanged, isNotNull);
    });
  }
}
