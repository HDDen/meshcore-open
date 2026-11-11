import '../../helpers/channel_binary_data_helper.dart';
import '../../helpers/cyr2lat.dart';
import '../../helpers/mcoimg_codec.dart';
import '../../helpers/mcoimg_v3_codec.dart';
import '../../helpers/mcoimg_v4_codec.dart';
import '../../helpers/shared_marker_deletions.dart';
import '../../models/message_filter.dart';

/// Normalization and matching for user-defined channel rules.
class MessageFilterText {
  MessageFilterText._();

  static const trainingTextLimit = 500;

  static FilterExample trainingExample(
    String sender,
    String text, {
    required bool spam,
    String? sourceKey,
  }) {
    String boundedNormalized(String value, int maxLength) {
      final prefix = value.length > maxLength ? value.substring(0, maxLength) : value;
      final normalized = normalize(prefix);
      return normalized.length > maxLength
          ? normalized.substring(0, maxLength)
          : normalized;
    }

    return FilterExample(
      sender: boundedNormalized(sender, 100),
      text: boundedNormalized(text, trainingTextLimit),
      spam: spam,
      sourceKey: sourceKey,
    );
  }

  static final RegExp _whitespace = RegExp(r'\s+', unicode: true);
  static final RegExp _mention = RegExp(r'@\[[^\]]*\]');
  static final RegExp _nonWordChars = RegExp(
    r'[^\p{L}\p{N}\s]+',
    unicode: true,
  );
  static const repeatedCharacterRun = 20;
  static final RegExp _repeatedChars = RegExp(
    r'([^\s\p{N}])\1{19,}',
    unicode: true,
  );

  static final Map<int, String> _foldMap = _buildFoldMap();

  static Map<int, String> _buildFoldMap() {
    final map = <int, String>{};
    void addAll(String chars, String replacement) {
      for (final rune in chars.runes) {
        map[rune] = replacement;
      }
    }

    // Accented Latin (lower case only: input is lower-cased first).
    addAll('àáâãäåāăąǎȁȃạảấầẩẫậắằẳẵặ', 'a');
    addAll('çćĉċč', 'c');
    addAll('ďđ', 'd');
    addAll('èéêëēĕėęěȅȇẹẻẽếềểễệ', 'e');
    addAll('ĝğġģ', 'g');
    addAll('ĥħ', 'h');
    addAll('ìíîïĩīĭįıǐȉȋỉị', 'i');
    addAll('ĵ', 'j');
    addAll('ķ', 'k');
    addAll('ĺļľŀł', 'l');
    addAll('ñńņňŉ', 'n');
    addAll('òóôõöøōŏőǒȍȏọỏốồổỗộớờởỡợơ', 'o');
    addAll('ŕŗř', 'r');
    addAll('śŝşšș', 's');
    addAll('ţťŧț', 't');
    addAll('ùúûüũūŭůűųǔȕȗụủứừửữựư', 'u');
    addAll('ŵ', 'w');
    addAll('ýÿŷỳỵỷỹ', 'y');
    addAll('źżž', 'z');
    map['ß'.runes.first] = 'ss';
    map['æ'.runes.first] = 'ae';
    map['œ'.runes.first] = 'oe';
    map['þ'.runes.first] = 'th';

    // Cyrillic look-alikes (reuse the app's Cyr2Lat table, lower-cased).
    Cyr2Lat.defaultCharMap.forEach((from, to) {
      map[from.toLowerCase().runes.first] = to.toLowerCase();
    });

    // Greek look-alikes.
    const greek = {
      'ο': 'o',
      'α': 'a',
      'ε': 'e',
      'ι': 'i',
      'κ': 'k',
      'ν': 'v',
      'ρ': 'p',
      'τ': 't',
      'υ': 'u',
      'χ': 'x',
    };
    greek.forEach((from, to) => map[from.runes.first] = to);
    return map;
  }

  static bool _isInvisible(int rune) =>
      (rune >= 0x200B && rune <= 0x200D) ||
      rune == 0x2060 ||
      rune == 0xFEFF ||
      rune == 0x00AD;

