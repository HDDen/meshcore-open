import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'direct_echo_crypto.dart';

/// A MeshCore identity holds the clamped SHA-512 expansion of an Ed25519
/// seed. The 64-byte radio export is not a seed or a seed/public-key pair.
class MeshCoreExpandedIdentity {
  MeshCoreExpandedIdentity._(this._expanded, this._publicKey);

  final Uint8List _expanded;
  final Uint8List _publicKey;

  Uint8List get publicKey => Uint8List.fromList(_publicKey);
  String get publicKeyHex => hex.encode(_publicKey);
  String get privateKeyHex => hex.encode(_expanded);
  String get maskedPrivateKey => '${hex.encode(_expanded.sublist(0, 3))}******';

  static Future<MeshCoreExpandedIdentity> fromHex(String value) async {
    final normalized = value.trim();
    if (!RegExp(r'^[a-fA-F0-9]{128}$').hasMatch(normalized)) {
      throw const FormatException('Expected a 64-byte MeshCore private key');
    }
    final expanded = Uint8List.fromList(hex.decode(normalized));
    try {
      if ((expanded[0] & 7) != 0 || (expanded[31] & 0xc0) != 0x40) {
        throw const FormatException('Invalid MeshCore private key scalar');
      }
      final algorithm = DartEd25519(sha512: _ExpandedSeedHash(expanded));
      final placeholder = await algorithm.newKeyPairFromSeed(Uint8List(32));
      try {
        final publicKey = (await placeholder.extractPublicKey()).bytes;
        if (publicKey.first == 0 || publicKey.first == 0xff) {
          throw const FormatException('Reserved MeshCore public key prefix');
        }
        return MeshCoreExpandedIdentity._(
          Uint8List.fromList(expanded),
          Uint8List.fromList(publicKey),
        );
      } finally {
        placeholder.destroy();
      }
    } finally {
      expanded.fillRange(0, expanded.length, 0);
    }
  }

  Uint8List sharedSecret(Uint8List peerPublicKey) =>
      DirectEchoCrypto.sharedSecret(_expanded, peerPublicKey);

  Future<Uint8List> sign(List<int> message) async {
    final publicKey = SimplePublicKey(_publicKey, type: KeyPairType.ed25519);
    final placeholder = SimpleKeyPairData(
      Uint8List(32),
      publicKey: publicKey,
      type: KeyPairType.ed25519,
    );
    try {
      final algorithm = DartEd25519(sha512: _ExpandedSeedHash(_expanded));
      final signature = await algorithm.sign(message, keyPair: placeholder);
      return Uint8List.fromList(signature.bytes);
    } finally {
      placeholder.destroy();
    }
  }
}

/// DartEd25519 exposes its SHA-512 implementation for injection. For a single
/// operation, supply the radio's expansion in place of hashing a seed. The
/// nonce and challenge hashes still use standard SHA-512. Each operation
/// creates its own adapter, so simultaneous signatures cannot share state.
class _ExpandedSeedHash extends DartSha512 {
  _ExpandedSeedHash(this._expanded);

  final Uint8List _expanded;
  bool _expandSeed = true;

  @override
  Future<Hash> hash(List<int> input) async {
    if (!_expandSeed) return super.hash(input);
    if (input.length != 32 || input.any((byte) => byte != 0)) {
      throw StateError('Unexpected Ed25519 seed expansion');
    }
    _expandSeed = false;
    return Hash(_expanded);
  }
}
