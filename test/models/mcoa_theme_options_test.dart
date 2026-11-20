import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoa_theme_options.dart';
import 'package:meshcore_open/helpers/mcoa_theme_preferences.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/custom_theme.dart';

void main() {
  test('sender name colors never change the global monochrome preference', () {
    for (final monochrome in [false, true]) {
      final settings = AppSettings(monochromeSenderNames: monochrome);
      for (final colors in <Map<String, Color>>[
        {}, {'incoming_sender_name': const Color(0xFFAA55BB)},
      ]) {
        final applied = applyMcoaThemePreferences(settings, McoaThemeOptions(colors: colors));
        expect(applied.monochromeSenderNames, monochrome);
        expect(settings.monochromeSenderNames, monochrome);
      }
    }
  });

  const options = McoaThemeOptions(
    colors: {
      'status_bar': Color(0xFF010203),
      'incoming_quote_background': Color(0x80445566),
      'outgoing_mention_text': Color(0xFFCC1122),
      'composer_input_background': Color(0xFF223344),
      'composer_counter_error': Color(0xFFCC3344),
      'outgoing_hop_border': Color(0xFF336699),
      'incoming_sender_name': Color(0xFFAA55BB),
      'incoming_link': Color(0xFF11AA77),
      'outgoing_signal': Color(0xFF7755AA),
    },
    uiScalePercent: 125,
    senderNameScalePercent: 113,
    simplifiedMentions: true,
  );
  const theme = CustomTheme(
    id: 'custom:mcoa',
    name: 'MCOa',
    background: Color(0xFF101010),
    accent: Color(0xFF3355FF),
    mcoa: options,
  );

  test('MCOa colors, alpha and preferences survive storage and sharing', () {
    expect(CustomTheme.fromJson(theme.toJson()), theme);
    expect(CustomTheme.fromShareCode(theme.toShareCode(), newId: theme.id), theme);
    expect(AppSettings.fromJson(AppSettings(customThemes: [theme]).toJson())
        .customThemes.single, theme);
    expect(options.toJson()['version'], 1);
    expect(McoaThemeOptions.colorKeys, hasLength(43));
    expect(McoaThemeOptions.fromJson(options.toJson()), options);
    expect(theme.sameContent(theme.copyWith(mcoa: const McoaThemeOptions())), isFalse);
    final upstream = jsonDecode(theme.toShareCode()) as Map<String, dynamic>;
    upstream.remove('mcoa');
    final plain = CustomTheme.fromShareCode(jsonEncode(upstream), newId: theme.id)!;
    expect(plain.background, theme.background);
    expect(plain.accent, theme.accent);
    expect(plain.mcoa.isEmpty, isTrue);
  });

  test('missing, future and malformed fields preserve legacy defaults', () {
    expect(McoaThemeOptions.fromJson(null).isEmpty, isTrue);
    expect(McoaThemeOptions.fromJson({'version': 2, 'colors': options.colors}).isEmpty, isTrue);
    final decoded = McoaThemeOptions.fromJson({
      'version': 1,
      'colors': {'incoming_text': '#010203', 'header': 'invalid', 'unknown': '#112233'},
      'preferences': {
        'ui_scale_percent': 0,
        'sender_name_scale_percent': 1000,
        'simplified_mentions': 'true',
        'monochrome_sender_names': false,
      },
    });
    expect(decoded.colors, {'incoming_text': const Color(0xFF010203)});
    expect(decoded.uiScalePercent, isNull);
    expect(decoded.senderNameScalePercent, isNull);
    expect(decoded.simplifiedMentions, isNull);
    // Removed preferences from older MCOa themes no longer affect the app.
    expect(decoded.toJson(), isNot(contains('preferences')));
  });
}
