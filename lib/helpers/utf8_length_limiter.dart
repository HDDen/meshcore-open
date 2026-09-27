import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/services.dart';

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

    final kept = StringBuffer();
    for (final char in inserted.characters) {
      if (_effectiveByteLength('$head$kept$char$tail') > maxBytes) break;
      kept.write(char);
    }

    final cursor = head.length + kept.length;
    return TextEditingValue(
      text: '$head$kept$tail',
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty,
    );
  }

  bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}
