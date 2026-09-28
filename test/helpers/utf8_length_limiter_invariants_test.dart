import 'dart:convert';
import 'dart:math';

import 'package:characters/characters.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/utf8_length_limiter.dart';

// What the length limiter promises, pinned before its search for the cut
// point changes: an edit that fits, or removes bytes, comes back as it is;
// a clipped edit keeps the unchanged head and tail of the draft, a whole
// number of graphemes of the insertion, as many as fit, and puts the cursor
// after them; the limit is measured on the encoder's output when there is
// one. The exact cut for an encoder whose output can shrink as the text
// grows is not promised, only that the result fits.

TextEditingValue _value(String text, [int? cursor]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: cursor ?? text.length),
);

int _bytes(String text) => utf8.encode(text).length;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
bool _isHighSurrogate(int codeUnit) =>
    codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

/// The unchanged head and tail the limiter keeps: the longest common prefix
/// and suffix of the two texts by code unit, never overlapping and never
/// ending between the halves of a surrogate pair.
({String head, String tail, String inserted}) _split(String old, String now) {
  var prefix = 0;
  while (prefix < old.length &&
      prefix < now.length &&
      old.codeUnitAt(prefix) == now.codeUnitAt(prefix)) {
    prefix++;
  }
  if (prefix > 0 &&
      prefix < now.length &&
      _isLowSurrogate(now.codeUnitAt(prefix))) {
    prefix--;
  }
  var suffix = 0;
  while (suffix < old.length - prefix &&
      suffix < now.length - prefix &&
      old.codeUnitAt(old.length - 1 - suffix) ==
          now.codeUnitAt(now.length - 1 - suffix)) {
    suffix++;
  }
  if (suffix > 0 && _isLowSurrogate(now.codeUnitAt(now.length - suffix))) {
    suffix--;
  }
  return (
    head: now.substring(0, prefix),
    tail: now.substring(now.length - suffix),
    inserted: now.substring(prefix, now.length - suffix),
  );
}

bool _hasLoneSurrogate(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (_isHighSurrogate(unit)) {
      if (i + 1 >= text.length || !_isLowSurrogate(text.codeUnitAt(i + 1))) {
        return true;
      }
      i++;
    } else if (_isLowSurrogate(unit)) {
      return true;
    }
  }
  return false;
}

/// Graphemes of one to eighteen UTF-8 bytes: ASCII, Cyrillic, a three-byte
/// sign, emoji as surrogate pairs, a letter with a combining mark and a
/// family joined by zero-width joiners.
const List<String> _alphabet = [
  'a', 'b', 'z', ' ', '7',
  'п', 'р', 'я',
  '€',
  '\u{1F600}', '\u{1F601}', '\u{1F468}',
  'é',
  '\u{1F468}‍\u{1F469}‍\u{1F467}',
];

String _randomText(Random random, int maxGraphemes) {
  final count = random.nextInt(maxGraphemes + 1);
  final buffer = StringBuffer();
  for (var i = 0; i < count; i++) {
    buffer.write(_alphabet[random.nextInt(_alphabet.length)]);
  }
  return buffer.toString();
}

/// One random edit: [deleted] graphemes of [old] at grapheme [at] replaced by
/// [inserted], the cursor after the insertion, as a paste over a selection
/// reaches the formatter.
({TextEditingValue oldValue, TextEditingValue newValue, String inserted})
_randomEdit(Random random) {
  final old = _randomText(random, 12);
  final graphemes = old.characters.toList();
  final at = random.nextInt(graphemes.length + 1);
  final deleted = random.nextInt(graphemes.length - at + 1);
  final inserted = _randomText(random, 15);
  final head = graphemes.take(at).join();
  final tail = graphemes.skip(at + deleted).join();
  final now = '$head$inserted$tail';
  return (
    oldValue: TextEditingValue(
      text: old,
      selection: TextSelection(
        baseOffset: head.length,
        extentOffset: head.length + graphemes.skip(at).take(deleted).join().length,
      ),
    ),
    newValue: _value(now, head.length + inserted.length),
    inserted: inserted,
  );
}

class _CountingEncoder {
  _CountingEncoder(this.inner);
  final String Function(String) inner;
  int calls = 0;
  String call(String text) {
    calls++;
    return inner(text);
  }
}

/// Every Cyrillic letter becomes one ASCII letter: the encoded text is
/// shorter than the typed one, as cyr2lat makes it.
String _shrinkCyrillic(String text) =>
    text.replaceAll(RegExp('[а-яА-Я]'), 'x');

/// Every `a` doubles: the encoded text is longer than the typed one.
String _expandA(String text) => text.replaceAll('a', 'aa');

/// Not monotonic in the length of the text: every fourth length encodes
/// three bytes shorter than the one before it.
String _nonMonotonic(String text) => text.isNotEmpty && text.length % 4 == 0
    ? text.substring(0, text.length - 3)
    : text;

