import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/theme_media.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/chat_background.dart';
import 'package:meshcore_open/models/custom_theme.dart';
import 'package:meshcore_open/theme/theme_icons.dart';
import 'package:meshcore_open/utils/theme_file.dart';

const _forest = CustomTheme(
  id: 'custom:forest',
  name: 'Forest',
  background: Color(0xFF0E1A13),
  accent: Color(0xFF4ADE80),
);

void main() {
  test('U19a: upstream share JSON preserves colors, known slots and the background', () {
    final theme = CustomTheme.fromShareCode(
      jsonEncode({
        'id': 'foreign-id',
        'name': ' Лес ',
        'background': '#abc',
        'accent': '4ADE80',
        'icons': {
          'map': {'icon': 'park'},
          'send': {'image': 'AQID'},
          'contacts': {'asset': 'assets/themes/christmas/contacts.jxl'},
          'channels': {'icon': 'unknown'},
          'map_room': {'asset': 'assets/themes/../outside.jxl'},
          'unknownSlot': {'icon': 'home'},
        },
        'chatBackground': {'color': '#123', 'fade': 2},
        'chatBackgroundEverywhere': true,
      }),
      newId: 'custom:local',
    )!;
    expect(theme.id, 'custom:local');
    expect(theme.name, 'Лес');
    expect(theme.background, const Color(0xFFAABBCC));
    expect(theme.accent, _forest.accent);
    expect(theme.icons.keys, unorderedEquals(['map', 'send', 'contacts']));
    expect(theme.icons['map']!.icon, 'park');
    expect(theme.icons['contacts']!.asset, 'assets/themes/christmas/contacts.jxl');
    final bytes = theme.icons['send']!.imageBytes;
    expect(bytes, [1, 2, 3]);
    expect(theme.icons['send']!.imageBytes, same(bytes));
    expect(theme.chatBackground!.color, const Color(0xFF112233));
    expect(theme.chatBackground!.fade, ChatBackground.maxFade);
    expect(theme.chatBackgroundEverywhere, isTrue);
    expect(CustomTheme.fromShareCode(theme.toShareCode(), newId: theme.id), theme);
    expect(jsonDecode(theme.toShareCode()), isNot(contains('id')));
  });

  test('U19a: inline pictures round-trip in exchange and saved themes reference their store', () {
    final imported = CustomTheme.fromShareCode(
      jsonEncode({
        'name': 'With picture',
        'background': '#112233',
        'accent': '#AABBCC',
        'chatBackground': {'imageData': 'AQID', 'fade': 0.6},
      }),
      newId: 'custom:picture',
    )!;
    expect(imported.chatBackground!.inlineImage, [1, 2, 3]);
    expect(imported.canSave, isFalse);
    final decodedAgain = CustomTheme.fromShareCode(imported.toShareCode(), newId: 'custom:copy')!;
    expect(decodedAgain.chatBackground!.inlineImage, [1, 2, 3]);

    final saved = imported.copyWith(
      chatBackground: imported.chatBackground!.withStoredImage('local-picture'),
    );
    expect(saved.canSave, isTrue);
    expect(saved.toJson()['chat_background'], {'image': 'local-picture', 'fade': 0.6});
    expect(CustomTheme.fromJson(saved.toJson()), saved);
    expect(jsonDecode(saved.toShareCode()), isNot(contains('chatBackground')));
    final hydrated = saved.copyWith(
      chatBackground: saved.chatBackground!.withInlineImage(Uint8List.fromList([1, 2, 3])),
    );
    final share = jsonDecode(hydrated.toShareCode()) as Map<String, dynamic>;
    expect(share['chatBackground'], {'imageData': 'AQID', 'fade': 0.6});

    final foreignReference = CustomTheme.fromShareCode(
      jsonEncode({...share, 'chatBackground': {'image': 'other-device'}}),
      newId: 'custom:foreign',
    );
    expect(foreignReference!.chatBackground, isNull);
    expect(ChatBackground.fromJson({'image': '../escape'}), isNull);
    expect(ChatBackground.fromJson({'imageData': 'AQID'}), isNull);
  });

  test('U19a: malformed theme entries leave legacy settings and valid themes readable', () {
    final loaded = AppSettings.fromJson({
      'theme_mode': 'light',
      'ui_scale': 1.4,
      'language_override': 'ru',
      'custom_themes': [
        {'id': 7, 'name': 'Bad ID'},
        {'id': 'custom:bad', 'name': false},
        {'id': 'preset:forest', 'name': 'Imposter'},
        _forest.toJson(),
        _forest.copyWith(name: 'Duplicate ID').toJson(),
        null,
      ],
      'active_theme_id': false,
    });
    expect(loaded.customThemes, [_forest]);
    expect(loaded.activeThemeId, isNull);
    expect(loaded.themeMode, 'light');
    expect(loaded.uiScale, 1.4);
    expect(loaded.languageOverride, 'ru');
    final active = loaded.copyWith(activeThemeId: _forest.id);
    expect(AppSettings.fromJson(active.toJson()).activeThemeId, _forest.id);
    expect(active.copyWith(activeThemeId: null).activeThemeId, isNull);
    expect(AppSettings.fromJson({'custom_themes': false}).customThemes, isEmpty);
  });

  test('U19a: invalid and oversized image payloads do not become overrides', () {
    expect(ThemeIconOverride.fromJson({'image': '###'}), isNull);
    expect(ThemeIconOverride.fromJson({'image': 'AZ=='}), isNull);
    expect(ThemeIconOverride.fromJson({'image': 'AQJ='}), isNull);
    final oversized = base64Encode(Uint8List(maxThemeIconBytes + 1));
    expect(ThemeIconOverride.fromJson({'image': oversized}), isNull);
    final allowed = ThemeIconOverride.fromJson({
      'image': base64Encode(Uint8List(maxThemeIconBytes)),
    });
    expect(allowed!.imageBytes, hasLength(maxThemeIconBytes));
    expect(parseHexColor('#-12345'), isNull);
  });

  test('U19a: JSONL skips malformed lines and gives each valid theme a fresh ID', () {
    final second = _forest.copyWith(id: 'custom:second', name: 'Океан');
    final encoded = encodeThemesJsonl([_forest, second]);
    var id = 0;
    final themes = decodeThemesJsonl(
      'invalid\n\n$encoded',
      newId: () => 'custom:import-${++id}',
    );
    expect(id, 2);
    expect(themes, [
      _forest.copyWith(id: 'custom:import-1'),
      second.copyWith(id: 'custom:import-2'),
    ]);
    final pretty = const JsonEncoder.withIndent('  ').convert(jsonDecode(_forest.toShareCode()));
    expect(
      decodeThemesJsonl(pretty, newId: () => 'custom:pretty'),
      [_forest.copyWith(id: 'custom:pretty')],
    );
    expect(themeFileStem('../Forest / Theme'), 'forest-theme');
  });

  test('U19a: a JSONL batch over the supported count is rejected as a whole', () {
    final themes = List.filled(CustomTheme.maxSavedThemes + 1, _forest);
    expect(() => encodeThemesJsonl(themes), throwsFormatException);
    final raw = themes.map((theme) => theme.toShareCode()).join('\n');
    expect(decodeThemesJsonl(raw, newId: () => 'custom:import'), isEmpty);
  });
}
