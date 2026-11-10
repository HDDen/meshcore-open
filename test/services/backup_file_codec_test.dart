import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';

const _payload = <String, Object?>{
  'format': 'meshcore-open-backup',
  'version': 1,
  'sourcePublicKey': '',
  'items': ['appSettings'],
  'sections': {
    'appSettings': {
      'preferences': {
        'app_settings': {'theme_mode': 'dark'},
      },
    },
  },
};

// Synthetic v1 payload encrypted independently using Node's crypto module.
const _encrypted = <String, Object?>{
  'format': 'meshcore-open-encrypted-backup',
  'version': 1,
  'kdf': 'PBKDF2-HMAC-SHA256',
  'iterations': 310000,
  'cipher': 'AES-256-GCM',
  'salt': 'ABEiM0RVZneImaq7zN3u/w==',
  'nonce': '/+7dzLuqmYh3ZlVE',
  'ciphertext':
      'sOOCwi92sHiNDHFin6OjrVifzG7F3HzqTdJec3DSAOoA53Z8rcPu8VZmyhv3'
      'GPPZ8S2a0zdy+7m6aejz9xcPULkXb2rUNiF7CTOOlRozwRY3VHmvaNtFP1'
      'NfaOE/mUe8mfPgEoEq/z1nODXRyh7X9ahiI1mgBdGycB3+HhImmKJtFn10'
      'l1HyIPLZSi6kFvFy/MwpbLoROKpo4R25gfJI5GviPlBbdo/v8cbU4g==',
  'tag': 'HJfreUMmJ4HF4pW0YCdd1A==',
};

void main() {
  const codec = BackupFileCodec();
  const password = 'fixture-password';

  test('reads and writes an upstream plaintext v1 backup', () async {
    expect(await codec.decode(jsonEncode(_payload), password: ''), _payload);
    expect(jsonDecode(await codec.encode(_payload, password: '')), _payload);
  });

  test('reads an independently encrypted upstream v1 backup', () async {
    expect(
      await codec.decode(jsonEncode(_encrypted), password: password),
      _payload,
    );
  });

  test('writes an authenticated envelope with no plaintext sections', () async {
    final encoded = await codec.encode(_payload, password: password);
    final envelope = jsonDecode(encoded) as Map<String, Object?>;
    expect(envelope['format'], _encrypted['format']);
    expect(envelope['version'], _encrypted['version']);
    expect(envelope['kdf'], _encrypted['kdf']);
    expect(envelope['cipher'], _encrypted['cipher']);
    expect(envelope['iterations'], _encrypted['iterations']);
    expect(envelope, isNot(contains('sections')));
    expect(encoded, isNot(contains('theme_mode')));
    expect(await codec.decode(encoded, password: password), _payload);
  });

  test('rejects a missing password, a wrong password, and a damaged tag',
      () async {
    final encoded = jsonEncode(_encrypted);
    await expectLater(codec.decode(encoded, password: ''), throwsFormatException);
    await expectLater(
      codec.decode(encoded, password: 'wrong-password'),
      throwsFormatException,
    );
    await expectLater(
      codec.decode(
        jsonEncode({..._encrypted, 'tag': 'AJfreUMmJ4HF4pW0YCdd1A=='}),
        password: password,
      ),
      throwsFormatException,
    );
  });

  test('rejects unsupported headers and malformed sections', () async {
    for (final invalid in [
      {..._payload, 'version': 2},
      {..._payload, 'items': [true]},
      {..._payload, 'sections': {'appSettings': []}},
      {..._encrypted, 'iterations': 1000001},
      {..._encrypted, 'salt': 'invalid base64!'},
      {..._encrypted, 'nonce': 'AA=='},
    ]) {
      await expectLater(
        codec.decode(jsonEncode(invalid), password: password),
        throwsFormatException,
      );
    }
  });

  test('parse errors omit backup contents', () async {
    await expectLater(
      codec.decode('{"privateKey":"fixture-secret"', password: ''),
      throwsA(
        isA<FormatException>().having(
          (error) => error.source,
          'source',
          isNull,
        ),
      ),
    );
  });
}
