/// Inline styles a run of message text can carry.
class MarkupStyles {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final bool mono;

  /// Colour key from [MessageMarkup.colorKeys], or null for the default text
  /// colour. Nested colours override rather than blend, so the innermost tag
  /// wins.
  final String? color;

  const MarkupStyles({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.mono = false,
    this.color,
  });

  static const none = MarkupStyles();

  bool get isPlain =>
      !bold &&
      !italic &&
      !underline &&
      !strikethrough &&
      !mono &&
      color == null;

  MarkupStyles withMarker(String marker) => MarkupStyles(
    bold: bold || marker == MessageMarkup.bold,
    italic: italic || marker == MessageMarkup.italic,
    underline: underline || marker == MessageMarkup.underline,
    strikethrough: strikethrough || marker == MessageMarkup.strikethrough,
    mono: mono || marker == MessageMarkup.mono,
    color: color,
  );

  MarkupStyles withColor(String value) => MarkupStyles(
    bold: bold,
    italic: italic,
    underline: underline,
    strikethrough: strikethrough,
    mono: mono,
    color: value,
  );
}

/// A run of text with the styles that apply to it.
class MarkupSegment {
  final String text;
  final MarkupStyles styles;

  /// True for the marker characters themselves, which [MessageMarkup.parse]
  /// only emits when asked to keep them — the composer shows them, message
  /// bubbles do not.
  final bool isMarker;

  const MarkupSegment(this.text, this.styles, {this.isMarker = false});
}

/// One span left open while parsing: what closes it, and what it does to the
/// style of everything inside.
class _OpenSpan {
  final String closer;

  /// Paired marker this span came from, or null for a colour tag.
  final String? marker;

  /// Colour key, or null for a paired marker.
  final String? color;

  const _OpenSpan({required this.closer, this.marker, this.color});
}

/// Chat-style inline markup: `**bold**`, `__italic__`, `_underline_`,
/// `~~strikethrough~~`, ```` ```mono``` ```` and colour tags such as
/// `[r]red[/r]`.
///
/// Deliberately forgiving, the way messaging apps are: a span only opens when
/// its closer exists later in the text, so a lone `*`, a snake_case word or a
/// stray bracket stays literal. Spans cross line breaks — a bold block can
/// cover a whole paragraph.
class MessageMarkup {
  MessageMarkup._();

  static const String mono = '```';
  static const String bold = '**';
  static const String italic = '__';
  static const String strikethrough = '~~';
  static const String underline = '_';

  /// Longest first, so `__` is never mistaken for two `_`.
  static const List<String> markers = [
    mono,
    bold,
    italic,
    strikethrough,
    underline,
  ];

  /// Colour tag keys, longest first so `[b]` cannot shadow `[bk]`. The parser
  /// only decides which brackets are markup; the actual colours live with the
  /// renderer, in `MarkupPalette`.
  static const List<String> colorKeys = [
    'lb', // light blue
    'bk', // black
    'gr', // grey
    'r', // red
    'g', // green
    'b', // blue
    'y', // yellow
    'o', // orange
    'p', // purple
    'w', // white
  ];

  /// Markers made of `_` must not start inside a word, or every snake_case
  /// identifier and half the URLs would turn into italics.
  static const List<String> _wordBoundaryMarkers = [italic, underline];

  /// Cheap pre-check before the full parse: message lists render a lot of
  /// plain text, and most of it contains no marker character at all.
  static bool has(String text) {
    var carriesMarkerChar = false;
    for (final unit in text.codeUnits) {
      // '*', '_', '~', '`', '['
      if (unit == 0x2A ||
          unit == 0x5F ||
          unit == 0x7E ||
          unit == 0x60 ||
          unit == 0x5B) {
        carriesMarkerChar = true;
        break;
      }
    }
    if (!carriesMarkerChar) return false;
    for (final segment in parse(text)) {
      if (!segment.styles.isPlain) return true;
    }
    return false;
  }

  /// Splits [text] into styled runs. Markers are dropped by default — they are
  /// formatting, not content — but [keepMarkers] emits them as segments of
  /// their own, which the composer needs to keep caret positions honest.
  static List<MarkupSegment> parse(String text, {bool keepMarkers = false}) {
    final segments = <MarkupSegment>[];
    final open = <_OpenSpan>[];
    final buffer = StringBuffer();

    MarkupStyles currentStyles() {
      var styles = MarkupStyles.none;
      for (final span in open) {
        styles = span.marker != null
            ? styles.withMarker(span.marker!)
            : styles.withColor(span.color!);
      }
      return styles;
    }

    void flush() {
      if (buffer.isEmpty) return;
      segments.add(MarkupSegment(buffer.toString(), currentStyles()));
      buffer.clear();
    }

    void emitMarker(String marker) {
      if (!keepMarkers) return;
      segments.add(MarkupSegment(marker, currentStyles(), isMarker: true));
    }

    var index = 0;
    while (index < text.length) {
      // Close the innermost span first, so nesting unwinds in order.
      if (open.isNotEmpty && text.startsWith(open.last.closer, index)) {
        flush();
        emitMarker(open.last.closer);
        index += open.removeLast().closer.length;
        continue;
      }

      final opener = _openerAt(text, index, open);
      if (opener != null) {
        flush();
        open.add(opener.span);
        emitMarker(opener.text);
        index += opener.text.length;
        continue;
      }

      buffer.write(text[index]);
      index++;
    }
    flush();
    return segments;
  }

  static ({String text, _OpenSpan span})? _openerAt(
    String text,
    int index,
    List<_OpenSpan> open,
  ) {
    // Inside a mono block everything is literal until the block closes.
    if (open.any((span) => span.marker == mono)) return null;

    for (final marker in markers) {
      if (!text.startsWith(marker, index)) continue;
      if (open.any((span) => span.marker == marker)) return null;
      if (!_canOpen(text, index, marker)) return null;
      if (!_hasCloser(text, index + marker.length, marker)) return null;
      return (text: marker, span: _OpenSpan(closer: marker, marker: marker));
    }

    if (!text.startsWith('[', index)) return null;
    for (final key in colorKeys) {
      final opener = '[$key]';
      if (!text.startsWith(opener, index)) continue;
      final closer = '[/$key]';
      final closerAt = text.indexOf(closer, index + opener.length);
      // An empty tag pair is not worth styling, and an unclosed one is text.
      if (closerAt <= index + opener.length - 1) return null;
      return (text: opener, span: _OpenSpan(closer: closer, color: key));
    }
    return null;
  }

  static bool _canOpen(String text, int index, String marker) {
    if (!_wordBoundaryMarkers.contains(marker)) return true;
    if (index == 0) return true;
    return !_isWordCharacter(text[index - 1]);
  }

  /// A closer must exist and leave something between the markers, so `****`
  /// stays literal.
  static bool _hasCloser(String text, int from, String marker) {
    final closer = text.indexOf(marker, from);
    if (closer < 0 || closer == from) return false;
    if (!_wordBoundaryMarkers.contains(marker)) return true;
    final after = closer + marker.length;
    return after >= text.length || !_isWordCharacter(text[after]);
  }

  static final RegExp _wordCharacter = RegExp(r'[\wЀ-ӿ]');

  static bool _isWordCharacter(String char) => _wordCharacter.hasMatch(char);
}
