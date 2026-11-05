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
  final urlWrites = <bool>[];
  int radioUpdates = 0;
  int completedSaves = 0;
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
  Future<void> setChannelCyr2LatEnabled(int index, bool value) async {}
  @override
  Future<void> setChannelCyr2LatProfileId(int index, String? value) async {}
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

  Widget app(_Settings settings, Widget child, {String language = 'en'}) =>
      ChangeNotifierProvider<AppSettingsService>.value(
        value: settings,
        child: MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

  Future<AppLocalizations> openSheet(WidgetTester tester, _Settings settings, _ChannelConnector connector) async {
    final channel = Channel(index: 1, name: 'Example', psk: Uint8List.fromList(List.filled(16, 1)));
    await tester.pumpWidget(app(settings, Builder(builder: (context) => TextButton(
      onPressed: () => showChannelEditSheet(context, connector, channel),
      child: const Text('Edit'),
    ))));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(DraggableScrollableSheet)));
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
