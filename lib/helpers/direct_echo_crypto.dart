import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// The two computations the firmware makes for a direct message that the app
/// repeats when it decrypts one itself from a raw RX-log copy: the shared
/// secret of `LocalIdentity::calcSharedSecret` and the ACK hash of
/// `BaseChatMesh::onPeerDataRecv`. The MAC-then-decrypt step is the same
/// `Utils::MACThenDecrypt` the channel decoder already implements.
///
/// Pure Dart on purpose: it handles secret material, and it is checked by a
/// script run outside the Flutter test runner.
abstract final class DirectEchoCrypto {
  /// `PRV_KEY_SIZE`: the orlp ed25519 private key, SHA-512 of the seed with
  /// the low half clamped. Only that low half is the X25519 scalar.
  static const int privateKeyLength = 64;
  static const int publicKeyLength = 32;
  static const int sharedSecretLength = 32;
  static const int ackLength = 6;

  static final BigInt _p = (BigInt.one << 255) - BigInt.from(19);

  /// X25519 as `ed25519_key_exchange` does it: the scalar is the first 32
  /// bytes of the private key (clamped again, which is idempotent) and the
  /// peer's Edwards y becomes Montgomery u = (1 + y) / (1 - y) mod p.
  static Uint8List sharedSecret(Uint8List privateKey, Uint8List peerPublicKey) {
    if (privateKey.length < 32) {
      throw ArgumentError('Private key must carry at least 32 bytes');
    }
    if (peerPublicKey.length != publicKeyLength) {
      throw ArgumentError('Public key must be $publicKeyLength bytes');
    }
    final scalar = Uint8List.fromList(privateKey.sublist(0, 32));
    final keyPair = SimpleKeyPairData(
      scalar,
      // Never read: the exchange needs only the scalar and the peer's point.
      publicKey: SimplePublicKey(Uint8List(32), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    try {
      final secret = const DartX25519().sharedSecretSync(
        keyPairData: keyPair,
        remotePublicKey: SimplePublicKey(
          edwardsToMontgomery(peerPublicKey),
          type: KeyPairType.x25519,
        ),
      );
      final bytes = Uint8List.fromList((secret as SecretKeyData).bytes);
      secret.destroy();
      return bytes;
    } finally {
      keyPair.destroy();
      scalar.fillRange(0, scalar.length, 0);
    }
  }

  /// Montgomery u-coordinate of an Ed25519 public key, little-endian; the
  /// top bit of the encoding (sign of x) is not part of y and is dropped.
  static Uint8List edwardsToMontgomery(Uint8List edwardsPublicKey) {
    var y = BigInt.zero;
    for (var i = edwardsPublicKey.length - 1; i >= 0; i--) {
      y = (y << 8) | BigInt.from(edwardsPublicKey[i]);
    }
    y &= (BigInt.one << 255) - BigInt.one;
    final oneMinusY = (BigInt.one - y) % _p;
    if (oneMinusY == BigInt.zero) {
      throw ArgumentError('Public key has no Montgomery form');
    }
    final u = (BigInt.one + y) * oneMinusY.modInverse(_p) % _p;
    final out = Uint8List(32);
    var rest = u;
    for (var i = 0; i < 32; i++) {
      out[i] = (rest & BigInt.from(0xFF)).toInt();
      rest >>= 8;
    }
    return out;
  }

  /// The six ACK bytes for a plain text message, as `BaseChatMesh` builds
  /// them: SHA-256 over the plaintext up to the end of the text (timestamp,
  /// flags, text) and the sender's public key, truncated to four bytes; then
  /// the extended attempt byte that follows the text's NUL, when the
  /// plaintext carries one; then one random byte so repeats hash differently.
  /// [plaintext] is the whole decrypted block, zero padding included.
  static Uint8List ackHash(
    Uint8List plaintext,
    int textLength,
    Uint8List senderPublicKey, {
    required int randomByte,
  }) {
    final signedLength = 5 + textLength;
    if (signedLength > plaintext.length) {
      throw ArgumentError('Text runs past the plaintext');
    }
    final input = Uint8List(signedLength + senderPublicKey.length)
      ..setRange(0, signedLength, plaintext)
      ..setRange(signedLength, signedLength + senderPublicKey.length,
          senderPublicKey);
    final digest = crypto.sha256.convert(input).bytes;
    final extendedAttemptIndex = signedLength + 1;
    final ack = Uint8List(ackLength)
      ..setRange(0, 4, digest)
      ..[4] = extendedAttemptIndex < plaintext.length
          ? plaintext[extendedAttemptIndex]
          : 0
      ..[5] = randomByte & 0xFF;
    return ack;
  }

  /// The text of a decrypted TXT_MSG plaintext: bytes 5.. up to the first NUL,
  /// which the AES zero padding guarantees unless the text fills the block.
  static int textLength(Uint8List plaintext) {
    var end = 5;
    while (end < plaintext.length && plaintext[end] != 0) {
      end++;
    }
    return end - 5;
  }
}
