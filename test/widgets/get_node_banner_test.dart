import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/get_node_banner.dart';

void main() {
  Future<void> pumpBanner(
    WidgetTester tester, {
    required Size size,
    required double textScale,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const Scaffold(bottomNavigationBar: GetNodeBanner()),
        ),
      ),
    );
  }

  testWidgets('shows the pitch and affiliate link', (tester) async {
    await pumpBanner(tester, size: const Size(390, 844), textScale: 1);

    expect(find.text('Need a new node?'), findsOneWidget);
    expect(find.text('Get one here'), findsOneWidget);
    expect(find.textContaining('Affiliate link'), findsOneWidget);
    expect(getNodeUrl, contains('sensecap_affiliate=JFWID0g'));
    // Leaves most of the screen for the device list.
    expect(
      tester.getSize(find.byType(GetNodeBanner)).height,
      lessThan(844 * 0.4),
    );
  });

  testWidgets('lays out on a narrow phone with large text', (tester) async {
    await pumpBanner(tester, size: const Size(320, 800), textScale: 1.5);
    expect(tester.takeException(), isNull);
  });
}
