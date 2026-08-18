import 'package:flutter/material.dart';

import '../helpers/message_markup.dart';
import '../theme/mesh_theme.dart';

/// Composer controller that previews inline markup as it is typed.
///
/// The markers stay in the text — a Flutter text field cannot hide characters
/// without the caret drifting out of step — but they are dimmed, and the run
/// between them is drawn the way it will look once sent. Deleting one marker
/// therefore visibly strips the formatting off that run, which is how you undo
/// it by editing.
class MarkupTextEditingController extends TextEditingController {
  MarkupTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // While an IME composition is in flight the base implementation owns the
    // underline that marks it; re-styling underneath would fight with it.
    if (withComposing &&
        value.isComposingRangeValid &&
        !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final base = style ?? const TextStyle();
    final markerColor =
        base.color?.withValues(alpha: 0.4) ??
        Theme.of(context).colorScheme.onSurfaceVariant;

    return TextSpan(
      style: base,
      children: [
        for (final segment in MessageMarkup.parse(text, keepMarkers: true))
          TextSpan(
            text: segment.text,
            style: segment.isMarker
                ? base.copyWith(color: markerColor)
                : _applyMarkup(base, segment.styles),
          ),
      ],
    );
  }

  static TextStyle _applyMarkup(TextStyle base, MarkupStyles styles) {
    if (styles.isPlain) return base;
    final decorations = <TextDecoration>[
      if (styles.underline) TextDecoration.underline,
      if (styles.strikethrough) TextDecoration.lineThrough,
    ];
    var result = base.copyWith(
      fontWeight: styles.bold ? FontWeight.w700 : null,
      fontStyle: styles.italic ? FontStyle.italic : null,
      decoration: decorations.isEmpty
          ? null
          : TextDecoration.combine(decorations),
      decorationColor: decorations.isEmpty ? null : base.color,
    );
    if (styles.mono) {
      result = result.copyWith(
        fontFamily: MeshFonts.mono,
        fontFamilyFallback: MeshFonts.monoFallback,
      );
    }
    return result;
  }
}
