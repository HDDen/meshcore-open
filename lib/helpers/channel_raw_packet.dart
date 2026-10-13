import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../connector/meshcore_protocol.dart';
import 'channel_echo_recovery.dart';

/// The GRP_TXT packet the app builds and sends through `CMD_SEND_RAW_PACKET`
/// when a channel sends under a name of its own (see `channel_sender_name.dart`):
/// `CMD_SEND_CHANNEL_TXT_MSG` takes only the text, the companion putting
/// `_prefs.node_name` in front of it (`BaseChatMesh::sendGroupMessage`), so
/// the name of a plain packet can be changed only by building the packet.
///
/// The packet repeats what the firmware builds for its own: the header of a
/// flood, a transport flood when the send is scoped; the two transport codes,
/// the second always zero; the path byte with the node's hash width and no
/// hops (`Packet::setPathHashSizeAndCount`); then the payload, the channel
/// hash byte in front of the MAC and the ciphertext of
/// `timestamp + type + "Name: text"` under the channel PSK
/// (`Mesh::createGroupDatagram`). Three things the firmware does for its own
/// packets fall to the app here. The transport code of the region, which
/// `sendPacket` neither computes nor adds. The echo registry and the
/// heard-packet map, fed from the frame by `_sendFrameDirect` for the node's
/// command. And the dedupe mark, which a raw packet never gets:
/// `Mesh::sendFlood` marks, the `CMD_SEND_RAW_PACKET` handler calls
/// `sendPacket` straight, so the first relayed copy comes back from the node
/// as an incoming message under that name and is folded into our own message
/// as any copy of it is.
class ChannelRawPacket {
  ChannelRawPacket._();

  static const int routeTransportFlood = 0x00;
  static const int routeFlood = 0x01;

  /// What `Mesh::sendFlood` gives a group text packet.
  static const int priority = 1;

  /// The bytes of `"Name: text"` the frame can carry: the companion frame
  /// (176) less the command and the priority, the header, the two transport
  /// codes, the path byte, the channel hash and the MAC leaves 165 bytes of
  /// ciphertext, ten whole blocks, 160 bytes of plaintext, five of which are
  /// the timestamp and the type. The node's own command carries 160 bytes
  /// of `"Name: text"` (`ChannelEchoRecovery.maxGroupTextBytes`), so a name
  /// of the channel's own costs five bytes of text on top of its length.
  static const int maxGroupTextBytes = 155;

  /// The on-air channel hash: the first byte of SHA-256 over the PSK.
  static int channelHash(Uint8List psk) =>
      crypto.sha256.convert(psk).bytes[0];

  /// `channel_hash + MAC + ciphertext`, the payload of a GRP_TXT packet
  /// carrying [plaintext] (`ChannelEchoRecovery.groupTextPlaintext`).
  static Uint8List groupTextPayload({
    required Uint8List psk,
    required Uint8List plaintext,
  }) {
    final encrypted = ChannelEchoRecovery.encryptedPayloadFor(psk, plaintext);
    return Uint8List(1 + encrypted.length)
      ..[0] = channelHash(psk)
      ..setRange(1, 1 + encrypted.length, encrypted);
  }

  /// The transport code of a packet of [payloadType] carrying [payload]
  /// under a public region, as `TransportKey::calcTransportCode` computes it:
  /// HMAC-SHA256 keyed with the region key, the first 16 bytes of SHA-256
  /// over `#name`, over the payload type and the payload, its first two
  /// bytes little-endian, 0 and 0xFFFF reserved.
  static int regionTransportCode(
    String region,
    int payloadType,
    Uint8List payload,
  ) {
    final name = region.startsWith('#') ? region : '#$region';
    final regionKey = crypto.sha256
        .convert(utf8.encode(name))
        .bytes
        .sublist(0, 16);
    final input = Uint8List(1 + payload.length)
      ..[0] = payloadType
      ..setRange(1, 1 + payload.length, payload);
    final digest = crypto.Hmac(crypto.sha256, regionKey).convert(input).bytes;
    final code = digest[0] | (digest[1] << 8);
    if (code == 0) return 1;
    if (code == 0xFFFF) return 0xFFFE;
    return code;
  }

  /// A flood packet of [payloadType] carrying [payload], scoped with
  /// [transportCode] when one is given.
  static Uint8List floodPacket({
    required int payloadType,
    required Uint8List payload,
    required int pathHashWidth,
    int? transportCode,
  }) {
    final width = pathHashWidth.clamp(1, 4);
    return Uint8List.fromList([
      (payloadType << 2) |
          (transportCode != null ? routeTransportFlood : routeFlood),
      if (transportCode != null) ...[
        transportCode & 0xFF,
        (transportCode >> 8) & 0xFF,
        0,
        0,
      ],
      (width - 1) << 6,
      ...payload,
    ]);
  }

  /// `[CMD_SEND_RAW_PACKET][priority][packet]`.
  static Uint8List sendFrame(Uint8List packet) =>
      Uint8List.fromList([cmdSendRawPacket, priority, ...packet]);

  /// The whole frame for [text] under [senderName]: the payload, the code of
  /// [region] (none for an empty one), the packet and the command.
  static Uint8List groupTextFrame({
    required Uint8List psk,
    required int timestampSeconds,
    required String senderName,
    required Uint8List textBytes,
    required int pathHashWidth,
    String region = '',
  }) {
    final payload = groupTextPayload(
      psk: psk,
      plaintext: ChannelEchoRecovery.groupTextPlaintext(
        timestampSeconds: timestampSeconds,
        senderName: senderName,
        textBytes: textBytes,
      ),
    );
    final scope = region.trim();
    return sendFrame(
      floodPacket(
        payloadType: payloadTypeGRPTXT,
        payload: payload,
        pathHashWidth: pathHashWidth,
        transportCode: scope.isEmpty
            ? null
            : regionTransportCode(scope, payloadTypeGRPTXT, payload),
      ),
    );
  }

}