  static bool _isCombiningMark(int rune) =>
      (rune >= 0x0300 && rune <= 0x036F) ||
      (rune >= 0x1AB0 && rune <= 0x1AFF) ||
      (rune >= 0x1DC0 && rune <= 0x1DFF) ||
      (rune >= 0x20D0 && rune <= 0x20FF) ||
      (rune >= 0xFE20 && rune <= 0xFE2F);

  /// Maps fullwidth and "mathematical" styled letters/digits (bold, italic,
  /// script, …) to plain ASCII, returning null for everything else.
  static int? _foldStyledAscii(int rune) {
    // Fullwidth forms.
    if (rune >= 0xFF41 && rune <= 0xFF5A) return 0x61 + rune - 0xFF41;
    if (rune >= 0xFF21 && rune <= 0xFF3A) return 0x61 + rune - 0xFF21;
    if (rune >= 0xFF10 && rune <= 0xFF19) return 0x30 + rune - 0xFF10;
    // Mathematical alphanumeric symbols: repeating A-Z a-z blocks.
    if (rune >= 0x1D400 && rune <= 0x1D6A3) {
      final offset = (rune - 0x1D400) % 52;
      return 0x61 + (offset < 26 ? offset : offset - 26);
    }
    if (rune >= 0x1D7CE && rune <= 0x1D7FF) {
      return 0x30 + (rune - 0x1D7CE) % 10;
    }
    return null;
  }

  /// Lower-cases, folds accents and look-alike characters, removes invisible
  /// characters and leaves the whitespace untouched.
  static String _fold(String text) {
    final lower = text.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      if (_isInvisible(rune) || _isCombiningMark(rune)) continue;
      final styled = _foldStyledAscii(rune);
      if (styled != null) {
        buffer.writeCharCode(styled);
        continue;
      }
      final mapped = _foldMap[rune];
      if (mapped != null) {
        buffer.write(mapped);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// Canonical form used for rule matching and classifier features.
  static String normalize(String text) {
    if (text.isEmpty) return '';
    return _fold(text).replaceAll(_whitespace, ' ').trim();
  }

  /// Removes mentions and punctuation from already normalized text.
  static String duplicateKey(String normalizedText) => normalizedText
      .replaceAll(_mention, ' ')
      .replaceAll(_nonWordChars, ' ')
      .replaceAll(_whitespace, ' ')
      .trim();

  static bool hasRepeatedCharacters(String normalizedText) =>
      normalizedText.length >= repeatedCharacterRun &&
      _repeatedChars.hasMatch(normalizedText);

  /// Images, map commands and opaque app data use their own receive paths.
  static bool isStructuredPayload(String text) =>
      text.startsWith('g:') ||
      text.startsWith('V1|') ||
      SharedMarkerDeletion.isMarkerPayload(text) ||
      text.startsWith(MCOImageCodec.prefix) ||
      text.startsWith(MCOImageV3Codec.textPrefix) ||
      text.startsWith(MCOImageV4Codec.textPrefix) ||
      text.startsWith(ChannelBinaryDataHelper.unsupportedMcoImagePrefix) ||
      text.startsWith(ChannelBinaryDataHelper.unknownAppDataPrefix);

  static final Map<String, RegExp> _wholeWordCache = {};

  static RegExp _wholeWordRegExp(String normalizedPattern) {
    final cached = _wholeWordCache[normalizedPattern];
    if (cached != null) return cached;
    if (_wholeWordCache.length > 256) _wholeWordCache.clear();
    final regExp = RegExp(
      '(?<![\\p{L}\\p{N}])${RegExp.escape(normalizedPattern)}(?![\\p{L}\\p{N}])',
      unicode: true,
    );
    _wholeWordCache[normalizedPattern] = regExp;
    return regExp;
  }

  static bool matchesNormalized(
    String normalizedPattern,
    FilterRuleMatch match,
    String normalizedTarget,
  ) {
    if (normalizedPattern.isEmpty || normalizedTarget.isEmpty) return false;
    switch (match) {
      case FilterRuleMatch.contains:
        return normalizedTarget.contains(normalizedPattern);
      case FilterRuleMatch.exact:
        return normalizedTarget == normalizedPattern;
      case FilterRuleMatch.wholeWord:
        if (!normalizedTarget.contains(normalizedPattern)) return false;
        return _wholeWordRegExp(normalizedPattern).hasMatch(normalizedTarget);
    }
  }
}
