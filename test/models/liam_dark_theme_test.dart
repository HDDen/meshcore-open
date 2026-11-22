import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/liam_dark_theme.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/custom_theme.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('built-in Liam exactly matches its bundled JSONL source', () async {
    final source = await rootBundle.loadString(
      'assets/themes/meshcore-liam-dark/meshcore-liam-dark.jsonl',
    );
    final theme = CustomTheme.presetById(liamDarkThemeId)!;
    expect(jsonDecode(theme.toShareCode()), jsonDecode(source.trim()));
    expect(CustomTheme.presets.first, same(theme));
    expect(theme.isPreset, isTrue);
    expect(CustomTheme.presets[1].id, 'preset:forest');
  });

  test('fresh settings choose Liam; existing settings keep their choice', () {
    expect(AppSettings().activeThemeId, liamDarkThemeId);
    expect(AppSettings().copyWith().activeThemeId, liamDarkThemeId);
    expect(AppSettings.fromJson(AppSettings().toJson()).activeThemeId, liamDarkThemeId);
    // Old stock settings omitted the active_theme_id key entirely.
    expect(AppSettings.fromJson({}).activeThemeId, isNull);
    for (final id in [null, 'preset:forest', 'custom:user-theme']) {
      final settings = AppSettings.fromJson({'active_theme_id': id});
      expect(settings.activeThemeId, id);
      expect(AppSettings.fromJson(settings.toJson()).activeThemeId, id);
    }
  });

  test('first launch selects Liam and stock selection survives reopening', () async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    addTearDown(PrefsManager.reset);
    final service = AppSettingsService();
    addTearDown(service.dispose);
    await service.loadSettings();
    expect(service.activeCustomTheme?.id, liamDarkThemeId);
    expect(service.settings.customThemes, isEmpty);
    await service.setActiveTheme(null);
    final reopened = AppSettingsService();
    addTearDown(reopened.dispose);
    await reopened.loadSettings();
    expect(reopened.activeCustomTheme, isNull);
    await reopened.setActiveTheme(liamDarkThemeId);
    expect(reopened.settings.senderNameScalePercent, 130);
    expect(reopened.settings.hideChannelIndexIndicator, isTrue);
    expect(reopened.settings.customThemes, isEmpty);
  });
}
