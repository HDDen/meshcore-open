import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoa_theme_options.dart';
import 'package:meshcore_open/helpers/mcoa_theme_preferences.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/custom_theme.dart';

void main() {
  test('all chat palette slots survive storage and sharing', () {
    final keys = McoaThemeOptions.colorKeys.where((key) => key.startsWith('chats_')).toList();
    expect(keys, hasLength(20));
    final colors = {for (var i = 0; i < keys.length; i++) keys[i]: Color(0x80112233 + i)};
    final options = McoaThemeOptions(colors: colors, showChannelIndices: false);
    final sample = CustomTheme(
      id: 'list', name: 'List', background: const Color(0xFF101010),
      accent: const Color(0xFF3355FF), mcoa: options,
    );
    expect(McoaThemeOptions.fromJson(options.toJson()), options);
    expect(CustomTheme.fromJson(sample.toJson()), sample);
    expect(CustomTheme.fromShareCode(sample.toShareCode(), newId: sample.id), sample);
    expect(options.copyWith(showChannelIndices: true).colors, colors);
    expect(McoaThemeOptions.fromJson({'version': 1}).showChannelIndices, isNull);
  });

  test('channel indices preference applies only on explicit activation', () {
    for (final hidden in [false, true]) {
      final original = AppSettings(hideChannelIndexIndicator: hidden);
      expect(applyMcoaThemePreferences(original, const McoaThemeOptions()).hideChannelIndexIndicator, hidden);
      for (final shown in [false, true]) {
        final applied = applyMcoaThemePreferences(original, McoaThemeOptions(showChannelIndices: shown));
        expect(applied.hideChannelIndexIndicator, !shown);
        expect(original.hideChannelIndexIndicator, hidden);
        final manuallyChanged = applied.copyWith(hideChannelIndexIndicator: shown);
        expect(manuallyChanged.hideChannelIndexIndicator, shown);
        expect(McoaThemeOptions.fromJson(McoaThemeOptions(showChannelIndices: shown).toJson()).showChannelIndices, shown);
      }
    }
  });

  test('metadata backgrounds and retained padding survive storage and sharing', () {
    const options = McoaThemeOptions(
      colors: {
        'incoming_metadata_background': Color(0xCC112233),
        'outgoing_metadata_background': Color(0xFF334455),
      },
      incomingMetadataTopPadding: 9, outgoingMetadataTopPadding: 17,
    );
    expect(options.metadataTopPaddingFor(false), 0);
    expect(options.metadataTopPaddingFor(true), 0);
    final enabled = options.copyWith(separateIncomingMetadata: true, separateOutgoingMetadata: true);
    expect(enabled.metadataTopPaddingFor(false), 9);
    expect(enabled.metadataTopPaddingFor(true), 17);
    expect(enabled.copyWith(separateIncomingMetadata: false).incomingMetadataTopPadding, 9);
    expect(enabled.copyWith(incomingMetadataTopPadding: 0).outgoingMetadataTopPadding, 17);
    const theme = CustomTheme(
      id: 'metadata', name: 'Metadata', background: Color(0xFF101010),
      accent: Color(0xFF3355FF), mcoa: options,
    );
    expect(CustomTheme.fromJson(theme.toJson()), theme);
    expect(CustomTheme.fromShareCode(theme.toShareCode(), newId: theme.id), theme);
    expect(McoaThemeOptions.fromJson(enabled.toJson()), enabled);
    expect(options.toJson(), isNot(contains('preferences')));
    for (final raw in <Object?>[null, -1, 41, '10', 1.5]) {
      final decoded = McoaThemeOptions.fromJson({
        'version': 1, 'incoming_metadata_top_padding': raw,
        'outgoing_metadata_top_padding': raw,
      });
      expect(decoded.incomingMetadataTopPadding, 0);
      expect(decoded.outgoingMetadataTopPadding, 0);
    }
    expect(const McoaThemeOptions(incomingMetadataTopPadding: 100).incomingMetadataTopPadding, 40);
    expect(const McoaThemeOptions(outgoingMetadataTopPadding: -1).outgoingMetadataTopPadding, 0);
    expect(const McoaThemeOptions().toJson(), isNot(contains('incoming_metadata_top_padding')));
    expect(const McoaThemeOptions().toJson(), isNot(contains('outgoing_metadata_top_padding')));
  });

  test('incoming and outgoing separation are independent and survive sharing', () {
    for (final incoming in [false, true]) {
      for (final outgoing in [false, true]) {
        final options = McoaThemeOptions(
          separateIncomingMetadata: incoming, separateOutgoingMetadata: outgoing,
        );
        expect(options.separateMetadataFor(false), incoming);
        expect(options.separateMetadataFor(true), outgoing);
        expect(options.isEmpty, !incoming && !outgoing);
        expect(McoaThemeOptions.fromJson(options.toJson()), options);
        expect(options.copyWith(separateOutgoingMetadata: !outgoing).separateIncomingMetadata, incoming);
        expect(options.copyWith(separateIncomingMetadata: !incoming).separateOutgoingMetadata, outgoing);
        final theme = CustomTheme(
          id: 'directions', name: 'Directions', background: const Color(0xFF101010),
          accent: const Color(0xFF3355FF), mcoa: options,
        );
        expect(CustomTheme.fromJson(theme.toJson()), theme);
        expect(CustomTheme.fromShareCode(theme.toShareCode(), newId: theme.id), theme);
      }
    }
    expect(const McoaThemeOptions().toJson(), isNot(contains('separate_outgoing_metadata')));
    for (final raw in <Object?>[null, false, 'true', 1]) {
      expect(McoaThemeOptions.fromJson({
        'version': 1, 'separate_outgoing_metadata': raw,
      }).separateOutgoingMetadata, isFalse);
    }
  });

  test('separate metadata defaults off and survives theme storage and sharing', () {
    const plain = McoaThemeOptions();
    expect(plain.separateIncomingMetadata, isFalse);
    expect(plain.toJson(), isNot(contains('separate_incoming_metadata')));
    final split = plain.copyWith(separateIncomingMetadata: true);
    expect(split.isEmpty, isFalse);
    expect(split.toJson()['separate_incoming_metadata'], isTrue);
    expect(split.toJson(), isNot(contains('preferences')));
    expect(McoaThemeOptions.fromJson(split.toJson()), split);
    expect(split.copyWith(separateIncomingMetadata: false), plain);
    const sample = CustomTheme(
      id: 'split', name: 'Split', background: Color(0xFF101010),
      accent: Color(0xFF3355FF), mcoa: McoaThemeOptions(separateIncomingMetadata: true),
    );
    expect(CustomTheme.fromJson(sample.toJson()), sample);
    expect(CustomTheme.fromShareCode(sample.toShareCode(), newId: sample.id), sample);
    for (final value in <Object?>[null, false, 'true', 1]) {
      expect(McoaThemeOptions.fromJson({
        'version': 1, 'separate_incoming_metadata': value,
      }).separateIncomingMetadata, isFalse);
    }
  });

  test('metadata spacing survives storage and sharing without preferences', () {
    const spacing = McoaThemeOptions(incomingMetadataSpacing: 21);
    const sample = CustomTheme(
      id: 'spacing', name: 'Spacing',
      background: Color(0xFF101010), accent: Color(0xFF3355FF),
      mcoa: spacing,
    );
    expect(spacing.isEmpty, isFalse);
    expect(spacing.toJson()['incoming_metadata_spacing'], 21);
    expect(spacing.toJson(), isNot(contains('preferences')));
    expect(CustomTheme.fromJson(sample.toJson()), sample);
    expect(CustomTheme.fromShareCode(sample.toShareCode(), newId: sample.id), sample);
    expect(spacing.copyWith(incomingMetadataSpacing: 0).isEmpty, isTrue);
    expect(spacing.copyWith().incomingMetadataSpacing, 21);
    expect(const McoaThemeOptions().toJson(), isNot(contains('incoming_metadata_spacing')));
  });

  test('legacy and malformed metadata spacing use the unchanged layout', () {
    expect(McoaThemeOptions.fromJson({'version': 1}).incomingMetadataSpacing, 0);
    for (final value in <Object?>[-1, 41, '20', 1.5, null]) {
      expect(McoaThemeOptions.fromJson({
        'version': 1, 'incoming_metadata_spacing': value,
      }).incomingMetadataSpacing, 0);
    }
    expect(const McoaThemeOptions(incomingMetadataSpacing: -10).incomingMetadataSpacing, 0);
    expect(const McoaThemeOptions(incomingMetadataSpacing: 100).incomingMetadataSpacing, 40);
  });

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

  test('name brightness without color overrides survives theme storage and exchange', () {
    final adjusted = theme.copyWith(mcoa: const McoaThemeOptions(incomingSenderNameBrightness: -40));
    expect(CustomTheme.fromJson(adjusted.toJson()), adjusted);
    expect(CustomTheme.fromShareCode(adjusted.toShareCode(), newId: adjusted.id), adjusted);
  });

  test('MCOa colors, alpha and preferences survive storage and sharing', () {
    expect(CustomTheme.fromJson(theme.toJson()), theme);
    expect(CustomTheme.fromShareCode(theme.toShareCode(), newId: theme.id), theme);
    expect(AppSettings.fromJson(AppSettings(customThemes: [theme]).toJson())
        .customThemes.single, theme);
    expect(options.toJson()['version'], 1);
    expect(McoaThemeOptions.colorKeys, hasLength(65));
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
