import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/additional_identity_advert.dart';
import 'package:meshcore_open/helpers/meshcore_expanded_identity.dart';

const _seedHex =
    '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
const _publicKeyHex =
    'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';
const _emptySignature =
    'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
    '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b';

Future<MeshCoreExpandedIdentity> _identity() async {
  final expanded = Uint8List.fromList(
    (await Sha512().hash(hex.decode(_seedHex))).bytes,
  );
  expanded[0] &= 248;
  expanded[31] = (expanded[31] & 63) | 64;
  return MeshCoreExpandedIdentity.fromHex(hex.encode(expanded));
}

void main() {
  test('MeshCore expansion derives and signs the RFC 8032 test vector', () async {
    final identity = await _identity();
    expect(identity.publicKeyHex, _publicKeyHex);
    expect(hex.encode(await identity.sign([])), _emptySignature);
    await expectLater(
      MeshCoreExpandedIdentity.fromHex(_seedHex),
      throwsFormatException,
    );
    await expectLater(
      MeshCoreExpandedIdentity.fromHex('00' * 64),
      throwsFormatException,
    );
  });

  test('Flood advert signs the firmware payload for the additional key', () async {
    final identity = await _identity();
    final frame = await buildAdditionalIdentityFloodAdvert(
      identity: identity,
      name: 'Relay test',
      timestampSeconds: 0x12345678,
      pathHashWidth: 3,
    );
    expect(frame.take(4), [cmdSendRawPacket, 3, 0x11, 0x80]);
    expect(hex.encode(frame.sublist(4, 36)), _publicKeyHex);
    expect(frame.sublist(36, 40), [0x78, 0x56, 0x34, 0x12]);
    expect(frame[104], 0x81);
    expect(utf8.decode(frame.sublist(105)), 'Relay test');
    expect(frame.length, lessThanOrEqualTo(maxFrameSize));
    final signature = Signature(
      frame.sublist(40, 104),
      publicKey: SimplePublicKey(
        hex.decode(_publicKeyHex),
        type: KeyPairType.ed25519,
      ),
    );
    expect(
      await Ed25519().verify(
        [...frame.sublist(4, 40), ...frame.sublist(104)],
        signature: signature,
      ),
      isTrue,
    );
  });
}
