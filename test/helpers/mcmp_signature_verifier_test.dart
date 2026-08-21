import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/mcmp_app_codec.dart';
import 'package:meshcore_open/helpers/mcmp_signature_verifier.dart';
import 'package:meshcore_open/models/contact.dart';

void main() {
  group('MCMP channel sender identity', () {
    const outerSenderName = 'Alice';
    const embeddedSenderName = 'Mallory';
    const text = 'signed message';
    const timestamp = 1_700_000_000;
    final channelPsk = Uint8List.fromList(List<int>.generate(16, (i) => i));

    late SimpleKeyPair keyPair;
    late Contact contact;

    setUp(() async {
      keyPair = await Ed25519().newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      contact = Contact(
        publicKey: Uint8List.fromList(publicKey.bytes),
        name: embeddedSenderName,
        type: advTypeChat,
        pathLength: 0,
        path: Uint8List(0),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
      );
    });

    test(
      'rejects a signed embedded name that differs from the transport',
      () async {
        final canonical = McmpAppCodec.canonicalSigningBytes(
          context: McmpSigningContext.channel,
          binding: McmpAppCodec.channelSigningBinding(channelPsk),
          senderName: embeddedSenderName,
          timestamp: timestamp,
          flags: McmpAppCodec.packFlags(
            hasReply: false,
            isSigned: true,
            hasSenderName: true,
          ),
          text: text,
        );
        final signature = await Ed25519().sign(canonical, keyPair: keyPair);
        final message = DecodedMcmpAppMessage(
          text: text,
          timestamp: timestamp,
          senderName: embeddedSenderName,
          signature: Uint8List.fromList(signature.bytes),
        );

        final result = await McmpSignatureVerifier.verifyChannelMessage(
          message: message,
          senderName: outerSenderName,
          channelPsk: channelPsk,
          contacts: [contact],
        );

        expect(result.status, McmpSignatureStatus.invalid);
        expect(result.verifiedSenderKeyHex, isNull);
      },
    );

    test('accepts matching embedded and transport names', () async {
      final canonical = McmpAppCodec.canonicalSigningBytes(
        context: McmpSigningContext.channel,
        binding: McmpAppCodec.channelSigningBinding(channelPsk),
        senderName: embeddedSenderName,
        timestamp: timestamp,
        flags: McmpAppCodec.packFlags(
          hasReply: false,
          isSigned: true,
          hasSenderName: true,
        ),
        text: text,
      );
      final signature = await Ed25519().sign(canonical, keyPair: keyPair);
      final message = DecodedMcmpAppMessage(
        text: text,
        timestamp: timestamp,
        senderName: embeddedSenderName,
        signature: Uint8List.fromList(signature.bytes),
      );

      final result = await McmpSignatureVerifier.verifyChannelMessage(
        message: message,
        senderName: embeddedSenderName,
        channelPsk: channelPsk,
        contacts: [contact],
      );

      expect(result.status, McmpSignatureStatus.valid);
      expect(result.verifiedSenderKeyHex, contact.publicKeyHex);
    });
  });
}
