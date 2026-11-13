import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../helpers/meshcore_expanded_identity.dart';
import '../helpers/utf8_length_limiter.dart';
import '../storage/data_root_core.dart';
import '../storage/message_history_storage.dart';
import '../utils/keys.dart';

class AdditionalIdentityEntry {
  AdditionalIdentityEntry._(this.name, this.identity);

  final String name;
  final MeshCoreExpandedIdentity identity;

  static Future<AdditionalIdentityEntry> parse(String name, String key) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        utf8.encode(trimmed).length > maxRadioNameBytes ||
        RegExp(r'[\[\]\\:,?*\x00-\x1f]').hasMatch(trimmed)) {
      throw const FormatException('Invalid MeshCore identity name');
    }
    return AdditionalIdentityEntry._(
      trimmed,
      await MeshCoreExpandedIdentity.fromHex(key),
    );
  }

  Map<String, String> _toJson() => {
    'name': name,
    'key': identity.privateKeyHex,
  };
}

/// Stores one encrypted snapshot per userdata database. The verifier and
/// encryption key are independent HMAC outputs from a salted password KDF.
class AdditionalIdentityVault {
  AdditionalIdentityVault._(this._storage, this._serialized, this._secrets);

  static final _cipher = AesGcm.with256bits();
  static final _kdf = Pbkdf2.hmacSha256(iterations: 310000, bits: 256);
  static const _deviceStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(storageNamespace: 'mcoa_identity_vault_v1'),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final MessageHistoryStorage _storage;
  String? _serialized;
  _VaultSecrets _secrets;
  List<AdditionalIdentityEntry> _entries = const [];

  List<AdditionalIdentityEntry> get entries => _entries;

  static Future<AdditionalIdentityVault> open({
    required String password,
    required String? saved,
    MessageHistoryStorage? storage,
  }) async {
    if (password.isEmpty) throw const FormatException('Empty vault password');
    final history = storage ?? MessageHistoryStorage.instance;
    if (saved == null) {
      final secrets = await _derive(password, randomBytes(16));
      final vault = AdditionalIdentityVault._(history, null, secrets);
      await vault._persist(vault.entries, secrets);
      return vault;
    }

    final envelope = _readEnvelope(saved);
    final secrets = await _derive(password, _readBytes(envelope['salt'], 16));
    final verifier = _readBytes(envelope['verifier'], 32);
    var mismatch = 0;
    for (var i = 0; i < verifier.length; i++) {
      mismatch |= verifier[i] ^ secrets.verifier[i];
    }
    if (mismatch != 0) throw const FormatException('Incorrect vault password');
    return _decrypt(history, saved, envelope, secrets);
  }

  /// Returns null when the profile has no remembered key or the OS store is
  /// locked, absent, or has a stale entry. The password remains the fallback.
  static Future<AdditionalIdentityVault?> openRemembered({
    MessageHistoryStorage? storage,
  }) async {
    final history = storage ?? MessageHistoryStorage.instance;
    if (!history.hasDatabase) return null;
    try {
      final saved = await history.readAdditionalIdentityVault();
      if (saved == null) return null;
      final envelope = _readEnvelope(saved);
      final salt = _readBytes(envelope['salt'], 16);
      final key = await _deviceStorage.read(key: _deviceEntryKey(salt));
      if (key == null) return null;
      return await _decrypt(history, saved, envelope, (
        salt: salt,
        key: SecretKey(_readBytes(key, 32)),
        verifier: _readBytes(envelope['verifier'], 32),
      ));
    } catch (_) {
      return null;
    }
  }

