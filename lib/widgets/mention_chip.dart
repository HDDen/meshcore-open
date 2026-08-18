import 'package:flutter/material.dart';

import '../theme/mesh_theme.dart';

/// How an `@name` mention is drawn inside a message bubble.
///
/// Two looks, picked by the "simplified mentions" setting: a bordered
/// monospace tag, or plain bold text that flows with the sentence.
class MentionChip extends StatelessWidget {
  const MentionChip({
    super.key,
    required this.senderName,
    required this.textScale,
    required this.simplified,
    required this.textStyle,
    this.onTap,
  });

  final String senderName;
  final double textScale;
  final bool simplified;
  final TextStyle textStyle;
  final VoidCallback? onTap;

  /// Baseline for the plain look so it sits on the line like the words around
  /// it; the bordered look is centred instead, since the border would
  /// otherwise hang below the text.
  PlaceholderAlignment get alignment => simplified
      ? PlaceholderAlignment.baseline
      : PlaceholderAlignment.middle;

  TextBaseline? get baseline => simplified ? TextBaseline.alphabetic : null;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      constraints: BoxConstraints(maxWidth: 160 * textScale),
      padding: simplified
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: simplified
          ? null
          : BoxDecoration(
              border: Border.all(color: MeshPalette.blue, width: 1),
              borderRadius: BorderRadius.circular(MeshRadii.xs),
            ),
      child: Text(
        '@$senderName',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: simplified
            ? textStyle.copyWith(fontWeight: FontWeight.w700)
            : MeshTheme.mono(
                fontSize: 12 * textScale,
                fontWeight: FontWeight.w700,
                color: MeshPalette.blue,
              ),
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
}
