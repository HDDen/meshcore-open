import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/screens/channel_share_screen.dart';

// The share screen's copy button says it copies a link; it used to borrow the
// contact screen's "Copy Contact to clipboard".

void main() {
  testWidgets('the copy button says it copies the link', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: ChannelShareScreen(
          channel: Channel(
            index: 1,
            name: '#ping',
            psk: Channel.parsePskHex('3cae16fd067ba9c32a98be22e9b98525'),
          ),
          displayName: '#ping',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Copy Contact to clipboard'), findsNothing);
  });
}
