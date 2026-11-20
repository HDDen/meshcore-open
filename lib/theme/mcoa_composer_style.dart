import 'package:flutter/material.dart';

import 'mcoa_theme_style.dart';

/// Composer-only overrides: generic byte-counted inputs keep their old theme.
class McoaComposerStyle {
  McoaComposerStyle._();

  static ButtonStyle sendButton(BuildContext context) {
    final colors = McoaThemeStyle.of(context).colors;
    return IconButton.styleFrom(
      backgroundColor: colors['composer_send_background'],
      foregroundColor: colors['composer_send_icon'],
    );
  }

  static InputDecoration decoration(BuildContext context, InputDecoration original) {
    final colors = McoaThemeStyle.of(context).colors;
    final theme = Theme.of(context).inputDecorationTheme;
    final borderColor = colors['composer_input_border'];
    InputBorder? border(InputBorder? local, InputBorder? inherited) {
      if (borderColor == null) {
        return local;
      }
      final shape = local ?? inherited ?? original.border ?? const OutlineInputBorder();
      return shape.copyWith(borderSide: shape.borderSide.copyWith(color: borderColor));
    }
    final hintColor = colors['composer_input_hint'];
    return original.copyWith(
      filled: colors['composer_input_background'] == null ? original.filled : true,
      fillColor: colors['composer_input_background'] ?? original.fillColor,
      hintStyle: hintColor == null ? original.hintStyle
          : (original.hintStyle ?? theme.hintStyle ?? const TextStyle()).copyWith(color: hintColor),
      border: border(original.border, theme.border),
      enabledBorder: border(original.enabledBorder, theme.enabledBorder),
      focusedBorder: border(original.focusedBorder, theme.focusedBorder),
      disabledBorder: border(original.disabledBorder, theme.disabledBorder),
    );
  }

  static TextStyle? text(BuildContext context) {
    final color = McoaThemeStyle.of(context).colors['composer_input_text'];
    return color == null ? null
        : (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(color: color);
  }

  static Color counter(BuildContext context, double ratio,
      double warningThreshold, double errorThreshold, Color fallback) {
    final key = ratio > errorThreshold ? 'composer_counter_error'
        : ratio > warningThreshold ? 'composer_counter_warning' : 'composer_counter';
    return McoaThemeStyle.of(context).colors[key] ?? fallback;
  }
}
