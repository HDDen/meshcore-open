enum MCOtxtCodecError {
  invalidInput,
  unknownVersion,
  unknownLanguage,
  modelUnavailable,
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

class MCOtxtCodecException implements Exception {
  final MCOtxtCodecError code;
  final String message;

  const MCOtxtCodecException(this.code, this.message);

  @override
  String toString() => 'MCOtxtCodecException($code): $message';
}
