import 'dart:convert';
import 'dart:typed_data';

/// Wire API локальной консоли, без LoRa destination/envelope.
const companionCliCommandCode = 66;
const companionCliReplyCode = 29;
const companionCliOrderKey = 'service:companion-cli';
const companionCliTimeout = Duration(seconds: 15);

class CompanionCliException implements Exception {
  const CompanionCliException(this.code);
  final String code;
  @override
  String toString() => 'CompanionCLI: $code';
}

/// В одном процессе идентификаторы не переиспользуются, даже после timeout.
/// При исчерпании отказываем до отправки, а не принимаем старый ответ за новый.
class CompanionCliTags {
  static const _alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  int _next = 0;
  String allocate() {
    if (_next >= _alphabet.length * _alphabet.length) {
      throw const CompanionCliException('tagExhausted');
    }
    final value = _next++;
    return '${_alphabet[value ~/ _alphabet.length]}${_alphabet[value % _alphabet.length]}';
  }
}

Uint8List buildCompanionCliFrame(String command, String prefix) {
  final text = command.replaceFirst(RegExp(r'^ +'), '');
  final bytes = utf8.encode(text);
  if (bytes.length < 2 || text.contains('\u0000') ||
      text.contains('\r') || text.contains('\n') ||
      !RegExp(r'^[0-9A-Za-z]{2}$').hasMatch(prefix)) {
    throw const CompanionCliException('invalidCommand');
  }
  if (bytes.length > 172 ||
      (text.startsWith('set radio ') && utf8.encode(text.substring(10)).length > 131)) {
    throw const CompanionCliException('tooLong');
  }
  return Uint8List.fromList([companionCliCommandCode, ...prefix.codeUnits, 0x7c, ...bytes]);
}

bool companionCliReplyMatches(Uint8List frame, String prefix) =>
    frame.length >= 4 && frame[0] == companionCliReplyCode &&
    frame[1] == prefix.codeUnitAt(0) && frame[2] == prefix.codeUnitAt(1) && frame[3] == 0x7c;

String companionCliReplyText(Uint8List frame) => utf8.decode(frame.sublist(4), allowMalformed: true);
