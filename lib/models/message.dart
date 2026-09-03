import 'dart:typed_data';
import '../connector/meshcore_protocol.dart';
import '../helpers/mcmp_app_codec.dart';
import '../helpers/mesh_compressor.dart';
import '../helpers/message_text_codec.dart';
import '../helpers/reaction_helper.dart';
import 'message_compression.dart';
import 'translation_support.dart';

enum MessageStatus { pending, sent, delivered, failed }

class Message {
  static const Object _unset = Object();

  final Uint8List senderKey;
  final String text;
  final String? rawText;
  final DateTime timestamp;
  // App-local conversation order. Incoming contact and room messages receive
  // it on arrival; outgoing room posts receive it on first transmission.
  final DateTime? receivedAt;
  final bool isOutgoing;
  final bool isCli;
  final MessageStatus status;
  final String? originalText;
  final String? translatedText;
  final String? translatedLanguageCode;
  final MessageTranslationStatus translationStatus;
  final String? translationModelId;
  final bool wasMcmpCompressed;
  final MessageCompressionType? compressionType;
  final int? compressionSavingsPercent;
  final int? compressionOriginalBytes;
  final int? compressionPayloadBytes;
  final McmpSignatureStatus mcmpSignatureStatus;

  // MCMP v3 metadata exactly as transmitted in the packet body. Kept verbatim
  // so reply anchors resolve precisely and signatures can be re-checked later.
  final int? mcmpTimestamp;
  final String? mcmpSenderName;
  final bool mcmpIsSigned;
  final Uint8List? mcmpSignature;
  final String? mcmpReplyAuthorName;
  final int? mcmpReplyTimestamp;

  /// Hex of the contact key that successfully verified the signature.
  final String? verifiedSenderKeyHex;

  /// True when the sender name belonged to more than one contact at the time
  /// the signature was checked.
  final bool mcmpNameCollision;

  // Resolved reply reference (from the MCMP reply anchor), mirroring the
  // ChannelMessage reply fields.
  final String? replyToMessageId;
  final String? replyToSenderName;
  final String? replyToText;
  final String? sharedHistorySourceName;
  final String? sourceLabel;

  // NEW: Retry logic fields
  final String messageId;
  final int retryCount;
  final int? estimatedTimeoutMs;
  final int? expectedAckHash;
  final DateTime? sentAt;
  // Internal TX anchor; UI keeps using timestamp as the visible compose time.
  final DateTime? sentByRadioAt;
  final List<int> sentByRadioWaitSeconds;
  final DateTime? deliveredAt;
  final int? tripTimeMs;
  final int? pathLength;
  final Uint8List pathBytes;
  final int deliveryProgressTotalSteps;
  final int deliveryProgressCompletedSteps;
  final Map<String, List<String?>> reactions;
  final Map<String, MessageStatus> reactionStatuses;
  final Uint8List fourByteRoomContactKey;

  /// True when this message arrived while its author was blocked.
  ///
  /// Room-server posts only: a one-to-one conversation is the contact itself,
  /// which is deleted rather than muted. Stored with the message and never
  /// cleared, exactly like `ChannelMessage.wasBlocked` — lifting a block must
  /// not resurrect a marker or a `del:` command from the muted period.
  final bool wasBlocked;

