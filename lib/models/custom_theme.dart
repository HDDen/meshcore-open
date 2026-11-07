import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../helpers/theme_media.dart';
import '../theme/theme_icons.dart';
import 'chat_background.dart';

/// A user-made theme.
///
/// Kept deliberately small: a theme is a name plus two colors. Everything
/// else (surfaces, text, borders, chat bubbles, light vs dark) is derived
/// from those two, so anyone can make a readable theme in a few taps.
/// Optionally it swaps some app icons for other icons or small pictures.
///
/// The share code is plain JSON, so a theme can also be written by hand:
///
/// ```json
/// {"name": "Forest", "background": "#0E1A13", "accent": "#4ADE80",
///  "icons": {"map": {"icon": "park"}}}
/// ```
class CustomTheme {
  static const Object _unset = Object();
  static const int maxSavedThemes = 64;
  static const int maxSavedIconCharacters = 4 * 1024 * 1024;
  static const int maxShareCodeCharacters = 8 * 1024 * 1024;
  static const int maxNameLength = 128;
  static final _idPattern = RegExp(r'^[a-zA-Z0-9_:-]{1,128}$');

  /// Prefix for the IDs of the built-in [presets].
  static const presetIdPrefix = 'preset:';

  final String id;
  final String name;

  /// Main screen color. Its brightness decides whether the theme is light or
  /// dark.
  final Color background;

  /// Buttons, switches, links, highlights and your own chat bubbles.
  final Color accent;

  /// Replacement icons keyed by [ThemeIconSlot.key]; empty keeps defaults.
  final Map<String, ThemeIconOverride> icons;

  /// Background for chats that have none of their own.
  final ChatBackground? chatBackground;

  /// When true, [chatBackground] also replaces chats' own backgrounds.
  final bool chatBackgroundEverywhere;

  const CustomTheme({
    required this.id,
    required this.name,
    required this.background,
    required this.accent,
    this.icons = const {},
    this.chatBackground,
    this.chatBackgroundEverywhere = false,
  });

  bool get isPreset => id.startsWith(presetIdPrefix);

  /// Inline backgrounds are exchange data. Materialize the picture in the
  /// background store before saving a theme.
  bool get canSave {
    final background = chatBackground;
    final imageId = background?.imageId;
    final asset = background?.asset;
    return !isPreset &&
        _idPattern.hasMatch(id) &&
        _validName(name) &&
        (background == null || background.fade.isFinite) &&
        background?.inlineImage == null &&
        (imageId == null || isStoredThemeImageId(imageId)) &&
        (asset == null || isThemeAssetPath(asset));
  }

  int get storedIconCharacters => icons.values.fold(
    0,
    (total, icon) => total + (icon.image?.length ?? 0),
  );

  static bool _validName(String name) =>
      name.trim().isNotEmpty && name.length <= maxNameLength;

  /// True when [background] is dark enough to need light text.
  bool get isDark => isDarkColor(background);

