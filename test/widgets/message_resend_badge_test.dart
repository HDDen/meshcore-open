import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/message_resend_badge.dart';
import 'package:meshcore_open/widgets/tx_power_boost_badge.dart';

void main() {
  for (final pending in [false, true]) {
    for (final withLna in [false, true]) {
      testWidgets(
        'shared attempts show spinner and confirmed power (pending=$pending, LNA=$withLna)',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: MessageResendBadge(
                  resends: 2,
                  pending: pending,
                  color: Colors.grey,
                  boosted: true,
                  withLna: withLna,
                ),
              ),
            ),
          );
          expect(find.text('3'), findsOneWidget);
          expect(
            find.byType(CircularProgressIndicator),
            pending ? findsOneWidget : findsNothing,
          );
          expect(
            find.byIcon(Icons.replay),
            pending ? findsNothing : findsOneWidget,
          );
          expect(
            tester
                .widget<TxPowerBoostBadge>(find.byType(TxPowerBoostBadge))
                .withLna,
            withLna,
          );
          expect(
            tester.widget<Icon>(find.byIcon(Icons.bolt)).color,
            withLna ? Colors.red : Colors.grey,
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
