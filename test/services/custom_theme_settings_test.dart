import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/chat_background.dart';
import 'package:meshcore_open/models/custom_theme.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/theme/theme_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _forest = CustomTheme(
  id: 'custom:forest',
  name: 'Forest',
  background: Color(0xFF0E1A13),
  accent: Color(0xFF4ADE80),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode({
        'theme_mode': 'dark',
        'ui_scale': 1.35,
        'language_override': 'ru',
        'public_ipfs_gateway': 'https://chosen.example/ipfs/',
      }),
    });
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  Future<AppSettingsService> open() async {
    final service = AppSettingsService();
    addTearDown(service.dispose);
    await service.loadSettings();
    return service;
  }

  test('U19a: save, apply, edit and reopen preserve the stock appearance settings', () async {
    final service = await open();
    expect(service.activeCustomTheme, isNull);
    await service.saveCustomTheme(_forest, apply: true);
    final edited = _forest.copyWith(name: 'Forest edited');
    await service.saveCustomTheme(edited);
    final reopened = await open();
    expect(reopened.settings.customThemes, [edited]);
    expect(reopened.activeCustomTheme, edited);
    expect(reopened.settings.themeMode, 'dark');
    expect(reopened.settings.uiScale, 1.35);
    expect(reopened.settings.languageOverride, 'ru');
    expect(reopened.settings.publicIpfsGateway, 'https://chosen.example/ipfs/');
    await reopened.setThemeMode('light');
    expect(reopened.activeCustomTheme, isNull);
    expect(reopened.settings.customThemes, [edited]);
    expect((await open()).settings.themeMode, 'light');
  });

  test('U19a: presets and removal return to the saved stock mode', () async {
    final service = await open();
    final preset = CustomTheme.presets.first;
    await service.setActiveTheme(preset.id);
    expect(service.chosenCustomTheme, preset);
    expect(service.settings.customThemes, isEmpty);
    await service.setActiveTheme(null);
    expect(service.activeCustomTheme, isNull);
    await service.saveCustomTheme(_forest, apply: true);
    await service.deleteCustomTheme(_forest.id);
    final reopened = await open();
    expect(reopened.settings.activeThemeId, isNull);
    expect(reopened.settings.customThemes, isEmpty);
    expect(reopened.settings.themeMode, 'dark');
    await expectLater(reopened.setActiveTheme('custom:missing'), throwsArgumentError);
    expect(reopened.activeCustomTheme, isNull);
  });

  test('U19a: import skips duplicates and resolves an ID collision in one update', () async {
    final service = await open();
    await service.saveCustomTheme(_forest, apply: true);
    var updates = 0;
    service.addListener(() => updates++);
    final duplicate = _forest.copyWith(id: 'custom:other');
    final collision = _forest.copyWith(name: 'A different theme');
    expect(await service.importCustomThemes([duplicate, collision, collision]), 1);
    expect(updates, 1);
    final saved = service.settings.customThemes;
    expect(saved.first, _forest);
    expect(saved.last.id, isNot(_forest.id));
    expect(saved.last.name, collision.name);
    expect(service.activeCustomTheme, _forest);
    expect((await open()).settings.customThemes, saved);
    expect(await service.importCustomThemes([duplicate]), 0);
    expect(updates, 1);
  });

  test('U19a: unprepared inline media rejects an import before applying any changes', () async {
    final service = await open();
    final before = PrefsManager.instance.getString('app_settings');
    final inline = const ChatBackground.color(Color(0xFF112233))
        .withInlineImage(Uint8List.fromList([1, 2, 3]));
    final unprepared = _forest.copyWith(
      id: 'custom:picture',
      chatBackground: inline,
    );
    await expectLater(service.importCustomThemes([_forest, unprepared]), throwsArgumentError);
    expect(service.settings.customThemes, isEmpty);
    expect(PrefsManager.instance.getString('app_settings'), before);

    final prepared = unprepared.copyWith(chatBackground: inline.withStoredImage('picture-1'));
    expect(await service.importCustomThemes([prepared]), 1);
    expect((await open()).settings.customThemes.single.chatBackground!.imageId, 'picture-1');
  });

  test('U19a: the saved library captures the editor icon map', () async {
    final service = await open();
    final overrides = {'map': const ThemeIconOverride.icon('park')};
    await service.saveCustomTheme(_forest.copyWith(icons: overrides));
    overrides.clear();
    expect(service.settings.customThemes.single.icons['map']?.icon, 'park');
    expect((await open()).settings.customThemes.single.icons['map']?.icon, 'park');
  });

  test('U19a: exceeding the library size preserves the saved library', () async {
    final service = await open();
    final themes = List.generate(CustomTheme.maxSavedThemes, (index) {
      return _forest.copyWith(id: 'custom:$index', name: 'Theme $index');
    });
    expect(await service.importCustomThemes(themes), themes.length);
    final before = PrefsManager.instance.getString('app_settings');
    await expectLater(service.saveCustomTheme(_forest), throwsStateError);
    expect(service.settings.customThemes, themes);
    expect(PrefsManager.instance.getString('app_settings'), before);
  });
}
