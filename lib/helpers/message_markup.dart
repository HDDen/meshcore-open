/// Inline styles a run of message text can carry.
class MarkupStyles {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final bool mono;

  const MarkupStyles({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.mono = false,
  });

  static const none = MarkupStyles();

  bool get isPlain =>
      !bold && !italic && !underline && !strikethrough && !mono;

  MarkupStyles withMarker(String marker) => MarkupStyles(
    bold: bold || marker == MessageMarkup.bold,
    italic: italic || marker == MessageMarkup.italic,
    underline: underline || marker == MessageMarkup.underline,
    strikethrough: strikethrough || marker == MessageMarkup.strikethrough,
    mono: mono || marker == MessageMarkup.mono,
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

/// Chat-style inline markup: `**bold**`, `__italic__`, `_underline_`,
/// `~~strikethrough~~` and ```` ```mono``` ````.
///
/// Deliberately forgiving, the way messaging apps are: a marker only opens a
/// span when a matching closer exists later in the text, so a lone `*` or a
/// snake_case word stays literal. Markers span line breaks — a bold block can
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

  /// Markers made of `_` must not start inside a word, or every snake_case
  /// identifier and half the URLs would turn into italics.
  static const List<String> _wordBoundaryMarkers = [italic, underline];

  /// Cheap pre-check before the full parse: message lists render a lot of
  /// plain text, and most of it contains no marker character at all.
  static bool has(String text) {
    var carriesMarkerChar = false;
    for (final unit in text.codeUnits) {
      // '*', '_', '~', '`'
      if (unit == 0x2A || unit == 0x5F || unit == 0x7E || unit == 0x60) {
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
    final open = <String>[];
    final buffer = StringBuffer();

    MarkupStyles currentStyles() {
      var styles = MarkupStyles.none;
      for (final marker in open) {
        styles = styles.withMarker(marker);
      }
      return styles;
    }

    void flush() {
      if (buffer.isEmpty) return;
      segments.add(MarkupSegment(buffer.toString(), currentStyles()));
      buffer.clear();
    }

    var index = 0;
    while (index < text.length) {
      final marker = _markerAt(text, index, insideMono: open.contains(mono));
      if (marker != null) {
        if (open.isNotEmpty && open.last == marker) {
          flush();
          if (keepMarkers) {
            segments.add(
              MarkupSegment(marker, currentStyles(), isMarker: true),
            );
          }
          open.removeLast();
          index += marker.length;
          continue;
        }
        if (!open.contains(marker) &&
            _canOpen(text, index, marker) &&
            _hasCloser(text, index + marker.length, marker)) {
          flush();
          open.add(marker);
          if (keepMarkers) {
            segments.add(
              MarkupSegment(marker, currentStyles(), isMarker: true),
            );
          }
          index += marker.length;
          continue;
        }
      }
      buffer.write(text[index]);
      index++;
    }
    flush();
    return segments;
  }

  static String? _markerAt(
    String text,
    int index, {
    required bool insideMono,
  }) {
    // Inside a mono block everything is literal until the block closes.
    if (insideMono) {
      return text.startsWith(mono, index) ? mono : null;
    }
    for (final marker in markers) {
      if (text.startsWith(marker, index)) return marker;
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
