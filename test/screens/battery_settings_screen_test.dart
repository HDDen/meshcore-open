import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mco_service/mco_service.dart' show SettingsSectionsService;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/screens/mod_settings_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/low_battery_settings_card.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';
import 'package:meshcore_open/widgets/power_saving_settings_tile.dart';

class _NoDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('Synthetic preferences without directory');
}

class _Sections extends ChangeNotifier implements SettingsSectionsService {
  @override
  List<Widget> modSettingsSections(BuildContext context) => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform originalPaths;
  setUpAll(() {
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDirectory();
  });
  tearDownAll(() => PathProviderPlatform.instance = originalPaths);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  for (final locale in ['en', 'ru']) {
    testWidgets('battery section follows storage and includes power saving ($locale)', (tester) async {
      final settings = AppSettingsService();
      final connector = MeshCoreConnector();
      final sections = _Sections();
      try {
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: connector),
            ChangeNotifierProvider<SettingsSectionsService>.value(value: sections),
          ],
          child: MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ModSettingsScreen(),
          ),
        ));
        final l10n = AppLocalizations.of(tester.element(find.byType(ModSettingsScreen)));
        final list = tester.widget<ListView>(find.byType(ListView));
        final children = (list.childrenDelegate as SliverChildListDelegate).children;
        final headers = children.whereType<SectionHeader>().map((widget) => widget.label).toList();
        expect(headers.indexOf(l10n.settings_modSettingsBattery),
            headers.indexOf(l10n.settings_modSettingsMessageStorage) + 1);
        final battery = children.indexWhere((widget) => widget is SectionHeader &&
            widget.label == l10n.settings_modSettingsBattery);
        expect((children[battery + 1] as MeshCard).child, isA<PowerSavingSettingsTile>());
        final scrollable = find.descendant(of: find.byType(ListView),
            matching: find.byType(Scrollable)).first;
        await tester.scrollUntilVisible(find.byType(LowBatterySettingsCard), 400, scrollable: scrollable);
        await tester.pump();
        expect(find.text(l10n.settings_lowBatteryAlerts), findsOneWidget);
        expect(find.byType(PowerSavingSettingsTile), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        connector.dispose();
        sections.dispose();
        settings.dispose();
      }
    });
  }

  for (final scale in [1.0, 1.5]) {
    testWidgets('battery levels scroll, persist and survive disabling at scale $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = AppSettingsService();
      try {
        await tester.pumpWidget(ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(body: LowBatterySettingsCard()),
          ),
        ));
        expect(tester.widgetList<Checkbox>(find.byType(Checkbox)).map((widget) => widget.value),
            [false, true, false, false, true, false]);
        await tester.tap(find.text('5%'));
        await tester.pump();
        await tester.drag(find.byType(SingleChildScrollView), const Offset(-500, 0));
        await tester.pumpAndSettle();
        expect(find.text('30%').hitTestable(), findsOneWidget);
        await tester.tap(find.text('30%'));
        await tester.pump();
        expect(settings.settings.lowBatteryAlerts.thresholds, [5, 10, 25, 30]);
        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();
        expect(find.byType(Checkbox), findsNothing);
        expect(settings.settings.lowBatteryAlerts.enabled, isFalse);
        final restored = AppSettingsService();
        try {
          await restored.loadSettings();
          expect(restored.settings.lowBatteryAlerts.toJson(), settings.settings.lowBatteryAlerts.toJson());
        } finally {
          restored.dispose();
        }
        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();
        expect(settings.settings.lowBatteryAlerts.thresholds, [5, 10, 25, 30]);
        expect(find.byType(Checkbox), findsNWidgets(6));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        settings.dispose();
      }
    });
  }
}
