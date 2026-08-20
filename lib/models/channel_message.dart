import 'dart:convert';
import 'dart:typed_data';
import '../connector/meshcore_protocol.dart';
import '../helpers/mcmp_app_codec.dart';
import '../helpers/mesh_compressor.dart';
import '../helpers/reaction_helper.dart';
import '../helpers/message_text_codec.dart';
import 'message_compression.dart';
import 'translation_support.dart';
import '../utils/app_logger.dart';

enum ChannelMessageStatus { pending, sent, failed }

class Repeat {
  final Uint8List? repeaterKey;
  final String repeaterName;
  final int tripTimeMs;
  final List<Uint8List>? path;

  Repeat({
    this.repeaterKey,
    required this.repeaterName,
    required this.tripTimeMs,
    this.path,
  });

  String? get repeaterKeyHex =>
      repeaterKey != null ? pubKeyToHex(repeaterKey!) : null;
}

class ChannelMessage {
  static const Object _unset = Object();

  final Uint8List? senderKey;
  final String senderName;
  final String text;
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
  final bool wasBinaryTransport;

  /// True when this message arrived while its sender was blocked.
  ///
  /// Stored with the message and never cleared: lifting a block must not
  /// resurrect a marker or a `del:` command from the muted period, and
  /// revealing the text by hand must not either.
  final bool wasBlocked;
  final int? binaryPacketBytes;
  final DateTime timestamp;
  final DateTime receivedAt;
  // Internal TX anchor; UI keeps using timestamp as the visible compose time.
  final DateTime? sentByRadioAt;
  final List<int> sentByRadioWaitSeconds;
  final bool isOutgoing;
  final ChannelMessageStatus status;
  final List<Repeat> repeats;
  final int repeatCount;
  final int? pathLength;
  final int? pathHashWidth;
  final Uint8List pathBytes;
  final List<Uint8List> pathVariants;

  /// What our own radio made of the reception this message arrived on: SNR in
  /// dB, RSSI in dBm. They describe the link from the last hop of [pathBytes]
  /// — the node we actually heard — to us, and belong together: a copy that
  /// travelled another route carries another reading.
  ///
  /// Null when the frame that delivered the message reported none. RSSI rides
  /// only in the raw RX log; the channel-message responses carry SNR alone.
  final double? snr;
  final int? rssi;
  final int? channelIndex;
  final String? packetRegion;
  final bool packetRegionInfoAvailable;
  final bool packetRegionNotMatched;
  final int? noRetransmissionWarningSeconds;
  final String messageId;
  final String? packetHash;
  final String? replyToMessageId;
  final String? replyToSenderName;
  final String? replyToText;
  final Map<String, int> reactions;
  final String? sharedHistorySourceName;

  ChannelMessage({
    this.senderKey,
    required this.senderName,
    required this.text,
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
    this.wasBinaryTransport = false,
    this.wasBlocked = false,
    this.binaryPacketBytes,
    required this.timestamp,
    DateTime? receivedAt,
    this.sentByRadioAt,
    List<int>? sentByRadioWaitSeconds,
    required this.isOutgoing,
    this.status = ChannelMessageStatus.pending,
    this.repeats = const [],
    this.repeatCount = 0,
    this.pathLength,
    this.pathHashWidth,
    Uint8List? pathBytes,
    List<Uint8List>? pathVariants,
    this.snr,
    this.rssi,
    this.channelIndex,
    this.packetRegion,
    this.packetRegionInfoAvailable = false,
    this.packetRegionNotMatched = false,
    this.noRetransmissionWarningSeconds,
    String? messageId,
    this.packetHash,
    this.replyToMessageId,
    this.replyToSenderName,
    this.replyToText,
    Map<String, int>? reactions,
    this.sharedHistorySourceName,
  }) : receivedAt = receivedAt ?? DateTime.now(),
       messageId =
           messageId ??
           '${timestamp.millisecondsSinceEpoch}_${senderName.hashCode}_${text.hashCode}',
       sentByRadioWaitSeconds = sentByRadioWaitSeconds ?? const [],
       reactions = reactions ?? {},
       pathBytes = pathBytes ?? Uint8List(0),
       pathVariants = _mergePathVariants(
         pathBytes ?? Uint8List(0),
         pathVariants,
       );

  String? get senderKeyHex =>
      senderKey != null ? pubKeyToHex(senderKey!) : null;

