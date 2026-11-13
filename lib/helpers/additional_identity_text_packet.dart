import 'dart:convert';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import '../models/path_selection.dart';
import 'channel_echo_recovery.dart';
import 'channel_raw_packet.dart';
import 'direct_echo_crypto.dart';
import 'meshcore_expanded_identity.dart';

/// TXT_MSG as constructed by BaseChatMesh::composeMsgPacket. The same
/// companion raw command carries Flood and explicitly routed packets.
abstract final class AdditionalIdentityTextPacket {
  static int maxTextBytes(PathSelection route, {required bool scoped}) {
    final overhead = 8 + (route.useFlood ? (scoped ? 4 : 0) : route.pathBytes.length);
    final available = ((maxFrameSize - overhead) ~/ 16) * 16 - 5;
    return available.clamp(0, maxTextPayloadBytes);
  }

  static ({Uint8List frame, int ackHash}) build({
    required MeshCoreExpandedIdentity identity,
    required Uint8List peer,
    required int timestamp,
    required String text,
    required PathSelection route,
    required int pathHashWidth,
    String region = '',
  }) {
    final textBytes = utf8.encode(text);
    if (textBytes.isEmpty ||
        textBytes.contains(0) ||
        textBytes.length > maxTextBytes(route, scoped: region.isNotEmpty)) {
      throw const FormatException('Invalid additional identity message size');
    }
    final plaintext = Uint8List(5 + textBytes.length)
      ..setRange(5, 5 + textBytes.length, textBytes);
    ByteData.sublistView(plaintext).setUint32(0, timestamp, Endian.little);
    final sender = identity.publicKey;
    final payload = _encryptedPayload(
      identity,
      peer,
      plaintext,
      [peer.first, sender.first],
    );
    final ack = DirectEchoCrypto.ackHash(
      plaintext,
      textBytes.length,
      sender,
      randomByte: 0,
    );
    return (
      frame: _frame(payloadTypeTXTMSG, payload, route, pathHashWidth, region),
      ackHash: ByteData.sublistView(ack).getUint32(0, Endian.little),
    );
  }

  static Uint8List roomLogin({
    required MeshCoreExpandedIdentity identity,
    required Uint8List room,
    required int timestamp,
    required int syncSince,
    required String password,
    required PathSelection route,
    required int pathHashWidth,
    required String region,
  }) {
    final passwordBytes = utf8.encode(password);
    if (passwordBytes.contains(0)) {
      throw const FormatException('Invalid room password');
    }
    final length = passwordBytes.length.clamp(0, 15);
    final plaintext = Uint8List(8 + length)
      ..setRange(8, 8 + length, passwordBytes);
    ByteData.sublistView(plaintext)
      ..setUint32(0, timestamp, Endian.little)
      ..setUint32(4, syncSince, Endian.little);
    final Uint8List payload;
    try {
      payload = _encryptedPayload(
        identity,
        room,
        plaintext,
        [room.first, ...identity.publicKey],
      );
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
    return _frame(payloadTypeANONREQ, payload, route, pathHashWidth, region);
  }

  static Uint8List _encryptedPayload(
    MeshCoreExpandedIdentity identity,
    Uint8List peer,
    Uint8List plaintext,
    List<int> address,
  ) {
    final secret = identity.sharedSecret(peer);
    try {
      return Uint8List.fromList([
        ...address,
        ...ChannelEchoRecovery.encryptedPayloadFor(secret, plaintext),
      ]);
    } finally {
      secret.fillRange(0, secret.length, 0);
    }
  }

  static Uint8List _frame(
    int type,
    Uint8List payload,
    PathSelection route,
    int pathHashWidth,
    String region,
  ) {
    if (pathHashWidth < 1 ||
        pathHashWidth > 3 ||
        (!route.useFlood &&
            (route.hopCount < 0 ||
                route.hopCount > 63 ||
                route.pathBytes.length != route.hopCount * pathHashWidth))) {
      throw const FormatException('Invalid MeshCore path');
    }

    final packet = route.useFlood
        ? ChannelRawPacket.floodPacket(
            payloadType: type,
            payload: payload,
            pathHashWidth: pathHashWidth,
            transportCode: region.isEmpty
                ? null
                : ChannelRawPacket.regionTransportCode(region, type, payload),
          )
        : Uint8List.fromList([
            (type << 2) | 0x02,
            ((pathHashWidth - 1) << 6) | route.hopCount,
            ...route.pathBytes,
            ...payload,
          ]);
    if (packet.length + 2 > maxFrameSize) {
      throw const FormatException('Raw frame exceeds the companion limit');
    }
    return Uint8List.fromList([
      cmdSendRawPacket,
      route.useFlood ? ChannelRawPacket.priority : 0,
      ...packet,
    ]);
  }

  static int? pathAckHash(Uint8List plaintext) {
    final offset = _pathExtraOffset(plaintext, payloadTypeACK);
    if (offset == null || plaintext.length < offset + 4) return null;
    return ByteData.sublistView(plaintext).getUint32(offset, Endian.little);
  }

  static ({int timestamp, bool canPost})? roomLoginResponse(
    Uint8List plaintext, {
    required bool inPath,
  }) {
    final offset = inPath
        ? _pathExtraOffset(plaintext, payloadTypeRESPONSE)
        : 0;
    if (offset == null ||
        plaintext.length < offset + 13 ||
        plaintext[offset + 4] != 0 ||
        plaintext[offset + 5] != 0 ||
        plaintext[offset + 6] > 2) {
      return null;
    }
    final timestamp = ByteData.sublistView(plaintext).getUint32(offset, Endian.little);
    if (timestamp == 0) return null;
    final role = plaintext[offset + 7] & 3;
    return (timestamp: timestamp, canPost: role >= 2);
  }

  static int? _pathExtraOffset(Uint8List plaintext, int type) {
    if (plaintext.isEmpty || (plaintext.first >> 6) == 3) return null;
    final path = plaintext.first;
    final offset = 1 + (path & 63) * ((path >> 6) + 1);
    if (plaintext.length <= offset || (plaintext[offset] & 0x0f) != type) {
      return null;
    }
    return offset + 1;
  }
}
