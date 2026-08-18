import 'dart:convert';

import '../models/channel_message.dart';
import 'cyr2lat.dart';

/// An incoming reply's quote line, with the message it was matched to.
class ResolvedQuote {
  /// Reply text with the quote line removed.
  final String text;

  /// Fragment exactly as received, kept so the quote stays visible even when
  /// nothing local matched it.
  final String fragment;

  /// Local message the fragment was cut from, when one was found.
  final ChannelMessage? quoted;

  const ResolvedQuote({
    required this.text,
    required this.fragment,
    required this.quoted,
  });
}

/// Plain-text replies carry only "@[sender]", which the receiver resolves to
/// that sender's most recent message. That is wrong whenever the answer targets
/// an older one, and plain text has no room for a real anchor like MCMP v3
/// provides. This helper adds a short quote fragment — ">first characters" on
/// its own line — that costs a few bytes and lets the receiver find the exact
/// message the reply belongs to.
///
/// Both ends of the mechanism live here: [formatReply] decides whether an
/// outgoing reply needs a fragment and builds the wire form, [resolveReply]
/// takes that wire form apart and matches it against local history.
class ExactQuoteHelper {
  ExactQuoteHelper._();

  /// Airtime budget for the fragment, measured on the wire: bytes rather than
  /// characters, and counted after cyr2lat transliteration when the channel
  /// uses it, since that is what the packet actually pays for.
  static const int maxFragmentBytes = 15;

  static const String _marker = '>';

  /// Appended when the fragment is shorter than the message it came from, so a
  /// quote that could not be resolved still reads as an excerpt. Stripped
  /// again before matching.
  static const String _ellipsis = '...';

  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _leadingBracketMention = RegExp(r'^@\[[^\]]+\]\s*');
  static final RegExp _leadingPlainMention = RegExp(r'^@\S+\s+');

  /// Trailing whitespace and punctuation are cut off a fragment so the
  /// ellipsis does not hang off a comma or a dangling space. A question
  /// mark is kept — it carries meaning the reader recognises the message by.
  static final RegExp _fragmentTrailing = RegExp(r'[\s.+,-]+$');

  /// Tried in this order when matching a transliterated fragment. Extended
  /// first because it is a superset of the standard table and the more common
  /// choice, transliteration last because it is the least look-alike of the
  /// three.
  static const List<Map<String, String>> _builtInCharMaps = [
    Cyr2Lat.extendedCharMap,
    Cyr2Lat.defaultCharMap,
    Cyr2Lat.transliterationCharMap,
  ];

  /// Wire form of a reply: "@[sender] text", with a ">fragment" line inserted
  /// when the mention alone would not identify the quoted message.
  ///
  /// [enabled] is false when the user turned the feature off or when the
  /// message travels as MCMP v3, which already carries an exact anchor. No
  /// fragment is spent when [quotedMessageId] is the newest message from
  /// [senderName] in [history] either — a bare mention resolves to it anyway.
  ///
  /// [outboundCharMap] is the cyr2lat table this message will be transliterated
  /// with, or null when it travels untransliterated. The fragment itself is cut
  /// from the readable original — transliteration happens later, to the whole
  /// message at once — but the budget is spent in transliterated bytes.
  static String formatReply({
    required String senderName,
    required String text,
    required String? quotedText,
    required String? quotedMessageId,
    required List<ChannelMessage> history,
    required bool enabled,
    Map<String, String>? outboundCharMap,
  }) {
    final mention = '@[$senderName] ';
    final fragment = enabled
        ? _fragmentFor(
            senderName,
            quotedText,
            quotedMessageId,
            history,
            outboundCharMap,
          )
        : null;
    if (fragment == null) return '$mention$text';
    return '$mention$_marker$fragment\n$text';
  }

  /// Takes the quote line off an incoming reply and matches it against
  /// [history]. [body] is what follows the mention; [extraCharMaps] adds
  /// user-defined cyr2lat profiles to the built-in tables.
  ///
  /// Returns null when [body] carries no quote line, which is the common case
  /// for messages from other clients.
  static ResolvedQuote? resolveReply({
    required String body,
    required String mentionedNode,
    required List<ChannelMessage> history,
    List<Map<String, String>> extraCharMaps = const [],
  }) {
    if (!body.startsWith(_marker)) return null;
    final newline = body.indexOf('\n');
    if (newline <= _marker.length) return null;
    final fragment = body.substring(_marker.length, newline);
    if (fragment.isEmpty) return null;

    return ResolvedQuote(
      text: body.substring(newline + 1),
      fragment: fragment,
      quoted: _findQuoted(history, mentionedNode, fragment, extraCharMaps),
    );
  }

