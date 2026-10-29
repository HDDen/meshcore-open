import 'package:flutter/painting.dart';

/// Add the author only to an actual, visible message preview. Empty channels
/// retain their channel description; a blocked preview never reveals a name.
TextSpan buildChannelPreviewSpan(
  String preview, {
  required String? senderName,
  required bool showSender,
  required TextStyle style,
  bool blocked = false,
}) {
  final sender = senderName?.trim() ?? '';
  if (!showSender || blocked || preview.isEmpty || sender.isEmpty) {
    return TextSpan(text: preview, style: style);
  }
  return TextSpan(
    style: style,
    children: [
      TextSpan(text: '$sender:'),
      // Scale only the separating space. A Unicode thin space can still occupy
      // a full cell in a monospace font. Retain a normal space for semantics.
      TextSpan(
        text: ' ',
        style: TextStyle(
          fontSize: (style.fontSize ?? 14) / 2,
          letterSpacing: (style.letterSpacing ?? 0) / 2,
        ),
      ),
      TextSpan(text: preview),
    ],
  );
}