  Future<bool> isUnlockRemembered() async {
    try {
      return await _deviceStorage.containsKey(
        key: _deviceEntryKey(_secrets.salt),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> setUnlockRemembered(bool remember) async {
    final slot = _deviceEntryKey(_secrets.salt);
    if (remember) {
      await _writeDeviceKey(_secrets);
    } else {
      await _deviceStorage.delete(key: slot);
    }
  }

  static Future<void> _writeDeviceKey(_VaultSecrets secrets) async {
    final slot = _deviceEntryKey(secrets.salt);
    final value = base64Encode(await secrets.key.extractBytes());
    await _deviceStorage.write(key: slot, value: value);
    if (await _deviceStorage.read(key: slot) != value) {
      throw StateError('Could not store the vault key on this device');
    }
  }

  static String _deviceEntryKey(List<int> salt) {
    final scope = jsonEncode([DataRoot.path, base64Encode(salt)]);
    final digest = crypto.sha256.convert(utf8.encode(scope));
    return 'mcoa_identity_vault_v1_$digest';
  }

  static Map<String, dynamic> _readEnvelope(String saved) {
    final envelope = jsonDecode(saved);
    if (envelope is! Map<String, dynamic> || envelope['version'] != 1) {
      throw const FormatException('Invalid identity vault');
    }
    return envelope;
  }

  static Future<AdditionalIdentityVault> _decrypt(
    MessageHistoryStorage history,
    String saved,
    Map<String, dynamic> envelope,
    _VaultSecrets secrets,
  ) async {
    final bytes = await _cipher.decrypt(
      SecretBox(
        _readBytes(envelope['ciphertext']),
        nonce: _readBytes(envelope['nonce'], 12),
        mac: Mac(_readBytes(envelope['tag'], 16)),
      ),
      secretKey: secrets.key,
    );
    final list = jsonDecode(utf8.decode(bytes));
    if (list is! List) throw const FormatException('Invalid identity entries');
    final entries = <AdditionalIdentityEntry>[];
    for (final entry in list) {
      if (entry is! Map || entry['name'] is! String || entry['key'] is! String) {
        throw const FormatException('Invalid identity entry');
      }
      entries.add(await AdditionalIdentityEntry.parse(
        entry['name'] as String,
        entry['key'] as String,
      ));
    }
    return AdditionalIdentityVault._(history, saved, secrets)
      .._entries = List.unmodifiable(entries);
  }

  Future<void> save(AdditionalIdentityEntry entry, {String? replacing}) async {
    final publicKey = entry.identity.publicKeyHex;
    if (entries.any((item) =>
        item.identity.publicKeyHex == publicKey && publicKey != replacing)) {
      throw const FormatException('Duplicate identity');
    }
    final next = entries.toList();
    final index = next.indexWhere((item) =>
        item.identity.publicKeyHex == replacing);
    if (index < 0) {
      next.add(entry);
    } else {
      next[index] = entry;
    }
    await _persist(next, _secrets);
  }

  Future<void> remove(String publicKey) => _persist(
    entries.where((entry) => entry.identity.publicKeyHex != publicKey).toList(),
    _secrets,
  );

  Future<void> changePassword(String password) async {
    if (password.isEmpty) throw const FormatException('Empty vault password');
    final previous = _secrets;
    final secrets = await _derive(password, randomBytes(16));
    final remember = await isUnlockRemembered();
    if (remember) await _writeDeviceKey(secrets);
    try {
      await _persist(entries, secrets);
    } catch (_) {
      if (remember) await _forgetDeviceKey(secrets);
      rethrow;
    }
    if (remember) await _forgetDeviceKey(previous);
  }

  static Future<void> _forgetDeviceKey(_VaultSecrets secrets) async {
    try {
      await _deviceStorage.delete(key: _deviceEntryKey(secrets.salt));
    } catch (_) {
      // A stale credential cannot open the current snapshot with a new salt.
    }
  }

  Future<void> _persist(
    List<AdditionalIdentityEntry> entries,
    _VaultSecrets secrets,
  ) async {
    final previous = _serialized;
    final plaintext = utf8.encode(jsonEncode([
      for (final entry in entries) entry._toJson(),
    ]));
    final box = await _cipher.encrypt(plaintext, secretKey: secrets.key);
    final serialized = jsonEncode({
      'version': 1,
      'salt': base64Encode(secrets.salt),
      'verifier': base64Encode(secrets.verifier),
      'nonce': base64Encode(box.nonce),
      'tag': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    });
    if (!await _storage.replaceAdditionalIdentityVault(previous, serialized)) {
      throw StateError('Identity vault changed during update');
    }
    _serialized = serialized;
    _entries = List.unmodifiable(entries);
    _secrets = secrets;
  }

  static List<int> _readBytes(Object? value, [int? length]) {
    if (value is! String) throw const FormatException('Invalid identity vault');
    final bytes = base64Decode(value);
    if (length != null && bytes.length != length) {
      throw const FormatException('Invalid identity vault');
    }
    return bytes;
  }

  static Future<_VaultSecrets> _derive(String password, List<int> salt) async {
    final master = await _kdf.deriveKeyFromPassword(password: password, nonce: salt);
    final hmac = Hmac.sha256();
    final encryption = await hmac.calculateMac(
      utf8.encode('meshcore.identity.vault.encryption.v1'),
      secretKey: master,
    );
    final verification = await hmac.calculateMac(
      utf8.encode('meshcore.identity.vault.verification.v1'),
      secretKey: master,
    );
    return (
      salt: salt,
      key: SecretKey(encryption.bytes),
      verifier: verification.bytes,
    );
  }
}

typedef _VaultSecrets = ({
  List<int> salt,
  SecretKey key,
  List<int> verifier,
});
