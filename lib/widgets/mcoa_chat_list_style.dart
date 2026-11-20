import 'package:flutter/material.dart';

import '../theme/mcoa_theme_style.dart';
import '../theme/mesh_theme.dart';
import 'mesh_ui.dart';
import 'unread_badge.dart';

/// Optional list-only overrides: avatars, chat bodies and settings cards keep
/// their own colors. An unset slot preserves each caller's existing fallback.
class McoaChatListStyle {
  static bool hidePreviewIndex(BuildContext context) =>
      !(McoaThemeStyle.of(context).showChannelIndices ?? true);

  static Color? override(BuildContext context, String part) =>
      McoaThemeStyle.of(context).colors['chats_$part'];

  static Color color(BuildContext context, String part, Color fallback) =>
      override(context, part) ?? fallback;

  static Color? searchBackground(BuildContext context, {bool contacts = false}) =>
      (contacts ? override(context, 'search_contacts_background') : null) ??
      override(context, 'search_background');

  static Color fallback(ThemeData theme, String part) {
    final scheme = theme.colorScheme;
    return switch (part) {
      'border' => scheme.outlineVariant,
      'background' => scheme.surfaceContainerLow,
      'title' || 'index_text' || 'prefix_text' => scheme.onSurface,
      'preview' || 'icons' => scheme.onSurfaceVariant,
      'index_border' => MeshPalette.blue.withValues(alpha: 0.3),
      'index_background' => MeshPalette.blue.withValues(alpha: 0.12),
      'index_dot' => readableAccent(MeshPalette.blue,
          Color.alphaBlend(MeshPalette.blue.withValues(alpha: 0.12), scheme.surfaceContainerLow),
          minContrast: 3),
      'unread_background' => MeshPalette.alert,
      'unread_text' => Colors.white,
      'search_border' => theme.inputDecorationTheme.enabledBorder?.borderSide.color ?? scheme.outlineVariant,
      'search_background' || 'search_contacts_background' => theme.inputDecorationTheme.fillColor ?? scheme.surfaceContainerHigh,
      'search_text' => theme.textTheme.bodyLarge?.color ?? scheme.onSurface,
      'search_hint_icons' => theme.inputDecorationTheme.hintStyle?.color ?? scheme.onSurfaceVariant,
      'key' => scheme.onSurfaceVariant.withValues(alpha: 0.7),
      'prefix_border' => scheme.outline,
      'prefix_background' => scheme.surfaceContainerHighest,
      _ => Colors.transparent,
    };
  }
}

class McoaChatListUnreadBadge extends StatelessWidget {
  const McoaChatListUnreadBadge({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => UnreadBadge(
    count: count,
    backgroundColor: McoaChatListStyle.override(context, 'unread_background'),
    textColor: McoaChatListStyle.override(context, 'unread_text'),
  );
}

class McoaChannelIndexChip extends StatelessWidget {
  const McoaChannelIndexChip({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: label, color: MeshPalette.blue, fontSize: 10,
    borderColor: McoaChatListStyle.override(context, 'index_border'),
    backgroundColor: McoaChatListStyle.override(context, 'index_background'),
    textColor: McoaChatListStyle.override(context, 'index_text'),
    dotColor: McoaChatListStyle.override(context, 'index_dot'),
  );
}
