enum McotxtCodecError {
  invalidInput,
  unknownVersion,
  unknownLanguage,
  unexpectedEnd,
  invalidTop4Reference,
  invalidPrimaryId,
  invalidExtensionId,
  invalidPunctuationId,
  toggleWithoutLanguageB,
  invalidShift,
  unknownExtendedControl,
  invalidOtherLanguage,
  invalidUtf8Fallback,
  invalidRawUtf8,
  unsupportedExtendedHeader,
}

class McotxtCodecException implements Exception {
  final McotxtCodecError code;
  final String message;

  const McotxtCodecException(this.code, this.message);

  @override
  String toString() => 'McotxtCodecException($code): $message';
}
