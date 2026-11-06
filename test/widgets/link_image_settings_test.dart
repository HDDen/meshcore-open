import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/channel_edit_sheet.dart';
import 'package:meshcore_open/widgets/link_image_settings_tiles.dart';
import '../support/wrapping_label_expectations.dart';

class _NoPaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('synthetic link settings');
}

class _Settings extends AppSettingsService {
  AppSettings value = AppSettings();
  @override
  AppSettings get settings => value;
  @override
  Future<void> setLoadLinkImages(bool enabled) async {
    value = value.copyWith(loadLinkImages: enabled);
    notifyListeners();
  }
  @override
  Future<void> setShowLinkImagesByDefault(bool enabled) async {
    value = value.copyWith(showLinkImagesByDefault: enabled);
    notifyListeners();
  }
}

// Capture sheet commands without radio, SQL or preference writes. Real store
// inheritance/reopen tests live in the storage baseline package.
class _ChannelConnector extends MeshCoreConnector {
  bool initialUrlChoice = false;
  bool cyr2latChoice = false;
  String? cyr2latProfile;
  final cyr2latWrites = <bool>[];
  final profileWrites = <String?>[];
  final urlWrites = <bool>[];
  int radioUpdates = 0;
  int completedSaves = 0;
  @override
  bool isChannelCyr2LatEnabled(int channelIndex) => cyr2latChoice;
  @override
  String? getChannelCyr2LatProfileId(int channelIndex) => cyr2latProfile;
  @override
  bool isChannelUrlImagesEnabled(int channelIndex) => initialUrlChoice;
  @override
  Future<void> setChannelUrlImagesEnabled(int channelIndex, bool enabled) async {
    urlWrites.add(enabled);
  }
  @override
  Future<void> setChannel(int index, String name, Uint8List psk) async { radioUpdates++; }
  @override
  Future<void> setChannelMcmpEnabled(int index, bool value) async {}
  @override
  Future<void> setChannelMcmpVersion(int index, int value) async {}
  @override
  Future<void> setChannelMcmpUseSign(int index, bool value) async {}
  @override
  Future<void> setChannelMCOtxtEnabled(int index, bool value) async {}
  @override
  Future<void> setChannelMCOtxtPlainWhenSmaller(int index, bool value) async {}
  @override
  Future<void> setChannelSmazEnabled(int index, bool value) async {}
  @override
  Future<void> setChannelCyr2LatEnabled(int index, bool value) async {
    cyr2latWrites.add(value);
    cyr2latChoice = value;
  }
  @override
  Future<void> setChannelCyr2LatProfileId(int index, String? value) async {
    profileWrites.add(value);
    cyr2latProfile = value;
  }
  @override
  Future<void> setChannelSendingDelayEnabled(int index, bool value) async {}
  @override
  Future<void> setChannelQuickAnswerIds(int index, List<String> value) async {}
  @override
  Future<void> setChannelWidgetColor(int index, int? value) async {}
  @override
  Future<void> setChannelWidgetTextColor(int index, int? value) async { completedSaves++; }
}