  Message({
    required this.senderKey,
    required this.text,
    this.rawText,
    required this.timestamp,
    this.receivedAt,
    required this.isOutgoing,
    this.isCli = false,
    this.status = MessageStatus.pending,
    String? messageId,
    this.originalText,
    this.translatedText,
    this.translatedLanguageCode,
    this.translationStatus = MessageTranslationStatus.none,
    this.translationModelId,
    this.wasMcmpCompressed = false,
    this.compressionType,
    this.compressionSavingsPercent,
    this.compressionOriginalBytes,
    this.compressionPayloadBytes,
    this.mcmpSignatureStatus = McmpSignatureStatus.none,
    this.mcmpTimestamp,
    this.mcmpSenderName,
    this.mcmpIsSigned = false,
    this.mcmpSignature,
    this.mcmpReplyAuthorName,
    this.mcmpReplyTimestamp,
    this.verifiedSenderKeyHex,
    this.mcmpNameCollision = false,
    this.replyToMessageId,
    this.replyToSenderName,
    this.replyToText,
    this.sharedHistorySourceName,
    this.sourceLabel,
    this.retryCount = 0,
    this.estimatedTimeoutMs,
    this.expectedAckHash,
    this.sentAt,
    this.sentByRadioAt,
    List<int>? sentByRadioWaitSeconds,
    this.deliveredAt,
    this.tripTimeMs,
    this.pathLength,
    Uint8List? pathBytes,
    this.deliveryProgressTotalSteps = 0,
    this.deliveryProgressCompletedSteps = 0,
    Uint8List? fourByteRoomContactKey,
    this.wasBlocked = false,
    Map<String, List<String?>>? reactions,
    Map<String, MessageStatus>? reactionStatuses,
  }) : messageId =
           messageId ??
           '${timestamp.millisecondsSinceEpoch}_${pubKeyToHex(senderKey)}_${text.hashCode}',
       sentByRadioWaitSeconds = sentByRadioWaitSeconds ?? const [],
       pathBytes = pathBytes ?? Uint8List(0),
       fourByteRoomContactKey = fourByteRoomContactKey ?? Uint8List(0),
       reactions = reactions ?? {},
       reactionStatuses = reactionStatuses ?? {};

  String get senderKeyHex => pubKeyToHex(senderKey);

