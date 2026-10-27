import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/delivery_observation_power_card.dart';

void main() {
  for (final language in ['en', 'ru']) {
    testWidgets('delivery statistics custom and read-only preset ($language)', (tester) async {
      var enabled = false;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) =>
          DeliveryObservationPowerCard(enabled: enabled, onChanged: (value) {
            setState(() { enabled = value; });
          }))),
      ));
      final tile = find.byType(SwitchListTile);
      final l10n = AppLocalizations.of(tester.element(tile));
      expect(find.text(l10n.powerSaving_reduceDeliveryObservationWrites), findsOneWidget);
      expect(find.text(l10n.powerSaving_reduceDeliveryObservationWritesDescription), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(enabled, isTrue);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);

      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: DeliveryObservationPowerCard(enabled: false)),
      ));
      expect(tester.widget<SwitchListTile>(tile).onChanged, isNull);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    });
  }
}
