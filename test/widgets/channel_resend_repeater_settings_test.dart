import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/widgets/channel_resend_repeater_settings.dart';

void main() {
  testWidgets('toggle reveals a 2–10 slider and preserves its independent value', (
    tester,
  ) async {
    var settings = AppSettings(
      channelMinHops: 3,
      channelMinHopsRepeaterCount: 7,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ChannelResendRepeaterSettings(
              settings: settings,
              onEnabledChanged: (value) => setState(() {
                settings = settings.copyWith(channelMinHopsCountRepeaters: value);
              }),
              onCountChanged: (value) => setState(() {
                settings = settings.copyWith(channelMinHopsRepeaterCount: value);
              }),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Slider), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    var slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 2);
    expect(slider.max, 10);
    expect(slider.divisions, 8);
    expect(slider.value, 7);
    expect(find.text('Требуется ближайших репитеров: 7'), findsOneWidget);
    expect(find.textContaining('7 разных ближайших репитеров'), findsOneWidget);

    // Exercise the slider's UI callback, without changing the route hop target.
    slider.onChanged!(10);
    await tester.pumpAndSettle();
    expect(settings.channelMinHops, 3);
    expect(settings.channelMinHopsRepeaterCount, 10);
    expect(find.text('Требуется ближайших репитеров: 10'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 10);
    expect(settings.channelMinHops, 3);
  });

  testWidgets('English controls show the repeater target in title and subtitle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChannelResendRepeaterSettings(
            settings: AppSettings(
              channelMinHops: 3,
              channelMinHopsCountRepeaters: true,
              channelMinHopsRepeaterCount: 5,
            ),
            onEnabledChanged: (_) {},
            onCountChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Required nearby repeaters: 5'), findsOneWidget);
    expect(find.textContaining('5 different nearby repeaters'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 5);
  });
}
