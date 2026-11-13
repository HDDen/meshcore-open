import 'dart:convert';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import 'channel_raw_packet.dart';
import 'meshcore_expanded_identity.dart';
import 'utf8_length_limiter.dart';

/// A chat-node advert sent by the companion for an app-managed identity.
/// Mesh::createAdvert signs public key, timestamp and app data in that order.
Future<Uint8List> buildAdditionalIdentityFloodAdvert({
  required MeshCoreExpandedIdentity identity,
  required String name,
  required int timestampSeconds,
  required int pathHashWidth,
}) async {
  final nameBytes = utf8.encode(name);
  if (nameBytes.isEmpty || nameBytes.length > maxRadioNameBytes ||
      nameBytes.contains(0)) {
    throw const FormatException('Invalid MeshCore advert name');
  }
  if (pathHashWidth < 1 || pathHashWidth > 3) {
    throw RangeError.range(pathHashWidth, 1, 3, 'pathHashWidth');
  }
  final publicKey = identity.publicKey;
  final timestamp = ByteData(4)
    ..setUint32(0, timestampSeconds, Endian.little);
  const namePresent = 0x80;
  final appData = [advTypeChat | namePresent, ...nameBytes];
  final signed = [
    ...publicKey,
    ...timestamp.buffer.asUint8List(),
    ...appData,
  ];
  final signature = await identity.sign(signed);
  final packet = ChannelRawPacket.floodPacket(
    payloadType: payloadTypeADVERT,
    payload: Uint8List.fromList([
      ...publicKey,
      ...timestamp.buffer.asUint8List(),
      ...signature,
      ...appData,
    ]),
    pathHashWidth: pathHashWidth,
  );
  // Mesh::sendFlood uses priority 3 for adverts.
  return Uint8List.fromList([cmdSendRawPacket, 3, ...packet]);
}