  Message copyWith({
    MessageStatus? status,
    DateTime? receivedAt,
    int? retryCount,
    int? estimatedTimeoutMs,
    int? expectedAckHash,
    DateTime? sentAt,
    Object? sentByRadioAt = _unset,
    List<int>? sentByRadioWaitSeconds,
    DateTime? deliveredAt,
    int? tripTimeMs,
    int? pathLength,
    Uint8List? pathBytes,
    int? deliveryProgressTotalSteps,
    int? deliveryProgressCompletedSteps,
    bool? isCli,
    Object? originalText = _unset,
    Object? translatedText = _unset,
    Object? translatedLanguageCode = _unset,
    MessageTranslationStatus? translationStatus,
    Object? translationModelId = _unset,
    bool? wasMcmpCompressed,
    Object? compressionType = _unset,
    Object? compressionSavingsPercent = _unset,
    Object? compressionOriginalBytes = _unset,
    Object? compressionPayloadBytes = _unset,
    McmpSignatureStatus? mcmpSignatureStatus,
    Object? mcmpTimestamp = _unset,
    Object? mcmpSenderName = _unset,
    bool? mcmpIsSigned,
    Object? mcmpSignature = _unset,
    Object? mcmpReplyAuthorName = _unset,
    Object? mcmpReplyTimestamp = _unset,
    Object? verifiedSenderKeyHex = _unset,
    bool? mcmpNameCollision,
    Object? replyToMessageId = _unset,
    Object? replyToSenderName = _unset,
    Object? replyToText = _unset,
    Object? sharedHistorySourceName = _unset,
    Object? sourceLabel = _unset,
    bool? isOutgoing,
    Map<String, List<String?>>? reactions,
    Map<String, MessageStatus>? reactionStatuses,
    Uint8List? fourByteRoomContactKey,
    bool? wasBlocked,
  }) {
    return Message(
      senderKey: senderKey,
      text: text,
      rawText: rawText,
      timestamp: timestamp,
      receivedAt: receivedAt ?? this.receivedAt,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      isCli: isCli ?? this.isCli,
      status: status ?? this.status,
      messageId: messageId,
      originalText: originalText == _unset
          ? this.originalText
          : originalText as String?,
      translatedText: translatedText == _unset
          ? this.translatedText
          : translatedText as String?,
      translatedLanguageCode: translatedLanguageCode == _unset
          ? this.translatedLanguageCode
          : translatedLanguageCode as String?,
      translationStatus: translationStatus ?? this.translationStatus,
      translationModelId: translationModelId == _unset
          ? this.translationModelId
          : translationModelId as String?,
      wasMcmpCompressed: wasMcmpCompressed ?? this.wasMcmpCompressed,
      compressionType: compressionType == _unset
          ? this.compressionType
          : compressionType as MessageCompressionType?,
      compressionSavingsPercent: compressionSavingsPercent == _unset
          ? this.compressionSavingsPercent
          : compressionSavingsPercent as int?,
      compressionOriginalBytes: compressionOriginalBytes == _unset
          ? this.compressionOriginalBytes
          : compressionOriginalBytes as int?,
      compressionPayloadBytes: compressionPayloadBytes == _unset
          ? this.compressionPayloadBytes
          : compressionPayloadBytes as int?,
      mcmpSignatureStatus: mcmpSignatureStatus ?? this.mcmpSignatureStatus,
      mcmpTimestamp: mcmpTimestamp == _unset
          ? this.mcmpTimestamp
          : mcmpTimestamp as int?,
      mcmpSenderName: mcmpSenderName == _unset
          ? this.mcmpSenderName
          : mcmpSenderName as String?,
      mcmpIsSigned: mcmpIsSigned ?? this.mcmpIsSigned,
      mcmpSignature: mcmpSignature == _unset
          ? this.mcmpSignature
          : mcmpSignature as Uint8List?,
      mcmpReplyAuthorName: mcmpReplyAuthorName == _unset
          ? this.mcmpReplyAuthorName
          : mcmpReplyAuthorName as String?,
      mcmpReplyTimestamp: mcmpReplyTimestamp == _unset
          ? this.mcmpReplyTimestamp
          : mcmpReplyTimestamp as int?,
      verifiedSenderKeyHex: verifiedSenderKeyHex == _unset
          ? this.verifiedSenderKeyHex
          : verifiedSenderKeyHex as String?,
      mcmpNameCollision: mcmpNameCollision ?? this.mcmpNameCollision,
      replyToMessageId: replyToMessageId == _unset
          ? this.replyToMessageId
          : replyToMessageId as String?,
      replyToSenderName: replyToSenderName == _unset
          ? this.replyToSenderName
          : replyToSenderName as String?,
      replyToText: replyToText == _unset
          ? this.replyToText
          : replyToText as String?,
      sharedHistorySourceName: sharedHistorySourceName == _unset
          ? this.sharedHistorySourceName
          : sharedHistorySourceName as String?,
      sourceLabel: sourceLabel == _unset
          ? this.sourceLabel
          : sourceLabel as String?,
      retryCount: retryCount ?? this.retryCount,
      estimatedTimeoutMs: estimatedTimeoutMs ?? this.estimatedTimeoutMs,
      expectedAckHash: expectedAckHash ?? this.expectedAckHash,
      sentAt: sentAt ?? this.sentAt,
      sentByRadioAt: sentByRadioAt == _unset
          ? this.sentByRadioAt
          : sentByRadioAt as DateTime?,
      sentByRadioWaitSeconds:
          sentByRadioWaitSeconds ?? this.sentByRadioWaitSeconds,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      tripTimeMs: tripTimeMs ?? this.tripTimeMs,
      pathLength: pathLength ?? this.pathLength,
      pathBytes: pathBytes ?? this.pathBytes,
      deliveryProgressTotalSteps:
          deliveryProgressTotalSteps ?? this.deliveryProgressTotalSteps,
      deliveryProgressCompletedSteps:
          deliveryProgressCompletedSteps ??
          this.deliveryProgressCompletedSteps,
      reactions: reactions ?? this.reactions,
      reactionStatuses: reactionStatuses ?? this.reactionStatuses,
      fourByteRoomContactKey:
          fourByteRoomContactKey ?? this.fourByteRoomContactKey,
      wasBlocked: wasBlocked ?? this.wasBlocked,
    );
  }

