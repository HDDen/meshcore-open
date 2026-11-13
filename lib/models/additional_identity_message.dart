import 'dart:typed_data';

import 'package:convert/convert.dart';

import '../connector/meshcore_protocol.dart';
import '../helpers/mcmp_app_codec.dart';
import '../helpers/message_text_codec.dart';
import 'message.dart';
import 'message_compression.dart';

/// A message in a thread identified by the app-owned key and its peer.
/// Both keys are full public keys, independent of the connected radio.
typedef AdditionalIdentityMessage = ({
  String recipientKey,
  String senderKey,
  String senderName,
  int peerType,
  String? roomAuthorHex,
  int timestampSeconds,
  int receivedAtMs,
  String wireText,
  String text,
  bool isUnread,
  bool isOutgoing,
  MessageStatus status,
  int rowId,
  bool? sentByFlood,
  String? region,
  Uint8List? path,
  int? dispatchedAtMs,
  int? tripTimeMs,
  int? airtimeMs,
  bool usedCyr2Lat,
});

extension AdditionalIdentityMessageProjection on AdditionalIdentityMessage {
  Message toChatMessage({String? identityName, bool sharedHistory = false}) {
    final decoded = MessageTextCodec.tryDecodeKnownCompressionDetails(
      wireText,
      inheritedTimestamp: timestampSeconds,
    );
    final compression = usedCyr2Lat
        ? MessageCompressionMetadata.fromText(
            type: MessageCompressionType.cyr2lat,
            originalText: text,
            compressedText: wireText,
          )
        : MessageCompressionMetadata.fromEncodedText(
            encodedText: wireText,
            decodedText: text,
          );
    final dispatched = dispatchedAtMs;
    final roundTrip = tripTimeMs;
    final mcmp = decoded?.mcmpMessage;
    return Message(
      senderKey: hexToPubKey(isOutgoing ? recipientKey : senderKey),
      messageId: 'identity:$recipientKey:$rowId',
      text: text,
      rawText: wireText,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampSeconds * 1000),
      receivedAt: DateTime.fromMillisecondsSinceEpoch(receivedAtMs),
      isOutgoing: isOutgoing,
      status: status,
      sendAttemptLimit: isOutgoing && dispatched != null ? 1 : null,
      sentByRadioAt: dispatched == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(dispatched),
      sentByRadioWaitSeconds: dispatched == null
          ? null
          : [((dispatched - receivedAtMs) ~/ 1000).clamp(0, 0x7fffffff)],
      deliveredAt: dispatched == null || roundTrip == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(dispatched + roundTrip),
      tripTimeMs: roundTrip,
      airtimeMs: airtimeMs,
      sentByFlood: sentByFlood == true,
      packetRegion: region,
      packetRegionInfoAvailable: sentByFlood == true,
      pathBytes: path,
      compressionType: compression?.type,
      compressionSavingsPercent: compression?.savingsPercent,
      compressionOriginalBytes: compression?.originalBytes,
      compressionPayloadBytes: compression?.payloadBytes,
      sharedHistorySourceName: sharedHistory ? identityName : null,
      containerTimestamp:
          mcmp?.timestamp ?? decoded?.mcotxtMessage?.metadataTimestamp,
      containerSenderName: isOutgoing ? identityName : null,
      mcmpIsSigned: mcmp?.isSigned ?? false,
      mcmpSignature: mcmp?.signature,
      containerReplyAuthorName:
          mcmp?.replyAuthorName ?? decoded?.mcotxtMessage?.replyAuthorName,
      containerReplyTimestamp:
          mcmp?.replyTimestamp ?? decoded?.mcotxtMessage?.replyTimestamp,
      mcmpSignatureStatus: !isOutgoing || mcmp == null
          ? McmpSignatureStatus.none
          : mcmp.isSigned
          ? McmpSignatureStatus.unverifiable
          : McmpSignatureStatus.unsigned,
      fourByteRoomContactKey: roomAuthorHex == null
          ? null
          : Uint8List.fromList(hex.decode(roomAuthorHex!)),
    );
  }
}

typedef AdditionalIdentityThread = ({
  String senderKey,
  String senderName,
  int peerType,
  int unread,
});
