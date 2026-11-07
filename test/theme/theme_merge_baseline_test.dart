import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/readable_accent.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel_group.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('U19a baseline: old settings use the system theme and stock scale', () {
    final settings = AppSettings.fromJson({});
    expect(settings.themeMode, 'system');
    expect(settings.uiScale, 1.0);
    expect(settings.uiScaleApplyToIcons, isTrue);
  });

  test('U19a baseline: appearance edits round-trip through preferences', () async {
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode({
        'theme_mode': 'dark',
        'ui_scale': 1.35,
        'ui_scale_apply_to_icons': false,
        'language_override': 'ru',
        'public_ipfs_gateway': 'https://chosen.example/ipfs/',
        'load_link_images': false,
      }),
    });
    PrefsManager.reset();
    addTearDown(PrefsManager.reset);
    await PrefsManager.initialize();
    final service = AppSettingsService();
    final reopened = AppSettingsService();
    addTearDown(service.dispose);
    addTearDown(reopened.dispose);

    await service.loadSettings();
    expect(service.settings.themeMode, 'dark');
    expect(service.settings.uiScale, 1.35);
    expect(service.settings.uiScaleApplyToIcons, isFalse);

    await service.setThemeMode('light');
    await service.setUiScale(1.5);
    await service.setUiScaleApplyToIcons(true);
    await reopened.loadSettings();
    expect(reopened.settings.themeMode, 'light');
    expect(reopened.settings.uiScale, 1.5);
    expect(reopened.settings.uiScaleApplyToIcons, isTrue);
    expect(reopened.settings.languageOverride, 'ru');
    expect(reopened.settings.publicIpfsGateway, 'https://chosen.example/ipfs/');
    expect(reopened.settings.loadLinkImages, isFalse);

    await reopened.setThemeMode('system');
    await service.loadSettings();
    expect(service.settings.themeMode, 'system');
    expect(service.settings.uiScale, 1.5);
    expect(service.settings.languageOverride, 'ru');
  });

  for (final preset in [
    (
      brightness: Brightness.dark,
      theme: MeshTheme.dark,
      surface: const Color(0xFF0B1220),
      accent: const Color(0xFF0EA5E9),
      ink: const Color(0xFFF8FAFC),
    ),
    (
      brightness: Brightness.light,
      theme: MeshTheme.light,
      surface: const Color(0xFFF4F6F8),
      accent: const Color(0xFF2F6EA8),
      ink: const Color(0xFF10161B),
    ),
  ]) {
    test('U19a baseline: stock ${preset.brightness.name} palette and fonts', () {
      final theme = preset.theme();
      final scheme = theme.colorScheme;
      expect(theme.brightness, preset.brightness);
      expect(scheme.surface, preset.surface);
      expect(scheme.primary, preset.accent);
      expect(scheme.onSurface, preset.ink);
      expect(theme.scaffoldBackgroundColor, preset.surface);
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(theme.textTheme.bodyMedium?.fontFamilyFallback, contains('Noto Sans'));
      expect(meshContrastRatio(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(4.5));

      final navigation = theme.navigationBarTheme;
      expect(navigation.backgroundColor, preset.surface);
      expect(navigation.indicatorColor, preset.accent);
      expect(navigation.labelTextStyle?.resolve({WidgetState.selected})?.color,
          scheme.onPrimary);
      expect(navigation.labelTextStyle?.resolve({})?.color, scheme.onSurfaceVariant);
    });
  }

  test('U19a baseline: channel folders keep their own colors and ordering', () {
    final folder = ChannelGroup.fromJson({
      'name': 'Local folder',
      'channel_names': ['Alpha', 'Beta'],
      'sort_order': 3,
      'widget_color': 0xFF123456,
      'widget_text_color': 0xFFE5F0FA,
      'allow_ordering_in_group': true,
    });
    final renamed = ChannelGroup.fromJson(folder.copyWith(name: 'Renamed').toJson());
    expect(renamed.name, 'Renamed');
    expect(renamed.channelNames, ['Alpha', 'Beta']);
    expect(renamed.sortOrder, 3);
    expect(renamed.widgetColor, 0xFF123456);
    expect(renamed.widgetTextColor, 0xFFE5F0FA);
    expect(renamed.allowOrderingInGroup, isTrue);
  });
}
