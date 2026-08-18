import 'package:flutter/services.dart';

/// Caps how much text a single edit may add, so pasting a long block into a
/// compression-limited composer cannot blow past the payload budget in one
/// keystroke.
class InsertedTextLimiter extends TextInputFormatter {
  const InsertedTextLimiter({this.maxInsertedChars = 600});

  final int maxInsertedChars;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final capped = _capInsertedText(oldValue.text, newValue.text);
    if (identical(capped, newValue.text)) return newValue;

    return TextEditingValue(
      text: capped,
      selection: TextSelection.collapsed(offset: capped.length),
      composing: TextRange.empty,
    );
  }

  String _capInsertedText(String oldText, String newText) {
    if (oldText == newText) return newText;

    var prefixLength = 0;
    final maxPrefixLength = oldText.length < newText.length
        ? oldText.length
        : newText.length;
    while (prefixLength < maxPrefixLength &&
        oldText.codeUnitAt(prefixLength) == newText.codeUnitAt(prefixLength)) {
      prefixLength++;
    }

    var suffixLength = 0;
    final oldRemaining = oldText.length - prefixLength;
    final newRemaining = newText.length - prefixLength;
    while (suffixLength < oldRemaining &&
        suffixLength < newRemaining &&
        oldText.codeUnitAt(oldText.length - 1 - suffixLength) ==
            newText.codeUnitAt(newText.length - 1 - suffixLength)) {
      suffixLength++;
    }

    final insertedEnd = newText.length - suffixLength;
    final inserted = newText.substring(prefixLength, insertedEnd);
    final limit = maxInsertedChars < 0 ? 0 : maxInsertedChars;
    if (inserted.length <= limit) return newText;

    return newText.replaceRange(
      prefixLength,
      insertedEnd,
      inserted.substring(0, limit),
    );
  }
}
