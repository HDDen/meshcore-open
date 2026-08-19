import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// What a blocked sender's message shows instead of its text.
///
/// The text itself is kept and a tap reveals it, but revealing is a display
/// choice and nothing more: the bubble never parses a blocked body, so a
/// revealed marker still puts no pin on the map and a revealed image stays a
/// line of text. Only lifting the block brings those back, and only for what
/// arrives afterwards.
class BlockedMessageBody extends StatelessWidget {
  const BlockedMessageBody({
    super.key,
    required this.text,
    required this.revealed,
    required this.onToggle,
    required this.style,
  });

  final String text;
  final bool revealed;
  final VoidCallback onToggle;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final muted = (style.color ?? Theme.of(context).colorScheme.onSurface)
        .withValues(alpha: 0.45);
    // The placeholder is not the message, so it sits a size below the body
    // text; the icon follows it rather than the body, and stays put when the
    // text is revealed at full size.
    final markerSize = (style.fontSize ?? 14) * 0.82;
    final bodyStyle = revealed
        ? style.copyWith(color: muted)
        : style.copyWith(
            color: muted,
            fontStyle: FontStyle.italic,
            fontSize: markerSize,
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      // One span run rather than a Row: the icon rides the text line, so it
      // centres against it at any size instead of needing a nudge.
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Icon(Icons.block, size: markerSize, color: muted),
              ),
            ),
            TextSpan(
              text: revealed ? text : context.l10n.chat_senderBlocked,
            ),
          ],
        ),
        style: bodyStyle,
      ),
    );
  }
}
