import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/channel_identity_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/channel_notification_mode_sheet.dart';

class _NoDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('Synthetic preferences without a directory');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform paths;
  late AppSettingsService settings;
  setUpAll(() {
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDirectory();
  });
  tearDownAll(() => PathProviderPlatform.instance = paths);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    ChannelIdentities.instance.resetForTesting();
    settings = AppSettingsService();
  });
  tearDown(() {
    settings.dispose();
    ChannelIdentities.instance.resetForTesting();
    PrefsManager.reset();
  });

  for (final locale in ['en', 'ru']) {
    for (final layout in const [
      (name: 'default', size: Size(800, 600), textScale: 1.0, bottomInset: 0.0, scrolls: false),
      (name: 'phone', size: Size(320, 568), textScale: 1.0, bottomInset: 0.0, scrolls: false),
      (name: 'desktop', size: Size(1280, 800), textScale: 2.0, bottomInset: 0.0, scrolls: false),
      (name: 'short', size: Size(320, 220), textScale: 2.0, bottomInset: 0.0, scrolls: true),
      (name: 'keyboard', size: Size(320, 568), textScale: 2.0, bottomInset: 360.0, scrolls: true),
    ]) {
      testWidgets('all three choices persist and reopen selected ($locale, ${layout.name})', (tester) async {
        tester.view.physicalSize = layout.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          await tester.pumpWidget(ChangeNotifierProvider.value(
            value: settings,
            child: MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(layout.textScale),
                  viewInsets: EdgeInsets.only(bottom: layout.bottomInset),
                ),
                child: child!,
              ),
              home: Scaffold(body: Builder(builder: (context) => TextButton(
                onPressed: () => showChannelNotificationModeSheet(context, 'Test'),
                child: const Text('Modes'),
              ))),
            ),
          ));
          await tester.pump();
          for (final mode in ChannelNotificationMode.values) {
            await tester.tap(find.text('Modes'));
            await tester.pumpAndSettle();
            final context = tester.element(find.byType(ListTile).first);
            final label = channelNotificationModeLabel(context, mode);
            expect(find.byType(ListTile), findsNWidgets(3));
            final choice = find.widgetWithText(ListTile, label);
            if (layout.scrolls) {
              final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
              expect(position.maxScrollExtent, greaterThan(0));
              await tester.ensureVisible(choice);
              await tester.pumpAndSettle();
            }
            await tester.tap(choice);
            await tester.pumpAndSettle();
            expect(settings.getChannelNotificationMode('Test'), mode);
            await tester.tap(find.text('Modes'));
            await tester.pumpAndSettle();
            final selected = find.widgetWithText(ListTile, label);
            if (layout.scrolls) {
              await tester.ensureVisible(selected);
              await tester.pumpAndSettle();
            }
            expect(find.descendant(of: selected, matching: find.byIcon(Icons.check)), findsOneWidget);
            Navigator.of(tester.element(selected)).pop();
            await tester.pumpAndSettle();
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      });
    }
  }
}
