import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/services.dart';

/// Keeps the draft within [maxBytes] of UTF-8, measured on the output of
/// [encoder] when there is one: the form the message will travel in. An
/// edit that fits, or that does not add bytes, passes as it is; one that
/// does not fit keeps the unchanged head and tail of the draft and as many
/// whole graphemes of the insertion as fit, the cursor after them.
///
/// The cut is found by binary search over the graphemes of the insertion,
/// about log2(n) encodings for a paste of n graphemes plus the two that
/// decide whether the edit fits at all, where a walk grapheme by grapheme
/// cost n: a paste of 260 Russian characters into an MCOtxt channel took
/// 475 encodings and most of a second on a desktop. The search only ever
/// keeps a count whose text it has encoded and found to fit, so the result
/// fits whatever the encoder does; what an encoder whose output can shrink
/// as the text grows is not promised is that no longer prefix would have
/// fit as well.
class Utf8LengthLimitingTextInputFormatter extends TextInputFormatter {
  final int maxBytes;
  final String Function(String)? encoder;

  const Utf8LengthLimitingTextInputFormatter(this.maxBytes, {this.encoder});

  int _effectiveByteLength(String text) {
    final effective = encoder != null ? encoder!(text) : text;
    return utf8.encode(effective).length;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (maxBytes <= 0) return oldValue;
    final newBytes = _effectiveByteLength(newValue.text);
    if (newBytes <= maxBytes ||
        newBytes <= _effectiveByteLength(oldValue.text)) {
      return newValue;
    }

    final oldText = oldValue.text;
    final newText = newValue.text;
    var prefix = 0;
    while (prefix < oldText.length &&
        prefix < newText.length &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }
    if (prefix > 0 &&
        prefix < newText.length &&
        _isLowSurrogate(newText.codeUnitAt(prefix))) {
      prefix--;
    }
    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < newText.length - prefix &&
        oldText.codeUnitAt(oldText.length - 1 - suffix) ==
            newText.codeUnitAt(newText.length - 1 - suffix)) {
      suffix++;
    }
    final suffixStart = newText.length - suffix;
    if (suffix > 0 && _isLowSurrogate(newText.codeUnitAt(suffixStart))) {
      suffix--;
    }

    final head = newText.substring(0, prefix);
    final tail = newText.substring(newText.length - suffix);
    final inserted = newText.substring(prefix, newText.length - suffix);

    final kept = _longestFittingPrefix(head, inserted, tail);
    final cursor = head.length + kept.length;
    return TextEditingValue(
      text: '$head$kept$tail',
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty,
    );
  }

  /// The longest prefix of whole graphemes of [inserted] that fits between
  /// [head] and [tail]. Binary search over the grapheme count: [fitting]
  /// only ever takes a count whose text was encoded and found to fit, and
  /// the whole insertion, which is the new text itself, is known not to
  /// fit, so nothing has to be checked after the loop.
  String _longestFittingPrefix(String head, String inserted, String tail) {
    // Where the first i graphemes of the insertion end, in code units.
    final ends = <int>[0];
    for (final grapheme in inserted.characters) {
      ends.add(ends.last + grapheme.length);
    }
    var fitting = 0;
    var notFitting = ends.length - 1;
    while (notFitting - fitting > 1) {
      final middle = (fitting + notFitting) ~/ 2;
      final candidate = inserted.substring(0, ends[middle]);
      if (_effectiveByteLength('$head$candidate$tail') <= maxBytes) {
        fitting = middle;
      } else {
        notFitting = middle;
      }
    }
    return inserted.substring(0, ends[fitting]);
  }

  bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}
