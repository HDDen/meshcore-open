import 'dart:convert';

import 'package:flutter/services.dart';

class Utf8LengthLimitingTextInputFormatter extends TextInputFormatter {
  final int maxBytes;
  final String Function(String) transformText;

  const Utf8LengthLimitingTextInputFormatter(
    this.maxBytes, {
    this.transformText = _identity,
  });

  static String _identity(String text) => text;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (maxBytes <= 0) return oldValue;
    final bytes = utf8.encode(transformText(newValue.text));
    if (bytes.length <= maxBytes) return newValue;

    final truncated = _truncateToMaxBytes(newValue.text, maxBytes);
    return TextEditingValue(
      text: truncated,
      selection: TextSelection.collapsed(offset: truncated.length),
      composing: TextRange.empty,
    );
  }

  String _truncateToMaxBytes(String text, int limit) {
    final buffer = StringBuffer();
    var used = 0;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final transformedChar = transformText(char);
      final charBytes = utf8.encode(transformedChar).length;
      if (used + charBytes > limit) break;
      buffer.write(char);
      used += charBytes;
    }
    return buffer.toString();
  }
}