  CustomTheme copyWith({
    String? id,
    String? name,
    Color? background,
    Color? accent,
    Map<String, ThemeIconOverride>? icons,
    Object? chatBackground = _unset,
    bool? chatBackgroundEverywhere,
  }) {
    return CustomTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      background: background ?? this.background,
      accent: accent ?? this.accent,
      icons: icons ?? this.icons,
      chatBackground: identical(chatBackground, _unset)
          ? this.chatBackground
          : chatBackground as ChatBackground?,
      chatBackgroundEverywhere:
          chatBackgroundEverywhere ?? this.chatBackgroundEverywhere,
    );
  }

  /// Storage form: chat background pictures are referenced by image-store ID.
  Map<String, dynamic> toJson() => {
    'id': id,
    ..._contentJson(),
    if (chatBackground != null) 'chat_background': chatBackground!.toJson(),
    if (chatBackgroundEverywhere) 'chat_background_everywhere': true,
  };

  Map<String, dynamic> _contentJson() => {
    'name': name,
    'background': colorToHex(background),
    'accent': colorToHex(accent),
    if (icons.isNotEmpty)
      'icons': icons.map((key, value) => MapEntry(key, value.toJson())),
  };

  factory CustomTheme.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    return CustomTheme(
      id: id is String ? id : '',
      name: name is String ? name.trim() : '',
      background: parseHexColor(json['background']) ?? const Color(0xFF0B1220),
      accent: parseHexColor(json['accent']) ?? const Color(0xFF0EA5E9),
      icons: parseThemeIcons(json['icons']),
      chatBackground: ChatBackground.fromJson(json['chat_background']),
      chatBackgroundEverywhere: json['chat_background_everywhere'] == true,
    );
  }

  /// Reads saved entries independently so one damaged theme cannot reset the
  /// rest of the application's preferences.
  static List<CustomTheme> readSavedThemes(Object? raw) {
    if (raw is! List || raw.isEmpty) return const [];
    final themes = <CustomTheme>[];
    final ids = <String>{};
    var iconCharacters = 0;
    for (final entry in raw) {
      if (themes.length == maxSavedThemes) break;
      if (entry is! Map<String, dynamic>) continue;
      final theme = CustomTheme.fromJson(entry);
      if (!theme.canSave || ids.contains(theme.id)) continue;
      final nextSize = iconCharacters + theme.storedIconCharacters;
      if (nextSize > maxSavedIconCharacters) continue;
      ids.add(theme.id);
      iconCharacters = nextSize;
      themes.add(theme);
    }
    return themes.isEmpty ? const [] : List.unmodifiable(themes);
  }

  /// Human-readable JSON for sharing (no ID). Pictures are embedded, so a
  /// theme with pictures makes a longer code. A chat background picture is
  /// only included once its bytes are attached (see
  /// `ChatBackgroundService.embedThemeImages`).
  String toShareCode() {
    final chat = chatBackground?.toShareJson();
    return jsonEncode({
      ..._contentJson(),
      'chatBackground': ?chat,
      if (chat != null && chatBackgroundEverywhere)
        'chatBackgroundEverywhere': true,
    });
  }

  /// Parses a share code. Returns null when [code] is not a valid theme.
  /// The returned theme carries [newId].
  static CustomTheme? fromShareCode(String code, {required String newId}) {
    if (code.length > maxShareCodeCharacters) return null;
    try {
      final decoded = jsonDecode(code.trim());
      if (decoded is! Map) return null;
      final name = decoded['name'];
      final background = parseHexColor(decoded['background']);
      final accent = parseHexColor(decoded['accent']);
      if (name is! String || !_validName(name.trim())) return null;
      if (background == null || accent == null) return null;
      return CustomTheme(
        id: newId,
        name: name.trim(),
        background: background,
        accent: accent,
        icons: parseThemeIcons(decoded['icons']),
        // Only colors and inline pictures: an image-store ID from another
        // device would point at nothing here.
        chatBackground: _sharedChatBackground(decoded['chatBackground']),
        chatBackgroundEverywhere: decoded['chatBackgroundEverywhere'] == true,
      );
    } on FormatException {
      return null;
    }
  }

  bool sameContent(CustomTheme other) =>
      other.name == name &&
      other.background == background &&
      other.accent == accent &&
      mapEquals(other.icons, icons) &&
      other.chatBackground == chatBackground &&
      other.chatBackgroundEverywhere == chatBackgroundEverywhere;

  @override
  bool operator ==(Object other) =>
      other is CustomTheme && other.id == id && sameContent(other);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    background,
    accent,
    Object.hashAllUnordered(
      icons.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    chatBackground,
    chatBackgroundEverywhere,
  );

  static ChatBackground? _sharedChatBackground(Object? json) {
    final background = ChatBackground.fromJson(json, allowInlineImage: true);
    if (background == null || background.imageId != null) return null;
    return background;
  }

  /// Ready-made themes. They also serve as starting points for new ones.
  static const List<CustomTheme> presets = [
    CustomTheme(
      id: '${presetIdPrefix}forest',
      name: 'Forest',
      background: Color(0xFF0E1A13),
      accent: Color(0xFF4ADE80),
    ),
    CustomTheme(
      id: '${presetIdPrefix}ocean',
      name: 'Ocean',
      background: Color(0xFF071A2B),
      accent: Color(0xFF22D3EE),
    ),
    CustomTheme(
      id: '${presetIdPrefix}ember',
      name: 'Ember',
      background: Color(0xFF1C1210),
      accent: Color(0xFFFB923C),
    ),
    CustomTheme(
      id: '${presetIdPrefix}grape',
      name: 'Grape',
      background: Color(0xFF17112A),
      accent: Color(0xFFC084FC),
    ),
    CustomTheme(
      id: '${presetIdPrefix}high_contrast',
      name: 'High Contrast',
      background: Color(0xFF000000),
      accent: Color(0xFFFACC15),
    ),
    CustomTheme(
      id: '${presetIdPrefix}paper',
      name: 'Paper',
      background: Color(0xFFFAF7F0),
      accent: Color(0xFF9A3412),
    ),
    CustomTheme(
      id: '${presetIdPrefix}mint',
      name: 'Mint',
      background: Color(0xFFEFFAF4),
      accent: Color(0xFF047857),
    ),
    CustomTheme(
      id: '${presetIdPrefix}sky',
      name: 'Sky',
      background: Color(0xFFF0F6FC),
      accent: Color(0xFF1D4ED8),
    ),
  ];

  static CustomTheme? presetById(String id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}

/// `#RRGGBB` (alpha dropped — themes are always opaque).
String colorToHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

final _hexDigits = RegExp(r'^[0-9a-fA-F]+$');

/// Accepts `#RRGGBB`, `RRGGBB`, `#RGB` or `RGB`. Returns an opaque color, or
/// null when [value] is not a hex color.
Color? parseHexColor(Object? value) {
  if (value is! String) return null;
  var hex = value.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length != 6 || !_hexDigits.hasMatch(hex)) return null;
  final rgb = int.tryParse(hex, radix: 16);
  if (rgb == null) return null;
  return Color(0xFF000000 | rgb);
}

/// Same threshold Flutter's `ThemeData.estimateBrightnessForColor` uses, so
/// "dark" here agrees with Material's text-color choices.
bool isDarkColor(Color color) {
  final luminance = color.computeLuminance();
  const kThreshold = 0.15;
  return (luminance + 0.05) * (luminance + 0.05) <= kThreshold;
}
