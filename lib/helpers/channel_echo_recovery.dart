import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

import '../connector/meshcore_protocol.dart';

/// Recognises a truncated RX-log copy of one of our own channel packets.
///
/// The companion hands every packet it hears to the app as
/// `PUSH_CODE_LOG_RX_DATA`, and that is the only place our own echo is
/// visible: the firmware marks a packet it sends as seen and drops the repeat
/// on dedupe before it could become a channel message. A companion frame is
/// capped at 176 bytes, and an ESP32 companion sets its BLE MTU to that very
/// number, so a notification carries three bytes fewer and the copy of a long
/// packet arrives with its last bytes cut off. Such a copy fails the MAC and
/// is dropped, and the repeat of our own long message goes unnoticed.
///
/// The payload of a channel packet is fully predictable, though: AES-128-ECB
/// with zero padding over a plaintext the app composes itself, under the
/// channel's PSK, with the first two bytes of an HMAC in front. So the
/// expected bytes are computed when the frame goes to the radio, and a cut
/// copy is recognised by its prefix. AES under one key is a permutation, so
/// two different plaintext blocks never share a ciphertext block: a prefix
/// that covers the MAC and one whole block can only belong to a packet with
/// our timestamp, type and text, that is to our own packet. Only frames the
/// normal decode has already rejected should reach [recover].
class ChannelEchoRecovery {
  ChannelEchoRecovery({
    this.ttl = const Duration(minutes: 10),
    this.maxEntries = 128,
  });

  static const int macSize = 2;
  static const int blockSize = 16;

  /// Firmware `MAX_TEXT_LEN`: the longest `Name: text` a group text carries.
  static const int maxGroupTextBytes = 160;

  /// The shortest prefix that proves a match: the MAC and one whole block.
  static const int minMatchLength = macSize + blockSize;

  /// How long an expectation stays valid. Repeats of one packet keep arriving
  /// for a while, and the self-echo window elsewhere is the same ten minutes.
  final Duration ttl;
  final int maxEntries;
  final List<_ExpectedEcho> _entries = <_ExpectedEcho>[];

  int get length => _entries.length;

  /// Registers a frame on its way to the radio when it is a channel send.
  /// Returns whether it was one. [pskFor] resolves a channel index to its
  /// PSK; [senderName] is the node's own name, which the firmware puts in
  /// front of a group text. Without either the packet cannot be predicted
  /// and nothing is registered.
  bool registerOutgoingFrame(
    Uint8List frame, {
    required Uint8List? Function(int channelIndex) pskFor,
    required String? senderName,
    DateTime? now,
  }) {
    if (frame.length < 2) return false;
    switch (frame[0]) {
      case cmdSendChannelTxtMsg:
        // [cmd][txt_type][channel_idx][timestamp x4][text...]
        if (frame.length < 7 || frame[1] != txtTypePlain) return false;
        if (senderName == null) return false;
        final channelIndex = frame[2];
        final psk = pskFor(channelIndex);
        if (psk == null) return false;
        final timestamp = ByteData.sublistView(
          frame,
          3,
          7,
        ).getUint32(0, Endian.little);
        register(
          channelIndex: channelIndex,
          psk: psk,
          plaintext: groupTextPlaintext(
            timestampSeconds: timestamp,
            senderName: senderName,
            textBytes: Uint8List.sublistView(frame, 7),
          ),
          now: now,
        );
        return true;
      case cmdSendChannelData:
        // [cmd][channel_idx][path_len][path?][data_type u16][payload...]
        if (frame.length < 5) return false;
        final channelIndex = frame[1];
        final pathLenRaw = frame[2];
        final pathBytes = pathLenRaw == 0xFF
            ? 0
            : (pathLenRaw & 0x3F) * (((pathLenRaw >> 6) & 0x03) + 1);
        final dataTypeOffset = 3 + pathBytes;
        if (frame.length < dataTypeOffset + 2) return false;
        final psk = pskFor(channelIndex);
        if (psk == null) return false;
        final dataType =
            frame[dataTypeOffset] | (frame[dataTypeOffset + 1] << 8);
        register(
          channelIndex: channelIndex,
          psk: psk,
          plaintext: groupDataPlaintext(
            dataType: dataType,
            payload: Uint8List.sublistView(frame, dataTypeOffset + 2),
          ),
          now: now,
        );
        return true;
      default:
        return false;
    }
  }

