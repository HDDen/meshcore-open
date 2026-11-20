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
    this.showChannelIndices,
    this.separateIncomingMetadata = false,
    this.separateOutgoingMetadata = false,
    int incomingSenderNameBrightness = 0,
    int incomingMetadataSpacing = 0,
    int incomingMetadataTopPadding = 0,
    int outgoingMetadataTopPadding = 0,
  }) : _incomingSenderNameBrightness = incomingSenderNameBrightness,
       _incomingMetadataSpacing = incomingMetadataSpacing,
       _incomingMetadataTopPadding = incomingMetadataTopPadding,
       _outgoingMetadataTopPadding = outgoingMetadataTopPadding;

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
    'incoming_metadata_background',
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
    'outgoing_metadata_background',
    'chats_border',
    'chats_background',
    'chats_title',
    'chats_preview',
    'chats_icons',
    'chats_index_border',
    'chats_index_background',
    'chats_index_text',
    'chats_index_dot',
    'chats_unread_background',
    'chats_unread_text',
    'chats_search_border',
    'chats_search_background',
    'chats_search_contacts_background',
    'chats_search_text',
    'chats_search_hint_icons',
    'chats_key',
    'chats_prefix_border',
    'chats_prefix_background',
    'chats_prefix_text',
  ];
  final Map<String, Color> colors;
  final int? uiScalePercent;
  final int? senderNameScalePercent;
  final bool? simplifiedMentions;
  final bool? showChannelIndices;
  final bool separateIncomingMetadata;
  final bool separateOutgoingMetadata;

  bool separateMetadataFor(bool outgoing) =>
      outgoing ? separateOutgoingMetadata : separateIncomingMetadata;
  final int _incomingSenderNameBrightness;
  final int _incomingMetadataSpacing;
  final int _incomingMetadataTopPadding;
  final int _outgoingMetadataTopPadding;

  static const maxMetadataTopPadding = 40;

  int get incomingMetadataTopPadding =>
      _incomingMetadataTopPadding.clamp(0, maxMetadataTopPadding).toInt();
  int get outgoingMetadataTopPadding =>
      _outgoingMetadataTopPadding.clamp(0, maxMetadataTopPadding).toInt();

  /// Stored values are retained while disabled, but do not change layout.
  int metadataTopPaddingFor(bool outgoing) => !separateMetadataFor(outgoing)
      ? 0 : (outgoing ? outgoingMetadataTopPadding : incomingMetadataTopPadding);

  static const maxIncomingMetadataSpacing = 40;

  /// Total additional gap in logical pixels; rendered as two equal halves.
  int get incomingMetadataSpacing =>
      _incomingMetadataSpacing.clamp(0, maxIncomingMetadataSpacing).toInt();

  /// Explicit sender ink wins and discards any previous brightness adjustment.
  int get incomingSenderNameBrightness => colors.containsKey('incoming_sender_name')
      ? 0 : _incomingSenderNameBrightness.clamp(-100, 100).toInt();

  bool get isEmpty => colors.isEmpty && uiScalePercent == null &&
      senderNameScalePercent == null && simplifiedMentions == null && showChannelIndices == null &&
      incomingSenderNameBrightness == 0 && incomingMetadataSpacing == 0 &&
      !separateIncomingMetadata && !separateOutgoingMetadata &&
      incomingMetadataTopPadding == 0 && outgoingMetadataTopPadding == 0;

  McoaThemeOptions copyWith({
    Map<String, Color>? colors,
    int? uiScalePercent,
    int? senderNameScalePercent,
    bool? simplifiedMentions,
    bool? showChannelIndices,
    bool? separateIncomingMetadata,
    bool? separateOutgoingMetadata,
    int? incomingSenderNameBrightness,
    int? incomingMetadataSpacing,
    int? incomingMetadataTopPadding,
    int? outgoingMetadataTopPadding,
  }) => McoaThemeOptions(
    colors: colors == null ? this.colors : Map.unmodifiable(colors),
    uiScalePercent: uiScalePercent ?? this.uiScalePercent,
    senderNameScalePercent: senderNameScalePercent ?? this.senderNameScalePercent,
    simplifiedMentions: simplifiedMentions ?? this.simplifiedMentions,
    showChannelIndices: showChannelIndices ?? this.showChannelIndices,
    separateIncomingMetadata: separateIncomingMetadata ?? this.separateIncomingMetadata,
    separateOutgoingMetadata: separateOutgoingMetadata ?? this.separateOutgoingMetadata,
    incomingSenderNameBrightness: incomingSenderNameBrightness ?? this.incomingSenderNameBrightness,
    incomingMetadataSpacing: incomingMetadataSpacing ?? this.incomingMetadataSpacing,
    incomingMetadataTopPadding: incomingMetadataTopPadding ?? this.incomingMetadataTopPadding,
    outgoingMetadataTopPadding: outgoingMetadataTopPadding ?? this.outgoingMetadataTopPadding,
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
    if (incomingMetadataTopPadding != 0)
      'incoming_metadata_top_padding': incomingMetadataTopPadding,
    if (outgoingMetadataTopPadding != 0)
      'outgoing_metadata_top_padding': outgoingMetadataTopPadding,
    if (separateIncomingMetadata) 'separate_incoming_metadata': true,
    if (separateOutgoingMetadata) 'separate_outgoing_metadata': true,
    if (incomingMetadataSpacing != 0)
      'incoming_metadata_spacing': incomingMetadataSpacing,
    if (incomingSenderNameBrightness != 0)
      'incoming_sender_name_brightness': incomingSenderNameBrightness,
    if (colors.isNotEmpty)
      'colors': {for (final key in colorKeys) if (colors[key] != null) key: hex(colors[key]!)},
    if (uiScalePercent != null || senderNameScalePercent != null ||
        simplifiedMentions != null || showChannelIndices != null)
      'preferences': {
        'ui_scale_percent': ?uiScalePercent,
        'sender_name_scale_percent': ?senderNameScalePercent,
        'simplified_mentions': ?simplifiedMentions,
        'show_channel_indices': ?showChannelIndices,
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
    int metadataPadding(String key) {
      final value = raw[key];
      return value is int && value >= 0 && value <= maxMetadataTopPadding ? value : 0;
    }
    return McoaThemeOptions(
      incomingMetadataTopPadding: metadataPadding('incoming_metadata_top_padding'),
      outgoingMetadataTopPadding: metadataPadding('outgoing_metadata_top_padding'),
      colors: Map.unmodifiable(colors),
      separateIncomingMetadata: raw['separate_incoming_metadata'] == true,
      separateOutgoingMetadata: raw['separate_outgoing_metadata'] == true,
      incomingMetadataSpacing: raw['incoming_metadata_spacing'] is int &&
              (raw['incoming_metadata_spacing'] as int) >= 0 &&
              (raw['incoming_metadata_spacing'] as int) <= maxIncomingMetadataSpacing
          ? raw['incoming_metadata_spacing'] as int : 0,
      incomingSenderNameBrightness: raw['incoming_sender_name_brightness'] is int &&
              (raw['incoming_sender_name_brightness'] as int) >= -100 &&
              (raw['incoming_sender_name_brightness'] as int) <= 100
          ? raw['incoming_sender_name_brightness'] as int : 0,
      uiScalePercent: percent('ui_scale_percent', 50, 200),
      senderNameScalePercent: percent('sender_name_scale_percent', 25, 400),
      showChannelIndices: pref('show_channel_indices') is bool
          ? pref('show_channel_indices') as bool : null,
      simplifiedMentions: pref('simplified_mentions') is bool
          ? pref('simplified_mentions') as bool : null,
    );
  }

  @override
  bool operator ==(Object other) => other is McoaThemeOptions &&
      mapEquals(colors, other.colors) && uiScalePercent == other.uiScalePercent &&
      senderNameScalePercent == other.senderNameScalePercent &&
      simplifiedMentions == other.simplifiedMentions &&
      showChannelIndices == other.showChannelIndices &&
      incomingSenderNameBrightness == other.incomingSenderNameBrightness &&
      incomingMetadataSpacing == other.incomingMetadataSpacing &&
      separateIncomingMetadata == other.separateIncomingMetadata &&
      separateOutgoingMetadata == other.separateOutgoingMetadata &&
      incomingMetadataTopPadding == other.incomingMetadataTopPadding &&
      outgoingMetadataTopPadding == other.outgoingMetadataTopPadding;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(colors.entries.map((e) => Object.hash(e.key, e.value))),
    uiScalePercent, senderNameScalePercent, simplifiedMentions, incomingSenderNameBrightness,
    incomingMetadataSpacing, separateIncomingMetadata, separateOutgoingMetadata,
    incomingMetadataTopPadding, outgoingMetadataTopPadding, showChannelIndices,
  );
}
