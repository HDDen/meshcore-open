import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// The row under an outgoing direct or room message the retry service is
/// still working on: a tap stops the attempts and the wait for the
/// acknowledgement. Laid out as `PendingSendCancelBar`, divider included, so
/// the two read as one control, and needing the same `IntrinsicWidth` around
/// the bubble column for the divider to span the bubble.
class StopSendingBar extends StatelessWidget {
  final VoidCallback onStop;
  final Color foregroundColor;
  final EdgeInsetsGeometry contentPadding;

  const StopSendingBar({
    super.key,
    required this.onStop,
    required this.foregroundColor,
    this.contentPadding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = DefaultTextStyle.of(
      context,
    ).style.copyWith(color: foregroundColor);
    return InkWell(
      onTap: onStop,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Container(height: 1, color: Colors.black.withValues(alpha: 0.5)),
            Padding(
              padding: contentPadding.add(const EdgeInsets.fromLTRB(0, 8, 0, 6)),
              child: Text(context.l10n.chat_stopSending, style: textStyle),
            ),
          ],
        ),
      ),
    );
  }
}
