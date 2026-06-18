import 'dart:typed_data';
import '../connector/meshcore_protocol.dart';
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
  final DateTime timestamp;
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
  final String? sharedHistorySourceName;

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
  final Map<String, int> reactions;
  final Map<String, MessageStatus> reactionStatuses;
  final Uint8List fourByteRoomContactKey;

  Message({
    required this.senderKey,
    required this.text,
    required this.timestamp,
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
    this.sharedHistorySourceName,
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
    Uint8List? fourByteRoomContactKey,
    Map<String, int>? reactions,
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
    Object? sharedHistorySourceName = _unset,
    Map<String, int>? reactions,
    Map<String, MessageStatus>? reactionStatuses,
    Uint8List? fourByteRoomContactKey,
  }) {
    return Message(
      senderKey: senderKey,
      text: text,
      timestamp: timestamp,
      isOutgoing: isOutgoing,
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
      sharedHistorySourceName: sharedHistorySourceName == _unset
          ? this.sharedHistorySourceName
          : sharedHistorySourceName as String?,
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
      reactions: reactions ?? this.reactions,
      reactionStatuses: reactionStatuses ?? this.reactionStatuses,
      fourByteRoomContactKey:
          fourByteRoomContactKey ?? this.fourByteRoomContactKey,
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
      final text =
          MessageTextCodec.tryDecodeKnownCompression(rawText) ?? rawText;
      final compression = MessageCompressionMetadata.fromEncodedText(
        encodedText: rawText,
        decodedText: text,
      );

      return Message(
        senderKey: senderKey,
        text: text,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestampRaw * 1000),
        isOutgoing: false,
        isCli: false,
        status: MessageStatus.delivered,
        wasMcmpCompressed: MeshCompressor.instance.hasPrefix(rawText),
        compressionType: compression?.type,
        compressionSavingsPercent: compression?.savingsPercent,
        compressionOriginalBytes: compression?.originalBytes,
        compressionPayloadBytes: compression?.payloadBytes,
        pathBytes: Uint8List(0),
      );
    } catch (e) {
      return null;
    }
  }

  static Message outgoing(
    Uint8List recipientKey,
    String text, {
    String? originalText,
    String? translatedLanguageCode,
    String? translationModelId,
    bool wasMcmpCompressed = false,
    MessageCompressionType? compressionType,
    int? compressionSavingsPercent,
    int? compressionOriginalBytes,
    int? compressionPayloadBytes,
    int? pathLength,
    Uint8List? pathBytes,
  }) {
    return Message(
      senderKey: recipientKey,
      text: text,
      originalText: originalText,
      translatedLanguageCode: translatedLanguageCode,
      translationModelId: translationModelId,
      wasMcmpCompressed: wasMcmpCompressed,
      compressionType: compressionType,
      compressionSavingsPercent: compressionSavingsPercent,
      compressionOriginalBytes: compressionOriginalBytes,
      compressionPayloadBytes: compressionPayloadBytes,
      timestamp: DateTime.now(),
      isOutgoing: true,
      isCli: false,
      status: MessageStatus.pending,
      pathLength: pathLength,
      pathBytes: pathBytes,
    );
  }

  static ReactionInfo? parseReaction(String text) {
    return ReactionHelper.parseReaction(text);
  }
}
