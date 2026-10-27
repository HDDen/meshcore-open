import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/ble_power_options.dart';
import 'package:meshcore_open/widgets/ble_connection_priority_card.dart';

void main() {
  for (final language in ['en', 'ru']) {
    testWidgets('all Android choices and read-only preset ($language)', (tester) async {
      var mode = BleConnectionPriorityMode.original;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) =>
          BleConnectionPriorityCard(mode: mode,
              onChanged: (next) => setState(() { mode = next; })))),
      ));
      final finder = find.byType(DropdownButton<BleConnectionPriorityMode>);
      final dropdown = tester.widget<DropdownButton<BleConnectionPriorityMode>>(finder);
      expect(dropdown.items!.map((item) => item.value), BleConnectionPriorityMode.values);
      dropdown.onChanged!(BleConnectionPriorityMode.lowPower);
      await tester.pump();
      expect(tester.widget<DropdownButton<BleConnectionPriorityMode>>(finder).value,
          BleConnectionPriorityMode.lowPower);
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: BleConnectionPriorityCard(
          mode: BleConnectionPriorityMode.original,
        )),
      ));
      expect(tester.widget<DropdownButton<BleConnectionPriorityMode>>(finder).onChanged,
          isNull);
    });
  }
}
