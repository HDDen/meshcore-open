import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class BackupPasswordException extends FormatException {
  const BackupPasswordException.required()
    : rejected = false,
      super('Password required');

  const BackupPasswordException.incorrectOrDamaged()
    : rejected = true,
      super('Wrong password or damaged backup');

  final bool rejected;
}

/// Reads and writes the upstream v1 backup envelope.
///
/// Section contents are validated by the restore plan before applying them.
class BackupFileCodec {
  const BackupFileCodec();

  static const _format = 'meshcore-open-backup';
  static const _encryptedFormat = 'meshcore-open-encrypted-backup';
  static const _version = 1;
  static const _kdf = 'PBKDF2-HMAC-SHA256';
  static const _cipher = 'AES-256-GCM';
  static const _iterations = 310000;
  static const _json = JsonEncoder.withIndent('  ');

  Future<String> encode(
    Map<String, Object?> payload, {
    required String password,
  }) async {
    _validatePayload(payload);
    if (password.isEmpty) return _json.convert(payload);

    final plaintext = utf8.encode(jsonEncode(payload));
    final random = Random.secure();
    final salt = List.generate(16, (_) => random.nextInt(256));
    final nonce = List.generate(12, (_) => random.nextInt(256));
    final key = await _deriveKey(password, salt, _iterations);
    final box = await AesGcm.with256bits().encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );
    return _json.convert({
      'format': _encryptedFormat,
      'version': _version,
      'kdf': _kdf,
      'iterations': _iterations,
      'cipher': _cipher,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    });
  }

  Future<Map<String, Object?>> decode(
    String contents, {
    required String password,
  }) async => decodeEnvelope(_decodeJson(contents), password: password);

  /// Decodes a parsed document so callers can dispatch between file formats.
  Future<Map<String, Object?>> decodeEnvelope(
    Object? decoded, {
    required String password,
  }) async {
    if (decoded is Map<String, Object?> &&
        decoded['format'] == _encryptedFormat) {
      return _decrypt(decoded, password);
    }
    return _validatePayload(decoded);
  }

  Future<Map<String, Object?>> _decrypt(
    Map<String, Object?> envelope,
    String password,
  ) async {
    if (envelope['version'] != _version ||
        envelope['kdf'] != _kdf ||
        envelope['cipher'] != _cipher) {
      throw const FormatException('Unsupported encrypted backup format');
    }
    final iterations = envelope['iterations'];
    if (iterations is! int || iterations < 100000 || iterations > 1000000) {
      throw const FormatException('Invalid password derivation settings');
    }
    if (password.isEmpty) throw const BackupPasswordException.required();
    final salt = _decodeField(envelope['salt'], length: 16);
    final nonce = _decodeField(envelope['nonce'], length: 12);
    final tag = _decodeField(envelope['tag'], length: 16);
    final ciphertext = _decodeField(envelope['ciphertext']);
    final key = await _deriveKey(password, salt, iterations);
    try {
      final plaintext = await AesGcm.with256bits().decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
        secretKey: key,
      );
      return _validatePayload(_decodeJson(utf8.decode(plaintext)));
    } on SecretBoxAuthenticationError {
      throw const BackupPasswordException.incorrectOrDamaged();
    } on FormatException {
      throw const FormatException('Invalid backup payload');
    }
  }

  static List<int> _decodeField(Object? field, {int? length}) {
    const invalid = FormatException('Invalid encrypted backup');
    if (field is! String || field.isEmpty) throw invalid;
    if (length != null && field.length > ((length + 2) ~/ 3) * 4) {
      throw invalid;
    }
    try {
      final bytes = base64Decode(field);
      if (length == null || bytes.length == length) return bytes;
    } on FormatException {
      throw invalid;
    }
    throw invalid;
  }

  static Object? _decodeJson(String contents) {
    try {
      return jsonDecode(contents);
    } on FormatException {
      throw const FormatException('Invalid backup JSON');
    }
  }

  static Map<String, Object?> _validatePayload(Object? payload) {
    if (payload is! Map<String, Object?> ||
        payload['format'] != _format ||
        payload['version'] != _version) {
      throw const FormatException('Invalid or unsupported backup file');
    }
    final items = payload['items'];
    final sections = payload['sections'];
    if (items is! List ||
        !items.every((item) => item is String) ||
        sections is! Map<String, Object?> ||
        !sections.values.every((section) => section is Map<String, Object?>)) {
      throw const FormatException('Invalid backup sections');
    }
    return payload;
  }

  static Future<SecretKey> _deriveKey(
    String password,
    List<int> salt,
    int iterations,
  ) => Pbkdf2.hmacSha256(
    iterations: iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
}
