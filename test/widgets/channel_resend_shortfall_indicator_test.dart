import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/channel_resend_shortfall_indicator.dart';

void main() {
  for (final language in ['ru', 'en']) {
    testWidgets('tracing shortfall appears and disappears with coverage ($language)', (tester) async {
      final shortfall = ValueNotifier<({int hops, int required})?>(null);
      try {
        await tester.pumpWidget(MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ValueListenableBuilder<({int hops, int required})?>(
            valueListenable: shortfall,
            builder: (context, value, _) => ChannelResendShortfallIndicator(shortfall: value),
          )),
        ));
        expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
        shortfall.value = (hops: 1, required: 2);
        await tester.pump();
        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
        expect(find.byIcon(Icons.done), findsNothing);
        final context = tester.element(find.byType(ChannelResendShortfallIndicator));
        expect(tester.widget<Tooltip>(find.byType(Tooltip)).message,
            AppLocalizations.of(context).messageStatus_hopsNotReached(1, 2));
        expect(tester.hasRunningAnimations, isFalse);
        shortfall.value = null;
        await tester.pump();
        expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        shortfall.dispose();
      }
    });
  }
}
