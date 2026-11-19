import 'dart:convert';
import 'dart:typed_data';

import 'meshcore_expanded_identity.dart';

/// A validated MeshCore private key with its derived public identity.
class BackupNodeIdentity {
  const BackupNodeIdentity._(this.identity);

  final MeshCoreExpandedIdentity identity;
  String get publicKey => identity.publicKeyHex;

  static Future<BackupNodeIdentity> read(
    Object? value, {
    required bool hexadecimal,
    required Iterable<Object?> publicKeys,
  }) async {
    if (value is! String || value.length > (hexadecimal ? 128 : 88)) {
      throw const FormatException('Invalid node identity backup');
    }
    final bytes = hexadecimal
        ? _readHex(value)
        : Uint8List.fromList(base64Decode(value));
    try {
      final identity = await MeshCoreExpandedIdentity.fromBytes(bytes);
      for (final key in publicKeys) {
        if (key == null || key == '') continue;
        if (key is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(key) ||
            identity.publicKeyHex != key.toLowerCase()) {
          throw const FormatException('Backup identity does not match its public key');
        }
      }
      return BackupNodeIdentity._(identity);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  static Uint8List _readHex(String value) {
    if (!RegExp(r'^[a-fA-F0-9]{128}$').hasMatch(value)) {
      throw const FormatException('Invalid node private key');
    }
    return Uint8List.fromList([
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ]);
  }
}

typedef BackupNodeIdentityPreview = ({
  Object session,
  String destinationKey,
  String destinationName,
  BackupNodeIdentity source,
});

enum BackupNodeIdentityStatus {
  completed,
  notReady,
  writeRejected,
  unsupported,
  unconfirmed,
  reconnectRequired,
}

typedef BackupNodeIdentityResult = ({
  bool written,
  BackupNodeIdentityStatus status,
});
