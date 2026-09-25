import 'package:flutter/widgets.dart';

/// Single-line text that elides the middle («start…end») when it does not fit
/// the available width, keeping both ends visible.
///
/// [style] must be monospace, as it is for the public keys shown with this
/// widget: the cut is computed from the width of one character cell instead
/// of laying out candidate strings. The bundled JetBrains Mono gives the hex
/// digits and the ellipsis the same advance.
///
/// The cell is measured the way [Text] will lay the text out here: the same
/// style merge, bold-text setting and text scaler, which is where the app's
/// DPI setting lands. Each measurement is shared by every instance, so a list
/// of keys adds no text layout of its own, on first display, while scrolling
/// or while the window is resized.
class MiddleEllipsisText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const MiddleEllipsisText({
    super.key,
    required this.text,
    required this.style,
  });

  static const String _ellipsis = '…';

  // Hex digits, which is what the keys are made of.
  static const String _sample = '0123456789ABCDEF';

  static final Map<(TextStyle, TextScaler), double> _cellWidths = {};
  static bool _listensToFonts = false;

  double _cellWidth(BuildContext context) {
    var effective = style.inherit
        ? DefaultTextStyle.of(context).style.merge(style)
        : style;
    if (MediaQuery.boldTextOf(context)) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final textScaler = MediaQuery.textScalerOf(context);
    final key = (effective, textScaler);
    final cached = _cellWidths[key];
    if (cached != null) return cached;

    if (!_listensToFonts) {
      // A font that finishes loading, as bundled fonts do on the web, changes
      // every measurement.
      _listensToFonts = true;
      PaintingBinding.instance.systemFonts.addListener(_cellWidths.clear);
    }
    // Colour and theme make a style new only a handful of times.
    if (_cellWidths.length >= 8) _cellWidths.clear();
    final painter = TextPainter(
      text: TextSpan(text: _sample, style: effective),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final width = painter.width / _sample.length;
    painter.dispose();
    return _cellWidths[key] = width;
  }

  @override
  Widget build(BuildContext context) {
    final cellWidth = _cellWidth(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        // A hair of tolerance, so a key that fits exactly is not cut over a
        // rounding error.
        final cells = maxWidth.isFinite && cellWidth > 0
            ? ((maxWidth + 0.001) / cellWidth).floor()
            : text.length;
        if (text.length <= cells) {
          return Text(text, maxLines: 1, softWrap: false, style: style);
        }
        // The ellipsis takes one cell and the ends share the rest, the head
        // taking the odd one.
        final keep = cells > 0 ? cells - 1 : 0;
        final head = (keep + 1) ~/ 2;
        final tail = keep ~/ 2;
        return Text(
          '${text.substring(0, head)}$_ellipsis'
          '${text.substring(text.length - tail)}',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: style,
        );
      },
    );
  }
}
