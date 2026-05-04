import 'package:flutter/services.dart';

class NewlineToSpaceFormatter extends TextInputFormatter {
  const NewlineToSpaceFormatter();

  static final RegExp _newlinePattern = RegExp(r'[\r\n]+');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = newValue.text.replaceAll(_newlinePattern, ' ');
    if (normalized == newValue.text) {
      return newValue;
    }
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
      composing: TextRange.empty,
    );
  }
}