  ChannelMessage copyWith({
    ChannelMessageStatus? status,
    DateTime? timestamp,
    List<Repeat>? repeats,
    int? repeatCount,
    int? pathLength,
    int? pathHashWidth,
    Uint8List? pathBytes,
    List<Uint8List>? pathVariants,
    Object? snr = _unset,
    Object? rssi = _unset,
    int? channelIndex,
    Object? packetRegion = _unset,
    bool? packetRegionInfoAvailable,
    bool? packetRegionNotMatched,
    Object? noRetransmissionWarningSeconds = _unset,
    String? packetHash,
    String? replyToMessageId,
    String? replyToSenderName,
    String? replyToText,
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
    bool? wasBinaryTransport,
    bool? wasBlocked,
    Object? binaryPacketBytes = _unset,
    Object? sharedHistorySourceName = _unset,
    DateTime? receivedAt,
    Object? sentByRadioAt = _unset,
    List<int>? sentByRadioWaitSeconds,
    Map<String, int>? reactions,
  }) {
    return ChannelMessage(
      senderKey: senderKey,
      senderName: senderName,
      text: text,
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
      wasBinaryTransport: wasBinaryTransport ?? this.wasBinaryTransport,
      wasBlocked: wasBlocked ?? this.wasBlocked,
      binaryPacketBytes: binaryPacketBytes == _unset
          ? this.binaryPacketBytes
          : binaryPacketBytes as int?,
      sharedHistorySourceName: sharedHistorySourceName == _unset
          ? this.sharedHistorySourceName
          : sharedHistorySourceName as String?,
      timestamp: timestamp ?? this.timestamp,
      receivedAt: receivedAt ?? this.receivedAt,
      sentByRadioAt: sentByRadioAt == _unset
          ? this.sentByRadioAt
          : sentByRadioAt as DateTime?,
      sentByRadioWaitSeconds:
          sentByRadioWaitSeconds ?? this.sentByRadioWaitSeconds,
      isOutgoing: isOutgoing,
      status: status ?? this.status,
      repeats: repeats ?? this.repeats,
      repeatCount: repeatCount ?? this.repeatCount,
      pathLength: pathLength ?? this.pathLength,
      pathHashWidth: pathHashWidth ?? this.pathHashWidth,
      pathBytes: pathBytes ?? this.pathBytes,
      pathVariants: pathVariants ?? this.pathVariants,
      snr: snr == _unset ? this.snr : snr as double?,
      rssi: rssi == _unset ? this.rssi : rssi as int?,
      channelIndex: channelIndex ?? this.channelIndex,
      packetRegion: packetRegion == _unset
          ? this.packetRegion
          : packetRegion as String?,
      packetRegionInfoAvailable:
          packetRegionInfoAvailable ?? this.packetRegionInfoAvailable,
      packetRegionNotMatched:
          packetRegionNotMatched ?? this.packetRegionNotMatched,
      noRetransmissionWarningSeconds: noRetransmissionWarningSeconds == _unset
          ? this.noRetransmissionWarningSeconds
          : noRetransmissionWarningSeconds as int?,
      messageId: messageId,
      packetHash: packetHash ?? this.packetHash,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      replyToText: replyToText ?? this.replyToText,
      reactions: reactions ?? this.reactions,
    );
  }

