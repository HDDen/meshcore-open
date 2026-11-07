import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koni_jxl_flutter/koni_jxl_flutter.dart';
import 'package:meshcore_open/models/custom_theme.dart';
import 'package:meshcore_open/models/holiday_schedule.dart';
import 'package:meshcore_open/theme/theme_icons.dart';

void main() {
  test('U19c: every holiday asset is declared in all build profiles', () {
    const profiles = [
      'pubspec.yaml',
      'pubspec.full.yaml',
      'pubspec.lite.yaml',
      'pubspec.lite-aeic.yaml',
    ];
    final manifests = profiles.map((path) => File(path).readAsStringSync()).toList();
    final assets = <String>{};
    for (final holiday in ThemeHoliday.values) {
      final theme = CustomTheme.presetById(holiday.themeId)!;
      expect(theme.isPreset, isTrue);
      final paths = [
        theme.chatBackground!.asset!,
        for (final icon in theme.icons.values) icon.asset!,
      ];
      expect(paths, hasLength(10), reason: theme.name);
      for (final path in paths) {
        expect(assets.add(path), isTrue);
        expect(isThemeAssetPath(path), isTrue);
        expect(looksLikeJxl(File(path).readAsBytesSync()), isTrue, reason: path);
        final dir = path.substring(0, path.lastIndexOf('/') + 1);
        for (var i = 0; i < profiles.length; i++) {
          expect(manifests[i], contains('- $dir'), reason: profiles[i]);
        }
      }
      final copy = CustomTheme.fromShareCode(theme.toShareCode(), newId: 'copy')!;
      expect(copy.chatBackground, theme.chatBackground);
      expect(copy.icons, theme.icons);
    }
    expect(assets, hasLength(40));
  });
}
