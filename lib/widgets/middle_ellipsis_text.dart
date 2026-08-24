import 'package:flutter/material.dart';

/// Single-line text that elides the middle («start…end») when it does not fit
/// the available width, keeping both ends visible.
class MiddleEllipsisText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const MiddleEllipsisText({
    super.key,
    required this.text,
    required this.style,
  });

  static const String _ellipsis = '…';

  double _measure(String value, TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      maxLines: 1,
      textDirection: direction,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || _measure(text, direction) <= maxWidth) {
          return Text(text, maxLines: 1, softWrap: false, style: style);
        }
        // Binary search for the largest number of original characters that fit
        // once the middle is replaced by the ellipsis.
        var lo = 0;
        var hi = text.length;
        var best = _ellipsis;
        while (lo <= hi) {
          final keep = (lo + hi) ~/ 2;
          final head = (keep + 1) ~/ 2;
          final tail = keep ~/ 2;
          final candidate =
              '${text.substring(0, head)}$_ellipsis'
              '${text.substring(text.length - tail)}';
          if (_measure(candidate, direction) <= maxWidth) {
            best = candidate;
            lo = keep + 1;
          } else {
            hi = keep - 1;
          }
        }
        return Text(
          best,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: style,
        );
      },
    );
  }
}
