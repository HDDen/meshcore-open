import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const int _publicKeySize = 32;
const int _signatureStart = _publicKeySize + 4;
const int _signatureSize = 64;
const int advertAppDataOffset = _signatureStart + _signatureSize;
const int _maxAppDataSize = 32;

const int _maxCachedSignatures = 256;
final _ed25519 = Ed25519();
final _verifiedAdverts = <String, Future<bool>>{};

/// Mesh::onRecvPacket caps app_data before both verification and parsing.
Uint8List boundedAdvertPayload(Uint8List payload) {
  const limit = advertAppDataOffset + _maxAppDataSize;
  return payload.length <= limit
      ? payload
      : Uint8List.sublistView(payload, 0, limit);
}

Future<bool> verifyAdvertSignature(Uint8List payload) {
  final envelope = boundedAdvertPayload(payload);
  if (envelope.length <= advertAppDataOffset) return Future.value(false);

  // A relay changes the route, not this envelope. Include every signed byte
  // as well as the signature so a modified packet cannot reuse the result.
  final key = base64Encode(envelope);
  final cached = _verifiedAdverts[key];
  if (cached != null) return cached;
  if (_verifiedAdverts.length == _maxCachedSignatures) {
    _verifiedAdverts.remove(_verifiedAdverts.keys.first);
  }
  return _verifiedAdverts[key] = _verify(envelope);
}

Future<bool> _verify(Uint8List envelope) async {
  final signedLength = envelope.length - _signatureSize;
  final message = Uint8List(signedLength)
    ..setRange(0, _signatureStart, envelope)
    ..setRange(_signatureStart, signedLength, envelope, advertAppDataOffset);
  final signature = Signature(
    envelope.sublist(_signatureStart, advertAppDataOffset),
    publicKey: SimplePublicKey(
      envelope.sublist(0, _publicKeySize),
      type: KeyPairType.ed25519,
    ),
  );
  try {
    return await _ed25519.verify(message, signature: signature);
  } catch (_) {
    return false;
  }
}
