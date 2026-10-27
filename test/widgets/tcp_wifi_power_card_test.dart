import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/tcp_wifi_power_card.dart';

void main() {
  for (final language in ['en', 'ru']) {
    testWidgets('Wi-Fi custom toggle and read-only preset ($language)', (tester) async {
      var releaseAllowed = false;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) =>
          TcpWifiPowerCard(releaseAllowed: releaseAllowed, onChanged: (value) {
            setState(() { releaseAllowed = value; });
          }))),
      ));
      final tile = find.byType(SwitchListTile);
      final context = tester.element(tile);
      final l10n = AppLocalizations.of(context);
      expect(find.text(l10n.powerSaving_releaseTcpWifiLock), findsOneWidget);
      expect(find.text(l10n.powerSaving_releaseTcpWifiLockDescription), findsOneWidget);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(releaseAllowed, isTrue);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);

      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: TcpWifiPowerCard(releaseAllowed: false)),
      ));
      expect(tester.widget<SwitchListTile>(tile).onChanged, isNull);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    });
  }
}