  static String? _fragmentFor(
    String senderName,
    String? quotedText,
    String? quotedMessageId,
    List<ChannelMessage> history,
    Map<String, String>? outboundCharMap,
  ) {
    if (quotedText == null || quotedText.isEmpty) return null;
    for (var i = history.length - 1; i >= 0; i--) {
      final candidate = history[i];
      if (candidate.senderName != senderName) continue;
      if (candidate.messageId == quotedMessageId) return null;
      break;
    }
    return _buildFragment(quotedText, outboundCharMap);
  }

  /// Cuts [text] down to [maxFragmentBytes] wire bytes without splitting a
  /// character, and marks the cut with an ellipsis. Trailing whitespace and
  /// punctuation are dropped first so the ellipsis does not hang off a comma
  /// or a half-typed space. Returns null when nothing usable is left, so
  /// callers can fall back to a bare mention.
  static String? _buildFragment(String text, Map<String, String>? charMap) {
    final source = _normalize(text);
    if (source.isEmpty) return null;
    final buffer = StringBuffer();
    var bytes = 0;
    var truncated = false;
    for (final rune in source.runes) {
      final char = String.fromCharCode(rune);
      final onWire = charMap == null ? char : (charMap[char] ?? char);
      final charBytes = utf8.encode(onWire).length;
      if (bytes + charBytes > maxFragmentBytes) {
        truncated = true;
        break;
      }
      buffer.write(char);
      bytes += charBytes;
    }
    final fragment = buffer.toString().replaceFirst(_fragmentTrailing, '');
    if (fragment.isEmpty) return null;
    return truncated ? '$fragment$_ellipsis' : fragment;
  }

  /// The most recent message from [mentionedNode] that [fragment] was cut
  /// from.
  static ChannelMessage? _findQuoted(
    List<ChannelMessage> history,
    String mentionedNode,
    String fragment,
    List<Map<String, String>> extraCharMaps,
  ) {
    for (var i = history.length - 1; i >= 0; i--) {
      final candidate = history[i];
      if (candidate.senderName != mentionedNode) continue;
      if (_matches(candidate.text, fragment, extraCharMaps)) return candidate;
    }
    return null;
  }

  /// A direct prefix match covers the normal case. When the reply was sent
  /// with cyr2lat the fragment arrived transliterated while the original sits
  /// in history in Cyrillic, so the candidate is put through every known
  /// substitution table and compared again. Encoding the candidate rather than
  /// decoding the fragment keeps this unambiguous: several Cyrillic letters
  /// map onto the same Latin one, so the reverse direction has no single
  /// answer.
  static bool _matches(
    String candidateText,
    String fragment,
    List<Map<String, String>> extraCharMaps,
  ) {
    final needle = fragment.endsWith(_ellipsis)
        ? fragment.substring(0, fragment.length - _ellipsis.length)
        : fragment;
    if (needle.isEmpty) return false;
    final candidate = _normalize(candidateText);
    if (candidate.startsWith(needle)) return true;
    for (final charMap in [..._builtInCharMaps, ...extraCharMaps]) {
      if (_transliterate(candidate, charMap).startsWith(needle)) return true;
    }
    return false;
  }

  /// Whitespace is collapsed and trimmed before a fragment is cut and again
  /// before a candidate is compared, so a quote taken from a multi-line
  /// message still matches the message it came from.
  static String _normalize(String text) =>
      _stripReplyScaffolding(text).replaceAll(_whitespace, ' ').trim();

  /// Drops the reply scaffolding a quoted message may itself begin with: a
  /// quote line of its own, or a mention of somebody else. Anchoring to that
  /// would point at the previous conversation rather than at what the author
  /// actually wrote, so both sides strip it before a fragment is cut or
  /// compared.
  static String _stripReplyScaffolding(String text) {
    var result = text.trimLeft();
    while (true) {
      final mention =
          _leadingBracketMention.matchAsPrefix(result) ??
          _leadingPlainMention.matchAsPrefix(result);
      if (mention != null && mention.end > 0) {
        result = result.substring(mention.end).trimLeft();
        continue;
      }
      if (result.startsWith(_marker)) {
        final newline = result.indexOf('\n');
        if (newline > 0) {
          result = result.substring(newline + 1).trimLeft();
          continue;
        }
      }
      return result;
    }
  }

  static String _transliterate(String text, Map<String, String> charMap) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(charMap[char] ?? char);
    }
    return buffer.toString();
  }
}
