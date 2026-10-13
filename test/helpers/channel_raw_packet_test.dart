import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/channel_echo_recovery.dart';
import 'package:meshcore_open/helpers/channel_raw_packet.dart';
import 'package:pointycastle/export.dart';

// The GRP_TXT packet the app sends through CMD_SEND_RAW_PACKET when a channel
// sends under a name of its own has to be the packet the firmware would
// build, byte for byte: the receivers decrypt it under the channel PSK, the
// repeaters filter it by the region's transport code, and the companion
// frame has to hold it.

Uint8List _psk() =>
    Uint8List.fromList(List<int>.generate(16, (i) => i * 7 + 1));

Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

/// The connector's `_decryptPayload`, repeated here as an independent
/// inverse of what the helper encrypts.
Uint8List? _decrypt(Uint8List psk, Uint8List encrypted) {
  final mac = encrypted.sublist(0, 2);
  final cipherText = encrypted.sublist(2);
  final key32 = Uint8List(32)..setRange(0, psk.length, psk);
  final hmac = crypto.Hmac(crypto.sha256, key32).convert(cipherText).bytes;
  if (hmac[0] != mac[0] || hmac[1] != mac[1]) return null;
  if (cipherText.isEmpty || cipherText.length % 16 != 0) return null;
  final cipher = ECBBlockCipher(AESEngine())
    ..init(false, KeyParameter(Uint8List.fromList(psk)));
  final out = Uint8List(cipherText.length);
  for (var i = 0; i < cipherText.length; i += 16) {
    cipher.processBlock(cipherText, i, out, i);
  }
  return out;
}

void main() {
  group('group text payload', () {
    test('is the channel hash, the MAC and the ciphertext', () {
      final psk = _psk();
      final plaintext = ChannelEchoRecovery.groupTextPlaintext(
        timestampSeconds: 0x01020304,
        senderName: 'Base',
        textBytes: _utf8('hi'),
      );
      final payload = ChannelRawPacket.groupTextPayload(
        psk: psk,
        plaintext: plaintext,
      );
      expect(payload[0], crypto.sha256.convert(psk).bytes[0]);
      expect(
        payload.sublist(1),
        ChannelEchoRecovery.encryptedPayloadFor(psk, plaintext),
      );
      final decrypted = _decrypt(psk, payload.sublist(1));
      expect(decrypted, isNotNull);
      expect(decrypted!.sublist(0, plaintext.length), plaintext);
      expect(
        utf8.decode(decrypted.sublist(5, plaintext.length)),
        'Base: hi',
      );
    });
  });

  group('flood packet', () {
    test('a plain flood: header, path byte with the hash width, payload', () {
      final packet = ChannelRawPacket.floodPacket(
        payloadType: payloadTypeGRPTXT,
        payload: Uint8List.fromList([9, 8, 7]),
        pathHashWidth: 2,
      );
      expect(packet, [
        (payloadTypeGRPTXT << 2) | ChannelRawPacket.routeFlood,
        0x40,
        9,
        8,
        7,
      ]);
    });

    test('a scoped flood carries the code little-endian, the second zero', () {
      final packet = ChannelRawPacket.floodPacket(
        payloadType: payloadTypeGRPTXT,
        payload: Uint8List.fromList([1]),
        pathHashWidth: 1,
        transportCode: 0xBEEF,
      );
      expect(packet, [
        (payloadTypeGRPTXT << 2) | ChannelRawPacket.routeTransportFlood,
        0xEF,
        0xBE,
        0,
        0,
        0x00,
        1,
      ]);
    });

    test('the hash width is clamped to the two bits of the path byte', () {
      Uint8List packet(int width) => ChannelRawPacket.floodPacket(
        payloadType: payloadTypeGRPTXT,
        payload: Uint8List(0),
        pathHashWidth: width,
      );
      expect(packet(0)[1], 0x00);
      expect(packet(4)[1], 0xC0);
      expect(packet(9)[1], 0xC0);
    });
  });

  group('transport code', () {
    test('is HMAC-SHA256 under the region key over type and payload', () {
      final payload = Uint8List.fromList([1, 2, 3]);
      final key = crypto.sha256
          .convert(utf8.encode('#ru-kda'))
          .bytes
          .sublist(0, 16);
      final digest = crypto.Hmac(
        crypto.sha256,
        key,
      ).convert([payloadTypeGRPTXT, 1, 2, 3]).bytes;
      final expected = digest[0] | (digest[1] << 8);
      expect(
        ChannelRawPacket.regionTransportCode(
          'ru-kda',
          payloadTypeGRPTXT,
          payload,
        ),
        expected,
      );
      expect(
        ChannelRawPacket.regionTransportCode(
          '#ru-kda',
          payloadTypeGRPTXT,
          payload,
        ),
        expected,
      );
      expect(expected, isNot(0));
      expect(expected, isNot(0xFFFF));
    });
  });

  group('send frame', () {
    test('is the command, the flood priority and the packet', () {
      expect(
        ChannelRawPacket.sendFrame(Uint8List.fromList([5, 6])),
        [cmdSendRawPacket, ChannelRawPacket.priority, 5, 6],
      );
    });

    test('a text at the budget fits the companion frame, one more does not', () {
      const name = 'Base';
      final budget =
          ChannelRawPacket.maxGroupTextBytes -
          channelSenderPrefixBytes(name);
      Uint8List frame(int textBytes) => ChannelRawPacket.groupTextFrame(
        psk: _psk(),
        timestampSeconds: 1,
        senderName: name,
        textBytes: _utf8('x' * textBytes),
        pathHashWidth: 1,
        region: 'ru-kda',
      );
      expect(frame(budget).length, 171);
      expect(frame(budget).length, lessThanOrEqualTo(maxFrameSize));
      expect(frame(budget + 1).length, greaterThan(maxFrameSize));
    });

    test('an unscoped frame carries no transport codes', () {
      final frame = ChannelRawPacket.groupTextFrame(
        psk: _psk(),
        timestampSeconds: 1,
        senderName: 'B',
        textBytes: _utf8('hi'),
        pathHashWidth: 1,
      );
      expect(frame[0], cmdSendRawPacket);
      expect(frame[2] & 0x03, ChannelRawPacket.routeFlood);
      expect(frame[2] >> 2, payloadTypeGRPTXT);
      expect(frame[3], 0x00);
      expect(frame[4], ChannelRawPacket.channelHash(_psk()));
    });

    test('a scoped frame codes the packet it carries', () {
      final frame = ChannelRawPacket.groupTextFrame(
        psk: _psk(),
        timestampSeconds: 1,
        senderName: 'B',
        textBytes: _utf8('hi'),
        pathHashWidth: 1,
        region: 'ru-kda',
      );
      expect(frame[2] & 0x03, ChannelRawPacket.routeTransportFlood);
      final payload = Uint8List.sublistView(frame, 8);
      final code = ChannelRawPacket.regionTransportCode(
        'ru-kda',
        payloadTypeGRPTXT,
        payload,
      );
      expect(frame[3] | (frame[4] << 8), code);
      expect(frame.sublist(5, 7), [0, 0]);
      expect(frame[7], 0x00);
    });
  });
}