  void register({
    required int channelIndex,
    required Uint8List psk,
    required Uint8List plaintext,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    _prune(at);
    _entries.add(
      _ExpectedEcho(channelIndex, encryptedPayloadFor(psk, plaintext), at),
    );
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  /// [encrypted] is the MAC and whatever ciphertext the frame carried.
  /// Returns the full MAC and ciphertext of the packet it is a cut copy of,
  /// or null. A copy as long as the packet is not a cut one: it would have
  /// decrypted on its own, and if it did not it is somebody else's.
  Uint8List? recover(Uint8List encrypted, {DateTime? now}) {
    if (encrypted.length < minMatchLength) return null;
    _prune(now ?? DateTime.now());
    for (var i = _entries.length - 1; i >= 0; i--) {
      final expected = _entries[i].encrypted;
      if (encrypted.length >= expected.length) continue;
      if (!_isPrefix(encrypted, expected)) continue;
      return Uint8List.fromList(expected);
    }
    return null;
  }

  void clear() => _entries.clear();

  void _prune(DateTime now) {
    _entries.removeWhere((entry) => now.difference(entry.registeredAt) > ttl);
  }

  static bool _isPrefix(Uint8List prefix, Uint8List whole) {
    for (var i = 0; i < prefix.length; i++) {
      if (prefix[i] != whole[i]) return false;
    }
    return true;
  }

  /// `timestamp(4) + TXT_TYPE_PLAIN + "Name: text"`, as `sendGroupMessage`
  /// builds it. The firmware cuts the text so that `Name: text` stays within
  /// [maxGroupTextBytes]; the text is the frame's bytes as they were, without
  /// a terminator.
  static Uint8List groupTextPlaintext({
    required int timestampSeconds,
    required String senderName,
    required Uint8List textBytes,
  }) {
    final prefix = utf8.encode('$senderName: ');
    var textLength = textBytes.length;
    if (textLength + prefix.length > maxGroupTextBytes) {
      textLength = math.max(0, maxGroupTextBytes - prefix.length);
    }
    final timestamp = ByteData(4)
      ..setUint32(0, timestampSeconds & 0xFFFFFFFF, Endian.little);
    final out = BytesBuilder(copy: false)
      ..add(timestamp.buffer.asUint8List())
      ..addByte(0) // TXT_TYPE_PLAIN, attempt 0
      ..add(prefix)
      ..add(Uint8List.sublistView(textBytes, 0, textLength));
    return out.toBytes();
  }

  /// `data_type(2) + length(1) + data`, as `sendGroupData` builds it.
  static Uint8List groupDataPlaintext({
    required int dataType,
    required Uint8List payload,
  }) {
    final out = BytesBuilder(copy: false)
      ..addByte(dataType & 0xFF)
      ..addByte((dataType >> 8) & 0xFF)
      ..addByte(payload.length & 0xFF)
      ..add(payload);
    return out.toBytes();
  }

  /// MAC and ciphertext as `Utils::encryptThenMAC` produces them: AES-128-ECB
  /// over the plaintext padded with zeros to a whole block, keyed with the
  /// first 16 bytes of the PSK, then the first two bytes of HMAC-SHA256 over
  /// the ciphertext keyed with the PSK padded with zeros to 32 bytes. This is
  /// the exact inverse of the connector's `_decryptPayload`.
  static Uint8List encryptedPayloadFor(Uint8List psk, Uint8List plaintext) {
    final blocks = (plaintext.length + blockSize - 1) ~/ blockSize;
    final padded = Uint8List(blocks * blockSize)
      ..setRange(0, plaintext.length, plaintext);
    final key16 = Uint8List(16)
      ..setRange(0, math.min(16, psk.length), psk);
    final cipher = ECBBlockCipher(AESEngine())..init(true, KeyParameter(key16));
    final cipherText = Uint8List(padded.length);
    for (var i = 0; i < padded.length; i += blockSize) {
      cipher.processBlock(padded, i, cipherText, i);
    }
    final key32 = Uint8List(32)
      ..setRange(0, math.min(32, psk.length), psk);
    final mac = crypto.Hmac(crypto.sha256, key32).convert(cipherText).bytes;
    final out = Uint8List(macSize + cipherText.length)
      ..[0] = mac[0]
      ..[1] = mac[1]
      ..setRange(macSize, macSize + cipherText.length, cipherText);
    return out;
  }
}

class _ExpectedEcho {
  const _ExpectedEcho(this.channelIndex, this.encrypted, this.registeredAt);

  final int channelIndex;
  final Uint8List encrypted;
  final DateTime registeredAt;
}