void main() {
  late PathProviderPlatform previousPaths;
  setUp(() async {
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPaths();
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(() {
    PathProviderPlatform.instance = previousPaths;
    PrefsManager.reset();
  });

  Widget app(_Settings settings, Widget child, {
    String language = 'en',
    double textScale = 1,
  }) =>
      ChangeNotifierProvider<AppSettingsService>.value(
        value: settings,
        child: MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(body: child),
        ),
      );

  for (final language in ['en', 'ru']) {
    testWidgets('master disables the default control without clearing it ($language)', (tester) async {
      final settings = _Settings();
      addTearDown(settings.dispose);
      await tester.pumpWidget(app(settings,
        const SingleChildScrollView(child: LinkImageSettingsTiles()), language: language,
      ));
      final master = find.byKey(const ValueKey('load-link-images'));
      final fallback = find.byKey(const ValueKey('show-link-images-by-default'));
      expect(tester.widget<SwitchListTile>(master).value, isFalse);
      expect(tester.widget<SwitchListTile>(fallback).value, isFalse);
      expect(tester.widget<SwitchListTile>(fallback).onChanged, isNull);
      await tester.ensureVisible(master);
      await tester.tap(master);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(master).value, isTrue);
      await tester.ensureVisible(fallback);
      await tester.tap(fallback);
      await tester.pumpAndSettle();
      expect(settings.settings.showLinkImagesByDefault, isTrue);
      await tester.ensureVisible(master);
      await tester.tap(master);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(fallback).value, isTrue);
      expect(tester.widget<SwitchListTile>(fallback).onChanged, isNull);
      expect(settings.settings.showLinkImagesByDefault, isTrue);
      await tester.tap(master);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(fallback).onChanged, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  Future<AppLocalizations> openSheet(WidgetTester tester, _Settings settings, _ChannelConnector connector, {
    String language = 'en',
    Size size = const Size(800, 600),
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final channel = Channel(index: 1, name: 'Example', psk: Uint8List.fromList(List.filled(16, 1)));
    await tester.pumpWidget(app(settings,
      Builder(builder: (context) => TextButton(
        onPressed: () => showChannelEditSheet(context, connector, channel),
        child: const Text('Edit'),
      )), language: language, textScale: textScale,
    ));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(DraggableScrollableSheet)));
  }

  Future<Finder> revealProfile(WidgetTester tester) async {
    final field = find.byType(DropdownButtonFormField<String>);
    final scrollable = find.descendant(
      of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable),
    ).first;
    // The editor's ListView builds later compression controls lazily.
    await tester.scrollUntilVisible(field, 200,
        scrollable: scrollable, maxScrolls: 30);
    await tester.pumpAndSettle();
    return field;
  }

  for (final language in ['en', 'ru']) {
    for (final save in [false, true]) {
      for (final layout in [
        (name: 'baseline', size: const Size(800, 600), scale: 1.0),
        (name: 'phone', size: const Size(320, 568), scale: 2.0),
        (name: 'landscape', size: const Size(568, 360), scale: 2.0),
      ]) {
        testWidgets('U11b4 ${layout.name}: Cyr2Lat profile stays a draft until Save ($language, save=$save)', (tester) async {
          final longLabels = layout.name != 'baseline';
          final alpha = !longLabels ? 'Alpha' : language == 'en'
              ? 'Alpha extended profile' : 'Альфа расширенный профиль';
          final beta = !longLabels ? 'Beta' : language == 'en'
              ? 'Beta extended profile' : 'Бета расширенный профиль';
          final settings = _Settings()..value = AppSettings(cyr2latProfiles: [
            Cyr2LatProfile(id: 'synthetic-a', name: alpha, charMap: const {'я': 'ya'}),
            Cyr2LatProfile(id: 'synthetic-b', name: beta, charMap: const {'я': 'ja'}),
          ]);
          final connector = _ChannelConnector()
            ..cyr2latChoice = true
            ..cyr2latProfile = 'synthetic-a';
          try {
            final l10n = await openSheet(tester, settings, connector,
                language: language, size: layout.size, textScale: layout.scale);
            final field = await revealProfile(tester);
            final button = find.descendant(of: field, matching: find.byType(DropdownButton<String>));
            expect(tester.widget<DropdownButton<String>>(button).value, 'synthetic-a');
            final arrow = find.descendant(of: field, matching: find.byIcon(Icons.arrow_drop_down));
            await tester.ensureVisible(arrow);
            await tester.pump();
            expect(arrow.hitTestable(), findsOneWidget);
            await tester.tap(arrow);
            await tester.pumpAndSettle();
            final option = await revealDropdownOption(tester, beta);
            if (longLabels) {
              expectCompleteWrappingLabel(tester, option, wraps: layout.name == 'phone');
            }
            await tester.tap(option);
            await tester.pumpAndSettle();
            expect(tester.widget<DropdownButton<String>>(button).value, 'synthetic-b');
            if (longLabels) {
              expectCompleteWrappingLabel(tester,
                  find.descendant(of: field, matching: find.text(beta)),
                  wraps: layout.name == 'phone');
            }
            expect(connector.profileWrites, isEmpty);
            expect(connector.cyr2latWrites, isEmpty);
            expect(connector.cyr2latProfile, 'synthetic-a');
            expect(connector.radioUpdates, 0);
            await tester.tap(save
                ? find.widgetWithText(FilledButton, l10n.common_save)
                : find.widgetWithText(OutlinedButton, l10n.common_cancel));
            await tester.pumpAndSettle();
            expect(find.byType(DraggableScrollableSheet), findsNothing);
            expect(connector.profileWrites, save ? ['synthetic-b'] : isEmpty);
            expect(connector.cyr2latWrites, save ? [true] : isEmpty);
            expect(connector.completedSaves, save ? 1 : 0);
            expect(connector.radioUpdates, 0); // No name/key change or history resync.
            await tester.tap(find.text('Edit'));
            await tester.pumpAndSettle();
            final reopened = await revealProfile(tester);
            expect(tester.widget<DropdownButton<String>>(find.descendant(
              of: reopened, matching: find.byType(DropdownButton<String>),
            )).value, save ? 'synthetic-b' : 'synthetic-a');
            if (longLabels) {
              expectCompleteWrappingLabel(tester,
                  find.descendant(of: reopened, matching: find.text(save ? beta : alpha)),
                  wraps: layout.name == 'phone');
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            connector.dispose();
            settings.dispose();
          }
        });
      }
    }
  }

  testWidgets('saving other channel fields keeps an unset URL choice unset', (tester) async {
    final settings = _Settings()..value = AppSettings(loadLinkImages: true);
    final connector = _ChannelConnector()..initialUrlChoice = true;
    addTearDown(settings.dispose);
    addTearDown(connector.dispose);
    final l10n = await openSheet(tester, settings, connector);
    await tester.tap(find.text(l10n.common_save));
    await tester.pumpAndSettle();
    expect(connector.urlWrites, isEmpty);
    expect(connector.radioUpdates, 0);
    expect(connector.completedSaves, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('editing back to the original value saves an explicit off', (tester) async {
    final settings = _Settings()..value = AppSettings(loadLinkImages: true);
    final connector = _ChannelConnector();
    addTearDown(settings.dispose);
    addTearDown(connector.dispose);
    final l10n = await openSheet(tester, settings, connector);
    final tile = find.widgetWithText(SwitchListTile, l10n.urlImage_enable);
    final scrollable = find.descendant(
      of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable),
    ).first;
    await tester.scrollUntilVisible(tile, 250, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.common_save));
    await tester.pumpAndSettle();
    expect(connector.urlWrites, [false]);
    expect(connector.completedSaves, 1);
    expect(connector.radioUpdates, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('master off disables the channel control and preserves its choice', (tester) async {
    final settings = _Settings()..value = AppSettings(loadLinkImages: false);
    final connector = _ChannelConnector()..initialUrlChoice = true;
    addTearDown(settings.dispose);
    addTearDown(connector.dispose);
    final l10n = await openSheet(tester, settings, connector);
    final tile = find.widgetWithText(SwitchListTile, l10n.urlImage_enable);
    final scrollable = find.descendant(
      of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable),
    ).first;
    await tester.scrollUntilVisible(tile, 250, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(tester.widget<SwitchListTile>(tile).onChanged, isNull);
    await tester.tap(find.text(l10n.common_save));
    await tester.pumpAndSettle();
    expect(connector.urlWrites, isEmpty);
    expect(connector.completedSaves, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
