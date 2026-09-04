import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/channel_echo_recovery.dart';
import 'package:pointycastle/export.dart';

Uint8List _psk() => Uint8List.fromList(List<int>.generate(16, (i) => i * 7 + 1));

/// The connector's `_decryptPayload`, repeated here so the helper is checked
/// against an independent inverse rather than against itself.
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

Uint8List _ascii(String text) => Uint8List.fromList(text.codeUnits);

void main() {
  group('plaintext layouts', () {
    test('group text follows sendGroupMessage', () {
      final plaintext = ChannelEchoRecovery.groupTextPlaintext(
        timestampSeconds: 0x01020304,
        senderName: 'Bob',
        textBytes: _ascii('hi'),
      );
      expect(plaintext, [0x04, 0x03, 0x02, 0x01, 0, ...'Bob: hi'.codeUnits]);
    });

    test('group text is cut so that name and text stay within 160 bytes', () {
      final plaintext = ChannelEchoRecovery.groupTextPlaintext(
        timestampSeconds: 0,
        senderName: 'Bob',
        textBytes: Uint8List.fromList(List<int>.filled(200, 0x61)),
      );
      expect(plaintext.length, 5 + ChannelEchoRecovery.maxGroupTextBytes);
      expect(plaintext.sublist(5, 10), 'Bob: '.codeUnits);
    });

    test('group data follows sendGroupData', () {
      final plaintext = ChannelEchoRecovery.groupDataPlaintext(
        dataType: 0x0120,
        payload: Uint8List.fromList([1, 2, 3]),
      );
      expect(plaintext, [0x20, 0x01, 3, 1, 2, 3]);
    });
  });

  group('encryptedPayloadFor', () {
    test('decrypts back through the receive-side inverse', () {
      final psk = _psk();
      final plaintext = ChannelEchoRecovery.groupTextPlaintext(
        timestampSeconds: 1700000000,
        senderName: 'Bob',
        textBytes: _ascii('a plaintext that spans several blocks of AES'),
      );
      final encrypted = ChannelEchoRecovery.encryptedPayloadFor(psk, plaintext);

      final blocks = (plaintext.length + 15) ~/ 16;
      expect(encrypted.length, 2 + blocks * 16);
      final decrypted = _decrypt(psk, encrypted);
      expect(decrypted, isNotNull);
      expect(decrypted!.sublist(0, plaintext.length), plaintext);
      expect(
        decrypted.sublist(plaintext.length),
        everyElement(0),
        reason: 'the firmware pads the last block with zeros',
      );
    });

    test('a different key does not verify', () {
      final plaintext = ChannelEchoRecovery.groupDataPlaintext(
        dataType: 1,
        payload: _ascii('payload'),
      );
      final encrypted = ChannelEchoRecovery.encryptedPayloadFor(
        _psk(),
        plaintext,
      );
      final otherKey = Uint8List.fromList(_psk())..[0] ^= 0xFF;
      expect(_decrypt(otherKey, encrypted), isNull);
    });
  });

  group('echo budget', () {
    test('a first-hop echo fits the RX log up to ten whole blocks', () {
      for (final transportCodes in [false, true]) {
        for (final width in [1, 2, 3, 4]) {
          expect(
            ChannelEchoRecovery.plaintextBytesOverEchoLimit(
              plaintextLength: 160,
              pathHashWidth: width,
              transportCodes: transportCodes,
            ),
            isNull,
            reason: 'width $width, transport $transportCodes',
          );
          expect(
            ChannelEchoRecovery.plaintextBytesOverEchoLimit(
              plaintextLength: 165,
              pathHashWidth: width,
              transportCodes: transportCodes,
            ),
            5,
            reason: 'width $width, transport $transportCodes',
          );
        }
      }
      expect(
        ChannelEchoRecovery.plaintextBytesOverEchoLimit(plaintextLength: 161),
        1,
      );
    });

    test('a wider path lowers the budget a whole block at a time', () {
      // Two hops of four bytes with a scope: 173 - 17 = 156 -> nine blocks.
      expect(
        ChannelEchoRecovery.plaintextBytesOverEchoLimit(
          plaintextLength: 150,
          pathHashWidth: 8,
          transportCodes: true,
        ),
        6,
      );
    });

    test('group text plaintext counts the name prefix and the header', () {
      expect(
        ChannelEchoRecovery.groupTextPlaintextLength(
          senderPrefixBytes: 5,
          textBytes: 155,
        ),
        165,
      );
    });
  });

  group('registerOutgoingFrame', () {
    final psk = _psk();
    Uint8List? pskFor(int index) => index == 3 ? psk : null;

    test('registers a channel text frame and recovers a cut copy', () {
      final recovery = ChannelEchoRecovery();
      final text = 'x' * 150;
      final frame = buildSendChannelTextMsgFrame(
        3,
        text,
        timestampSeconds: 1234,
      );
      expect(
        recovery.registerOutgoingFrame(
          frame,
          pskFor: pskFor,
          senderName: 'Bob',
        ),
        isTrue,
      );
      expect(recovery.length, 1);

      final expected = ChannelEchoRecovery.encryptedPayloadFor(
        psk,
        ChannelEchoRecovery.groupTextPlaintext(
          timestampSeconds: 1234,
          senderName: 'Bob',
          textBytes: _ascii(text),
        ),
      );
      final cut = Uint8List.sublistView(expected, 0, expected.length - 3);
      expect(recovery.recover(cut), expected);
    });

    test('registers a channel data frame with and without a path', () {
      final recovery = ChannelEchoRecovery();
      final payload = Uint8List.fromList(List<int>.generate(100, (i) => i));
      final flood = buildSendChannelDataFrame(3, 0x0120, payload);
      final routed = buildSendChannelDataFrame(
        3,
        0x0120,
        payload,
        pathBytes: Uint8List.fromList([0x11, 0x22]),
      );
      expect(
        recovery.registerOutgoingFrame(flood, pskFor: pskFor, senderName: 'B'),
        isTrue,
      );
      expect(
        recovery.registerOutgoingFrame(
          routed,
          pskFor: pskFor,
          senderName: 'B',
        ),
        isTrue,
      );
      // Same plaintext either way: the route is not part of the payload.
      final expected = ChannelEchoRecovery.encryptedPayloadFor(
        psk,
        ChannelEchoRecovery.groupDataPlaintext(
          dataType: 0x0120,
          payload: payload,
        ),
      );
      final cut = Uint8List.sublistView(expected, 0, expected.length - 1);
      expect(recovery.recover(cut), expected);
    });

    test('ignores frames it cannot predict', () {
      final recovery = ChannelEchoRecovery();
      final text = buildSendChannelTextMsgFrame(3, 'hello');
      expect(
        recovery.registerOutgoingFrame(text, pskFor: pskFor, senderName: null),
        isFalse,
        reason: 'no node name, no "Name: " prefix',
      );
      expect(
        recovery.registerOutgoingFrame(
          buildSendChannelTextMsgFrame(7, 'hello'),
          pskFor: pskFor,
          senderName: 'Bob',
        ),
        isFalse,
        reason: 'unknown channel',
      );
      expect(
        recovery.registerOutgoingFrame(
          buildGetStatsFrame(statsTypeRadio),
          pskFor: pskFor,
          senderName: 'Bob',
        ),
        isFalse,
        reason: 'not a channel send',
      );
      expect(recovery.length, 0);
    });
  });

  group('recover', () {
    final psk = _psk();
    final plaintext = ChannelEchoRecovery.groupTextPlaintext(
      timestampSeconds: 99,
      senderName: 'Bob',
      textBytes: _ascii('a message long enough for a few blocks of text'),
    );
    final expected = ChannelEchoRecovery.encryptedPayloadFor(psk, plaintext);

    ChannelEchoRecovery registered({DateTime? now}) {
      final recovery = ChannelEchoRecovery();
      recovery.register(
        channelIndex: 0,
        psk: psk,
        plaintext: plaintext,
        now: now,
      );
      return recovery;
    }

    test('accepts any strict prefix that covers the MAC and one block', () {
      final recovery = registered();
      for (final length in [
        ChannelEchoRecovery.minMatchLength,
        expected.length - 16,
        expected.length - 3,
        expected.length - 1,
      ]) {
        expect(
          recovery.recover(Uint8List.sublistView(expected, 0, length)),
          expected,
          reason: 'prefix of $length bytes',
        );
      }
    });

    test('a whole copy is not a cut one', () {
      expect(registered().recover(expected), isNull);
      expect(
        registered().recover(Uint8List.fromList([...expected, 0])),
        isNull,
      );
    });

    test('needs the MAC and one whole block', () {
      expect(
        registered().recover(
          Uint8List.sublistView(
            expected,
            0,
            ChannelEchoRecovery.minMatchLength - 1,
          ),
        ),
        isNull,
      );
    });

    test('a different packet does not match', () {
      final other = Uint8List.fromList(expected.sublist(0, expected.length - 2))
        ..[5] ^= 0x01;
      expect(registered().recover(other), isNull);
    });

    test('several repeats of one packet all recover', () {
      final recovery = registered();
      final cut = Uint8List.sublistView(expected, 0, expected.length - 2);
      expect(recovery.recover(cut), expected);
      expect(recovery.recover(cut), expected);
    });

    test('an expectation expires', () {
      final t0 = DateTime(2026, 1, 1, 12);
      final recovery = registered(now: t0);
      final cut = Uint8List.sublistView(expected, 0, expected.length - 2);
      expect(
        recovery.recover(cut, now: t0.add(const Duration(minutes: 9))),
        expected,
      );
      expect(
        recovery.recover(cut, now: t0.add(const Duration(minutes: 11))),
        isNull,
      );
    });

    test('keeps at most maxEntries, dropping the oldest', () {
      final recovery = ChannelEchoRecovery(maxEntries: 2);
      final first = ChannelEchoRecovery.groupDataPlaintext(
        dataType: 1,
        payload: _ascii('first payload, long enough'),
      );
      recovery.register(channelIndex: 0, psk: psk, plaintext: first);
      recovery.register(channelIndex: 0, psk: psk, plaintext: plaintext);
      recovery.register(
        channelIndex: 0,
        psk: psk,
        plaintext: ChannelEchoRecovery.groupDataPlaintext(
          dataType: 2,
          payload: _ascii('third payload, long enough'),
        ),
      );
      expect(recovery.length, 2);
      final firstEncrypted = ChannelEchoRecovery.encryptedPayloadFor(
        psk,
        first,
      );
      expect(
        recovery.recover(
          Uint8List.sublistView(firstEncrypted, 0, firstEncrypted.length - 1),
        ),
        isNull,
      );
      expect(
        recovery.recover(Uint8List.sublistView(expected, 0, expected.length - 1)),
        expected,
      );
    });
  });
}