void main() {
  group('edits that need no clipping', () {
    const formatter = Utf8LengthLimitingTextInputFormatter(5);

    test('an edit that fits comes back as it is, composing range included',
        () {
      const newValue = TextEditingValue(
        text: 'abc',
        selection: TextSelection(baseOffset: 1, extentOffset: 2),
        composing: TextRange(start: 0, end: 3),
      );
      final result = formatter.formatEditUpdate(_value('ab'), newValue);
      expect(result.text, 'abc');
      expect(result.selection, newValue.selection);
      expect(result.composing, newValue.composing);
    });

    test('an edit that removes bytes passes even over the limit', () {
      expect(
        formatter.formatEditUpdate(_value('abcdefg'), _value('abcdef')).text,
        'abcdef',
      );
      // A replacement of the same size passes too.
      expect(
        formatter.formatEditUpdate(_value('abcdefg'), _value('abcdefX')).text,
        'abcdefX',
      );
      // Cyrillic to ASCII drops bytes though the text is as long.
      expect(
        formatter.formatEditUpdate(_value('ппппп'), _value('пппп' 'x')).text,
        'ппппx',
      );
    });

    test('a limit of zero or less refuses every edit', () {
      for (final limit in [0, -1]) {
        final old = _value('abc', 1);
        final result = Utf8LengthLimitingTextInputFormatter(
          limit,
        ).formatEditUpdate(old, _value('abXc', 3));
        expect(result.text, 'abc');
        expect(result.selection.baseOffset, 1);
      }
    });
  });

  group('clipped edits', () {
    test('keep the head and tail of the draft, a whole number of graphemes '
        'of the insertion, as many as fit, and the cursor after them', () {
      final random = Random(20260928);
      var clipped = 0;
      for (var i = 0; i < 600; i++) {
        final edit = _randomEdit(random);
        final maxBytes = 1 + random.nextInt(24);
        final formatter = Utf8LengthLimitingTextInputFormatter(maxBytes);
        final oldText = edit.oldValue.text;
        final newText = edit.newValue.text;
        final reason = 'limit $maxBytes, old "$oldText", new "$newText"';

        final result = formatter.formatEditUpdate(edit.oldValue, edit.newValue);

        if (_bytes(newText) <= maxBytes || _bytes(newText) <= _bytes(oldText)) {
          expect(result.text, newText, reason: reason);
          expect(result.selection, edit.newValue.selection, reason: reason);
          continue;
        }
        clipped++;
        final split = _split(oldText, newText);
        expect(result.text, startsWith(split.head), reason: reason);
        expect(result.text, endsWith(split.tail), reason: reason);
        expect(
          result.text.length,
          greaterThanOrEqualTo(split.head.length + split.tail.length),
          reason: reason,
        );
        final kept = result.text.substring(
          split.head.length,
          result.text.length - split.tail.length,
        );
        final keptGraphemes = kept.characters.toList();
        final insertedGraphemes = split.inserted.characters.toList();
        expect(
          insertedGraphemes.take(keptGraphemes.length).toList(),
          keptGraphemes,
          reason: '$reason: kept "$kept" is not a grapheme prefix of the insertion',
        );
        // The surrounding draft may already be over the limit; only the
        // insertion is limited.
        expect(
          _bytes(result.text),
          lessThanOrEqualTo(max(maxBytes, _bytes('${split.head}${split.tail}'))),
          reason: reason,
        );
        if (keptGraphemes.length < insertedGraphemes.length) {
          final next = insertedGraphemes[keptGraphemes.length];
          expect(
            _bytes('${split.head}$kept$next${split.tail}'),
            greaterThan(maxBytes),
            reason: '$reason: one more grapheme would still fit',
          );
        }
        expect(result.selection.isCollapsed, isTrue, reason: reason);
        expect(
          result.selection.baseOffset,
          split.head.length + kept.length,
          reason: reason,
        );
        expect(result.composing, TextRange.empty, reason: reason);
        expect(_hasLoneSurrogate(result.text), isFalse, reason: reason);
      }
      expect(clipped, greaterThan(100));
    });

    test('a paste into the middle keeps both sides', () {
      const formatter = Utf8LengthLimitingTextInputFormatter(8);
      final result = formatter.formatEditUpdate(
        _value('abc' 'def', 3),
        _value('abc' 'XYZW' 'def', 7),
      );
      expect(result.text, 'abcXYdef');
      expect(result.selection.baseOffset, 5);
    });

    test('a paste over a selection drops the selection and keeps what fits',
        () {
      const formatter = Utf8LengthLimitingTextInputFormatter(6);
      const oldValue = TextEditingValue(
        text: 'abcdef',
        selection: TextSelection(baseOffset: 2, extentOffset: 4),
      );
      final result = formatter.formatEditUpdate(oldValue, _value('abXYZWef', 6));
      expect(result.text, 'abXYef');
      expect(result.selection.baseOffset, 4);
    });

    test('an emoji at the boundary is kept whole or not at all', () {
      // Two bytes left: the four-byte emoji does not fit, the letter after
      // it is not reached either, since the kept part is a prefix.
      const formatter = Utf8LengthLimitingTextInputFormatter(5);
      final result = formatter.formatEditUpdate(
        _value('abc'),
        _value('abc\u{1F600}d'),
      );
      expect(result.text, 'abc');
      expect(_hasLoneSurrogate(result.text), isFalse);

      // Four bytes left: the emoji fits, the letter after it does not.
      const wider = Utf8LengthLimitingTextInputFormatter(7);
      final kept = wider.formatEditUpdate(
        _value('abc'),
        _value('abc\u{1F600}d'),
      );
      expect(kept.text, 'abc\u{1F600}');
      expect(kept.selection.baseOffset, 5);
    });

    test('a combining mark stays with its base letter', () {
      const formatter = Utf8LengthLimitingTextInputFormatter(4);
      // "é" as e + combining acute is three bytes; with "ab" only two are
      // left, so the whole grapheme is dropped rather than the mark alone.
      final result = formatter.formatEditUpdate(
        _value('ab'),
        _value('abé'),
      );
      expect(result.text, 'ab');
    });
  });

  group('with an encoder', () {
    test('the limit is measured on the encoded text', () {
      const cyrillic = 'ппппппппппп';
      final shrinking = _CountingEncoder(_shrinkCyrillic);
      final withEncoder = Utf8LengthLimitingTextInputFormatter(
        10,
        encoder: shrinking.call,
      );
      expect(
        withEncoder.formatEditUpdate(_value(''), _value(cyrillic)).text,
        'пппппппппп',
      );
      expect(shrinking.calls, greaterThan(0));

      const plain = Utf8LengthLimitingTextInputFormatter(10);
      expect(
        plain.formatEditUpdate(_value(''), _value(cyrillic)).text,
        'ппппп',
      );

      final expanding = Utf8LengthLimitingTextInputFormatter(
        6,
        encoder: _expandA,
      );
      expect(
        expanding.formatEditUpdate(_value(''), _value('aaaa')).text,
        'aaa',
      );
    });

    test('a shrinking encoder still gives the longest fitting insertion',
        () {
      final random = Random(7);
      for (var i = 0; i < 300; i++) {
        final edit = _randomEdit(random);
        final maxBytes = 1 + random.nextInt(24);
        final formatter = Utf8LengthLimitingTextInputFormatter(
          maxBytes,
          encoder: _shrinkCyrillic,
        );
        int effective(String text) => _bytes(_shrinkCyrillic(text));
        final oldText = edit.oldValue.text;
        final newText = edit.newValue.text;
        final reason = 'limit $maxBytes, old "$oldText", new "$newText"';

        final result = formatter.formatEditUpdate(edit.oldValue, edit.newValue);

        if (effective(newText) <= maxBytes ||
            effective(newText) <= effective(oldText)) {
          expect(result.text, newText, reason: reason);
          continue;
        }
        final split = _split(oldText, newText);
        final kept = result.text.substring(
          split.head.length,
          result.text.length - split.tail.length,
        );
        final keptGraphemes = kept.characters.toList();
        final insertedGraphemes = split.inserted.characters.toList();
        expect(
          insertedGraphemes.take(keptGraphemes.length).toList(),
          keptGraphemes,
          reason: reason,
        );
        expect(
          effective(result.text),
          lessThanOrEqualTo(
            max(maxBytes, effective('${split.head}${split.tail}')),
          ),
          reason: reason,
        );
        if (keptGraphemes.length < insertedGraphemes.length) {
          final next = insertedGraphemes[keptGraphemes.length];
          expect(
            effective('${split.head}$kept$next${split.tail}'),
            greaterThan(maxBytes),
            reason: reason,
          );
        }
        expect(result.selection.baseOffset, split.head.length + kept.length);
      }
    });

    test('an encoder whose output can shrink as the text grows still gets '
        'a result that fits', () {
      final random = Random(11);
      for (var i = 0; i < 300; i++) {
        final edit = _randomEdit(random);
        final maxBytes = 1 + random.nextInt(24);
        final formatter = Utf8LengthLimitingTextInputFormatter(
          maxBytes,
          encoder: _nonMonotonic,
        );
        int effective(String text) => _bytes(_nonMonotonic(text));
        final oldText = edit.oldValue.text;
        final newText = edit.newValue.text;
        final reason = 'limit $maxBytes, old "$oldText", new "$newText"';

        final result = formatter.formatEditUpdate(edit.oldValue, edit.newValue);

        if (effective(newText) <= maxBytes ||
            effective(newText) <= effective(oldText)) {
          expect(result.text, newText, reason: reason);
          continue;
        }
        final split = _split(oldText, newText);
        expect(result.text, startsWith(split.head), reason: reason);
        expect(result.text, endsWith(split.tail), reason: reason);
        final kept = result.text.substring(
          split.head.length,
          result.text.length - split.tail.length,
        );
        expect(
          split.inserted.characters.take(kept.characters.length).toList(),
          kept.characters.toList(),
          reason: reason,
        );
        expect(
          effective(result.text),
          lessThanOrEqualTo(
            max(maxBytes, effective('${split.head}${split.tail}')),
          ),
          reason: reason,
        );
        expect(result.selection.baseOffset, split.head.length + kept.length);
        expect(_hasLoneSurrogate(result.text), isFalse, reason: reason);
      }
    });
  });
}