  static Message? fromFrame(Uint8List frame, Uint8List selfPubKey) {
    if (frame.length < msgTextOffset + 1) return null;
    final reader = BufferReader(frame);
    try {
      final code = reader.readByte();
      if (code != respCodeContactMsgRecv && code != respCodeContactMsgRecvV3) {
        return null;
      }

      final senderKey = reader.readBytes(pubKeySize);
      final timestampRaw = reader.readInt32LE();
      final flags = reader.readByte();
      if ((flags >> 2) != txtTypePlain) {
        return null;
      }
      final rawText = reader.readCString();
      final decodedDetails = MessageTextCodec.tryDecodeKnownCompressionDetails(
        rawText,
      );
      final text = decodedDetails?.text ?? rawText;
      final compression = MessageCompressionMetadata.fromEncodedText(
        encodedText: rawText,
        decodedText: text,
      );

      return Message(
        senderKey: senderKey,
        text: text,
        rawText: rawText,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestampRaw * 1000),
        isOutgoing: false,
        isCli: false,
        status: MessageStatus.delivered,
        wasMcmpCompressed:
            MeshCompressor.instance.hasPrefix(rawText) ||
            McmpAppCodec.isTextPayload(rawText) ||
            decodedDetails?.mcotxtMessage != null,
        compressionType: compression?.type,
        compressionSavingsPercent: compression?.savingsPercent,
        compressionOriginalBytes: compression?.originalBytes,
        compressionPayloadBytes: compression?.payloadBytes,
        mcmpSignatureStatus:
            decodedDetails?.mcmpMessage?.signatureStatus ??
            McmpSignatureStatus.none,
        mcmpTimestamp:
            decodedDetails?.mcmpMessage?.timestamp ??
            decodedDetails?.mcotxtMessage?.metadataTimestamp,
        mcmpSenderName:
            decodedDetails?.mcmpMessage?.senderName ??
            decodedDetails?.mcotxtMessage?.senderName,
        mcmpIsSigned: decodedDetails?.mcmpMessage?.isSigned ?? false,
        mcmpSignature: decodedDetails?.mcmpMessage?.signature,
        mcmpReplyAuthorName:
            decodedDetails?.mcmpMessage?.replyAuthorName ??
            decodedDetails?.mcotxtMessage?.replyAuthorName,
        mcmpReplyTimestamp:
            decodedDetails?.mcmpMessage?.replyTimestamp ??
            decodedDetails?.mcotxtMessage?.replyTimestamp,
        pathBytes: Uint8List(0),
      );
    } catch (e) {
      return null;
    }
  }

  static Message outgoing(
    Uint8List recipientKey,
    String text, {
    String? rawText,
    String? messageId,
    DateTime? timestamp,
    String? originalText,
    String? translatedLanguageCode,
    String? translationModelId,
    bool wasMcmpCompressed = false,
    MessageCompressionType? compressionType,
    int? compressionSavingsPercent,
    int? compressionOriginalBytes,
    int? compressionPayloadBytes,
    McmpSignatureStatus mcmpSignatureStatus = McmpSignatureStatus.none,
    int? mcmpTimestamp,
    String? mcmpSenderName,
    bool mcmpIsSigned = false,
    Uint8List? mcmpSignature,
    String? mcmpReplyAuthorName,
    int? mcmpReplyTimestamp,
    int? pathLength,
    Uint8List? pathBytes,
  }) {
    return Message(
      senderKey: recipientKey,
      text: text,
      rawText: rawText,
      originalText: originalText,
      translatedLanguageCode: translatedLanguageCode,
      translationModelId: translationModelId,
      wasMcmpCompressed: wasMcmpCompressed,
      compressionType: compressionType,
      compressionSavingsPercent: compressionSavingsPercent,
      compressionOriginalBytes: compressionOriginalBytes,
      compressionPayloadBytes: compressionPayloadBytes,
      mcmpSignatureStatus: mcmpSignatureStatus,
      mcmpTimestamp: mcmpTimestamp,
      mcmpSenderName: mcmpSenderName,
      mcmpIsSigned: mcmpIsSigned,
      mcmpSignature: mcmpSignature,
      mcmpReplyAuthorName: mcmpReplyAuthorName,
      mcmpReplyTimestamp: mcmpReplyTimestamp,
      timestamp: timestamp ?? DateTime.now(),
      isOutgoing: true,
      isCli: false,
      status: MessageStatus.pending,
      messageId: messageId,
      pathLength: pathLength,
      pathBytes: pathBytes,
    );
  }

  static ReactionInfo? parseReaction(String text) {
    return ReactionHelper.parseReaction(text);
  }
}