  static ChannelMessage? fromFrame(
    Uint8List frame, {
    bool includeSenderNameInCompressionRatio = false,
  }) {
    // CHANNEL_MSG_RECV format varies by version:
    // V3: [0]=code [1]=SNR [2]=rsv1 [3]=rsv2 [4]=channel_idx [5]=path_len [path... optional] [txt_type] [timestamp x4] [text...]
    // Non-V3: [0]=code [1]=channel_idx [2]=path_len [3]=txt_type [4-7]=timestamp [8+]=text
    if (frame.length < 8) return null;
    try {
      final reader = BufferReader(frame);
      final code = reader.readByte();
      if (code != respCodeChannelMsgRecv && code != respCodeChannelMsgRecvV3) {
        return null;
      }

      int pathLen;
      int txtType;
      int? packetPathHashWidth;
      Uint8List pathBytes = Uint8List(0);
      int channelIdx;
      // Only V3 frames report the reception, and only its SNR — RSSI reaches
      // the app through the raw RX log push instead.
      double? snr;
      if (code == respCodeChannelMsgRecvV3) {
        snr = reader.readInt8() / 4.0;
        final flags = reader.readByte();
        final hasPath = (flags & 0x01) != 0;
        reader.skipBytes(1); // Skip reserved byte
        channelIdx = reader.readByte();
        final pathByte = reader.readUInt8();
        // pathByte packs: top 2 bits = hash width mode, low 6 bits = hop count
        packetPathHashWidth = ((pathByte & 0xC0) >> 6) + 1;
        final hopCount = pathByte & 0x3F;
        pathLen = hopCount;
        // If a path is present, read hopCount * width bytes
        if (hasPath && hopCount > 0) {
          final totalPathBytes = hopCount * packetPathHashWidth;
          pathBytes = reader.readBytes(totalPathBytes);
        }
        // After consuming optional path bytes, read the text type byte.
        txtType = reader.readByte();
      } else {
        channelIdx = reader.readByte();
        pathLen = reader.readInt8();
        txtType = reader.readByte();
      }
      final timestampRaw = reader.readUInt32LE();

      if (txtType != txtTypePlain) {
        return null;
      }

      final text = reader.readCString();

      // Extract sender name and actual message from "name: msg" format
      String senderName = 'Unknown';
      String actualText = text;

      final colonIndex = text.indexOf(':');
      if (colonIndex > 0 && colonIndex < text.length - 1 && colonIndex < 50) {
        final potentialSender = text.substring(0, colonIndex);
        if (!RegExp(r'[:\[\]]').hasMatch(potentialSender)) {
          senderName = potentialSender;
          final offset =
              (colonIndex + 1 < text.length && text[colonIndex + 1] == ' ')
              ? colonIndex + 2
              : colonIndex + 1;
          actualText = text.substring(offset);
        }
      }

      final decodedDetails = MessageTextCodec.tryDecodeKnownCompressionDetails(
        actualText,
      );
      final decodedText = decodedDetails?.text ?? actualText;
      final compression = MessageCompressionMetadata.fromEncodedText(
        encodedText: actualText,
        decodedText: decodedText,
        sharedPayloadBytes: includeSenderNameInCompressionRatio
            ? utf8.encode('$senderName: ').length
            : 0,
      );

      final mcmpMessage = decodedDetails?.mcmpMessage;
      return ChannelMessage(
        senderKey: null,
        senderName: senderName,
        text: decodedText,
        wasMcmpCompressed:
            MeshCompressor.instance.hasPrefix(actualText) ||
            McmpAppCodec.isTextPayload(actualText),
        compressionType: compression?.type,
        compressionSavingsPercent: compression?.savingsPercent,
        compressionOriginalBytes: compression?.originalBytes,
        compressionPayloadBytes: compression?.payloadBytes,
        mcmpSignatureStatus:
            mcmpMessage?.signatureStatus ?? McmpSignatureStatus.none,
        mcmpTimestamp: mcmpMessage?.timestamp,
        mcmpSenderName: mcmpMessage?.senderName,
        mcmpIsSigned: mcmpMessage?.isSigned ?? false,
        mcmpSignature: mcmpMessage?.signature,
        mcmpReplyAuthorName: mcmpMessage?.replyAuthorName,
        mcmpReplyTimestamp: mcmpMessage?.replyTimestamp,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestampRaw * 1000),
        isOutgoing: false,
        status: ChannelMessageStatus.sent,
        pathLength: pathLen,
        pathHashWidth: packetPathHashWidth,
        pathBytes: pathBytes,
        snr: snr,
        channelIndex: channelIdx,
      );
    } catch (e) {
      appLogger.error('Error parsing channel message frame: $e');
      // If parsing fails, return null to avoid crashes
      return null;
    }
  }

  static ChannelMessage outgoing(
    String text,
    String senderName,
    int channelIndex, {
    String? messageId,
    DateTime? timestamp,
    DateTime? receivedAt,
    String? originalText,
    String? translatedLanguageCode,
    String? translationModelId,
    String? replyToMessageId,
    String? replyToSenderName,
    String? replyToText,
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
    bool wasBinaryTransport = false,
    int? binaryPacketBytes,
    String? packetRegion,
    bool packetRegionInfoAvailable = false,
    bool packetRegionNotMatched = false,
  }) {
    return ChannelMessage(
      senderKey: null,
      senderName: senderName,
      text: text,
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
      wasBinaryTransport: wasBinaryTransport,
      binaryPacketBytes: binaryPacketBytes,
      timestamp: timestamp ?? DateTime.now(),
      receivedAt: receivedAt,
      isOutgoing: true,
      status: ChannelMessageStatus.pending,
      messageId: messageId,
      pathLength: null,
      pathBytes: Uint8List(0),
      pathVariants: const [],
      channelIndex: channelIndex,
      packetRegion: packetRegion,
      packetRegionInfoAvailable: packetRegionInfoAvailable,
      packetRegionNotMatched: packetRegionNotMatched,
      replyToMessageId: replyToMessageId,
      replyToSenderName: replyToSenderName,
      replyToText: replyToText,
    );
  }

  static List<Uint8List> _mergePathVariants(
    Uint8List pathBytes,
    List<Uint8List>? pathVariants,
  ) {
    final merged = <Uint8List>[];

    void addPath(Uint8List bytes) {
      if (bytes.isEmpty) return;
      for (final existing in merged) {
        if (_pathsEqual(existing, bytes)) return;
      }
      merged.add(bytes);
    }

    if (pathVariants != null) {
      for (final variant in pathVariants) {
        addPath(variant);
      }
    }
    addPath(pathBytes);
    return merged;
  }

  static bool _pathsEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static ReplyInfo? parseReplyMention(String text) {
    final regex = RegExp(r'^@\[([^\]]+)\]\s+(.+)$', dotAll: true);
    final match = regex.firstMatch(text);
    if (match == null) return null;
    return ReplyInfo(
      mentionedNode: match.group(1)!,
      actualMessage: match.group(2)!,
    );
  }

  static ReactionInfo? parseReaction(String text) {
    return ReactionHelper.parseReaction(text);
  }
}

class ReplyInfo {
  final String mentionedNode;
  final String actualMessage;

  ReplyInfo({required this.mentionedNode, required this.actualMessage});
}
