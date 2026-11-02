/// Notification matcher for the node name and the channel's sender name.
class ChannelMentionMatcher {
  ChannelMentionMatcher._();

  // Bounded cache: no timer, and no recompiling patterns on every message.
  static final Map<String, RegExp> _patterns = {};

  static bool mentions(String text, String? name) {
    final normalized = name?.trim();
    if (normalized == null || normalized.isEmpty || !text.contains('@')) {
      return false;
    }
    final key = normalized.toLowerCase();
    var pattern = _patterns[key];
    if (pattern == null) {
      final escaped = RegExp.escape(normalized);
      // Build from raw fragments so Dart does not consume regex escapes.
      final expression = StringBuffer()
        ..write(r'@\[\s*')
        ..write(escaped)
        ..write(r'\s*\]|(?<![\p{L}\p{N}_])@')
        ..write(escaped)
        ..write(r'(?![\p{L}\p{N}_])');
      pattern = RegExp(
        expression.toString(),
        caseSensitive: false,
        unicode: true,
      );
      if (_patterns.length >= 32) {
        _patterns.remove(_patterns.keys.first);
      }
      _patterns[key] = pattern;
    }
    return pattern.hasMatch(text);
  }
}
