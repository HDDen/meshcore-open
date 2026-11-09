import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Sign the advert envelope in place, excluding the radio wrapper and path.
Future<Uint8List> signAdvertFixture(
  Uint8List bytes,
  SimpleKeyPair keys, {
  int payloadOffset = 0,
}) async {
  final signatureStart = payloadOffset + 36;
  final appDataStart = signatureStart + 64;
  final signature = await Ed25519().sign([
    ...bytes.sublist(payloadOffset, signatureStart),
    ...bytes.sublist(appDataStart, min(bytes.length, appDataStart + 32)),
  ], keyPair: keys);
  return bytes..setRange(signatureStart, appDataStart, signature.bytes);
}
