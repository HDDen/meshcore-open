import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'mcoa_theme_extension.dart';

/// Optional MCOa data; absence means inherit the ordinary theme/preferences.
@immutable
class McoaThemeOptions {
  const McoaThemeOptions({
    this.colors = const {},
    this.uiScalePercent,
    this.senderNameScalePercent,
    this.simplifiedMentions,
  });

  static const colorKeys = [
    'status_bar',
    'header',
    'header_text',
    'composer_background',
    'composer_action_icon',
    'composer_input_border',
    'composer_input_background',
    'composer_input_hint',
    'composer_input_text',
    'composer_send_background',
    'composer_send_icon',
    'composer_counter',
    'composer_counter_warning',
    'composer_counter_error',
    'incoming_border',
    'incoming_background',
    'incoming_sender_name',
    'incoming_text',
    'incoming_badges',
    'incoming_quote_background',
    'incoming_quote_text',
    'incoming_mention_border',
    'incoming_mention_background',
    'incoming_mention_text',
    'incoming_hop_border',
    'incoming_hop_background',
    'incoming_hop_text',
    'incoming_link',
    'incoming_signal',
    'outgoing_border',
    'outgoing_background',
    'outgoing_text',
    'outgoing_badges',
    'outgoing_quote_background',
    'outgoing_quote_text',
    'outgoing_mention_border',
    'outgoing_mention_background',
    'outgoing_mention_text',
    'outgoing_hop_border',
    'outgoing_hop_background',
    'outgoing_hop_text',
    'outgoing_link',
    'outgoing_signal',
  ];
  final Map<String, Color> colors;
  final int? uiScalePercent;
  final int? senderNameScalePercent;
  final bool? simplifiedMentions;

  bool get isEmpty => colors.isEmpty && uiScalePercent == null &&
      senderNameScalePercent == null && simplifiedMentions == null;

  McoaThemeOptions copyWith({
    Map<String, Color>? colors,
    int? uiScalePercent,
    int? senderNameScalePercent,
    bool? simplifiedMentions,
  }) => McoaThemeOptions(
    colors: colors == null ? this.colors : Map.unmodifiable(colors),
    uiScalePercent: uiScalePercent ?? this.uiScalePercent,
    senderNameScalePercent: senderNameScalePercent ?? this.senderNameScalePercent,
    simplifiedMentions: simplifiedMentions ?? this.simplifiedMentions,
  );

  static String hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  static Color? parseColor(Object? raw) {
    if (raw is! String || !RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(raw)) {
      return null;
    }
    final value = int.tryParse(raw.substring(1), radix: 16);
    return value == null ? null : Color(raw.length == 7 ? 0xff000000 | value : value);
  }

  Map<String, Object> toJson() => {
    ...mcoaThemeExtension,
    if (colors.isNotEmpty)
      'colors': {for (final key in colorKeys) if (colors[key] != null) key: hex(colors[key]!)},
    if (uiScalePercent != null || senderNameScalePercent != null ||
        simplifiedMentions != null)
      'preferences': {
        'ui_scale_percent': ?uiScalePercent,
        'sender_name_scale_percent': ?senderNameScalePercent,
        'simplified_mentions': ?simplifiedMentions,
      },
  };

  static McoaThemeOptions fromJson(Object? raw) {
    if (raw is! Map || raw['version'] != mcoaThemeExtension['version']) {
      return const McoaThemeOptions();
    }
    final inputColors = raw['colors'];
    final colors = <String, Color>{};
    if (inputColors is Map) {
      for (final key in colorKeys) {
        final color = parseColor(inputColors[key]);
        if (color != null) {
          colors[key] = color;
        }
      }
    }
    final prefs = raw['preferences'];
    Object? pref(String key) => prefs is Map ? prefs[key] : null;
    int? percent(String key, int min, int max) {
      final value = pref(key);
      return value is int && value >= min && value <= max ? value : null;
    }
    return McoaThemeOptions(
      colors: Map.unmodifiable(colors),
      uiScalePercent: percent('ui_scale_percent', 50, 200),
      senderNameScalePercent: percent('sender_name_scale_percent', 25, 400),
      simplifiedMentions: pref('simplified_mentions') is bool
          ? pref('simplified_mentions') as bool : null,
    );
  }

  @override
  bool operator ==(Object other) => other is McoaThemeOptions &&
      mapEquals(colors, other.colors) && uiScalePercent == other.uiScalePercent &&
      senderNameScalePercent == other.senderNameScalePercent &&
      simplifiedMentions == other.simplifiedMentions;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(colors.entries.map((e) => Object.hash(e.key, e.value))),
    uiScalePercent, senderNameScalePercent, simplifiedMentions,
  );
}
