import 'dart:convert';
import 'dart:typed_data';
import '../models/message.dart';
import '../models/message_compression.dart';
import '../models/translation_support.dart';
import '../helpers/mcmp_app_codec.dart';
import '../helpers/message_text_codec.dart';
import '../helpers/mesh_compressor.dart';
import '../utils/app_logger.dart';
import 'message_history_storage.dart';

class MessageStore {
  static const String _keyPrefix = 'messages_';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length >= 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';

  Future<void> saveMessages(
    String contactKeyHex,
    List<Message> messages,
  ) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot save messages.');
      return;
    }
    final history = MessageHistoryStorage.instance;
    final key = '$keyFor$contactKeyHex';
    final jsonList = messages.map(_messageToJson).toList();
    await history.setString(
      MessageHistoryKind.direct,
      key,
      jsonEncode(jsonList),
    );
  }

  Future<List<Message>> loadMessages(String contactKeyHex) async {
    final jsonString = await _loadMessagesJson(contactKeyHex);
    return _messagesFromJson(jsonString);
  }

  Future<List<Message>> loadScopedMessages(String contactKeyHex) async {
    final jsonString = await loadMessagesJsonForSearch(contactKeyHex);
    return _messagesFromJson(jsonString);
  }

  List<Message> _messagesFromJson(String? jsonString) {
    if (jsonString == null) return [];

    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList.map((json) => _messageFromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<String?> loadMessagesJsonForSearch(
    String contactKeyHex, {
    bool includeLegacyUnscoped = false,
  }) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot load messages.');
      return null;
    }
    final history = MessageHistoryStorage.instance;
    final key = '$keyFor$contactKeyHex';
    var jsonString = history.getString(MessageHistoryKind.direct, key);
    if ((jsonString == null || jsonString.isEmpty) && includeLegacyUnscoped) {
      jsonString = history.getString(
        MessageHistoryKind.direct,
        '$_keyPrefix$contactKeyHex',
      );
    }
    return jsonString == null || jsonString.isEmpty ? null : jsonString;
  }

  Future<String?> _loadMessagesJson(String contactKeyHex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot load messages.');
      return null;
    }
    final history = MessageHistoryStorage.instance;
    final key = '$keyFor$contactKeyHex';
    final oldKey = '$_keyPrefix$contactKeyHex';
    String? jsonString = history.getString(MessageHistoryKind.direct, key);
    if (jsonString == null || jsonString.isEmpty) {
      // Attempt migration from legacy unscoped key on first load
      final legacyJsonString = history.getString(
        MessageHistoryKind.direct,
        oldKey,
      );
      await history.remove(MessageHistoryKind.direct, oldKey);
      if (legacyJsonString != null && legacyJsonString.isNotEmpty) {
        appLogger.info(
          'Migrating messages from legacy key $oldKey to scoped key $key',
        );
        await history.setString(
          MessageHistoryKind.direct,
          key,
          legacyJsonString,
        );
        jsonString = legacyJsonString;
      }
    }
    if (jsonString == null || jsonString.isEmpty) {
      jsonString = history.getString(MessageHistoryKind.direct, keyFor);
    }
    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }
    return jsonString;
  }

  /// True when this conversation's stored blob could hold a shared marker.
  ///
  /// A conversation is one JSON string, so deciding this by decoding it costs
  /// as much as loading it. The map only needs the handful of conversations
  /// that carry pins, and a substring scan over the raw string rejects the
  /// rest for the price of reading it. False positives are fine — the caller
  /// decodes and parses properly — false negatives are not, so this looks for
  /// the bare marker prefix and catches `del:m:` along with `m:`.
  ///
  /// Deliberately not built on [_loadMessagesJson]: that one migrates legacy
  /// keys, so peeking at a few hundred conversations through it would fire a
  /// preferences write per contact. This reads and returns, nothing else, and
  /// stays synchronous so a caller sweeping every contact pays no async hop.
  bool mayContainMarker(String contactKeyHex) {
    if (publicKeyHex.isEmpty) return false;
    final history = MessageHistoryStorage.instance;
    for (final key in [
      '$keyFor$contactKeyHex',
      '$_keyPrefix$contactKeyHex',
      keyFor,
    ]) {
      final jsonString = history.getString(MessageHistoryKind.direct, key);
      if (jsonString != null && jsonString.contains('m:')) return true;
    }
    return false;
  }

  Future<MessageStoreSummary?> loadMessageSummary(
    String contactKeyHex, {
    bool includeLegacyUnscoped = true,
  }) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot load messages.');
      return null;
    }
    final history = MessageHistoryStorage.instance;
    final key = '$keyFor$contactKeyHex';
    final oldKey = '$_keyPrefix$contactKeyHex';
    var jsonString = history.getString(MessageHistoryKind.direct, key);
    if ((jsonString == null || jsonString.isEmpty) && includeLegacyUnscoped) {
      final legacyJsonString = history.getString(
        MessageHistoryKind.direct,
        oldKey,
      );
      if (legacyJsonString != null && legacyJsonString.isNotEmpty) {
        jsonString = legacyJsonString;
      }
    }
    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }

    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      DateTime? latestMessageAt;
      String latestRawMessageText = '';
      var messageCount = 0;
      for (final entry in jsonList) {
        if (entry is! Map<String, dynamic>) continue;
        if (entry['isCli'] as bool? ?? false) continue;
        final timestampMs = entry['timestamp'] as int?;
        if (timestampMs == null) continue;
        messageCount++;
        final timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs);
        if (latestMessageAt == null || timestamp.isAfter(latestMessageAt)) {
          latestMessageAt = timestamp;
          final rawText = entry['text'];
          latestRawMessageText = rawText is String ? rawText : '';
        }
      }
      if (messageCount == 0 || latestMessageAt == null) return null;
      final latestMessageText =
          MessageTextCodec.tryDecodeKnownCompression(latestRawMessageText) ??
          latestRawMessageText;
      return MessageStoreSummary(
        messageCount: messageCount,
        latestMessageAt: latestMessageAt,
        latestMessageText: latestMessageText,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearMessages(String contactKeyHex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot clear messages.');
      return;
    }
    final history = MessageHistoryStorage.instance;
    final key = '$keyFor$contactKeyHex';
    await history.remove(MessageHistoryKind.direct, key);
  }

  Map<String, dynamic> _messageToJson(Message msg) {
    return {
      'senderKey': base64Encode(msg.senderKey),
      'text': msg.text,
      'timestamp': msg.timestamp.millisecondsSinceEpoch,
      'receivedAt': msg.receivedAt?.millisecondsSinceEpoch,
      'isOutgoing': msg.isOutgoing,
      'isCli': msg.isCli,
      'status': msg.status.index,
      'messageId': msg.messageId,
      'originalText': msg.originalText,
      'translatedText': msg.translatedText,
      'translatedLanguageCode': msg.translatedLanguageCode,
      'translationStatus': msg.translationStatus.value,
      'translationModelId': msg.translationModelId,
      'wasMcmpCompressed': msg.wasMcmpCompressed,
      'compressionType': msg.compressionType?.name,
      'compressionSavingsPercent': msg.compressionSavingsPercent,
      'compressionOriginalBytes': msg.compressionOriginalBytes,
      'compressionPayloadBytes': msg.compressionPayloadBytes,
      'mcmpSignatureStatus': msg.mcmpSignatureStatus.name,
      'mcmpTimestamp': msg.mcmpTimestamp,
      'mcmpSenderName': msg.mcmpSenderName,
      'mcmpIsSigned': msg.mcmpIsSigned,
      'mcmpSignature': msg.mcmpSignature != null
          ? base64Encode(msg.mcmpSignature!)
          : null,
      'mcmpReplyAuthorName': msg.mcmpReplyAuthorName,
      'mcmpReplyTimestamp': msg.mcmpReplyTimestamp,
      'verifiedSenderKeyHex': msg.verifiedSenderKeyHex,
      'mcmpNameCollision': msg.mcmpNameCollision,
      'replyToMessageId': msg.replyToMessageId,
      'replyToSenderName': msg.replyToSenderName,
      'replyToText': msg.replyToText,
      'retryCount': msg.retryCount,
      'estimatedTimeoutMs': msg.estimatedTimeoutMs,
      'expectedAckHash': msg.expectedAckHash,
      'sentAt': msg.sentAt?.millisecondsSinceEpoch,
      'sentByRadioAt': msg.sentByRadioAt?.millisecondsSinceEpoch,
      'sentByRadioWaitSeconds': msg.sentByRadioWaitSeconds,
      'deliveredAt': msg.deliveredAt?.millisecondsSinceEpoch,
      'tripTimeMs': msg.tripTimeMs,
      'pathLength': msg.pathLength,
      'pathBytes': msg.pathBytes.isNotEmpty
          ? base64Encode(msg.pathBytes)
          : null,
      'deliveryProgressTotalSteps': msg.deliveryProgressTotalSteps,
      'deliveryProgressCompletedSteps': msg.deliveryProgressCompletedSteps,
      'reactions': msg.reactions,
      'reactionStatuses': msg.reactionStatuses.map(
        (key, value) => MapEntry(key, value.index),
      ),
      'fourByteRoomContactKey': base64Encode(msg.fourByteRoomContactKey),
      'wasBlocked': msg.wasBlocked,
      'sourceLabel': msg.sourceLabel,
    };
  }

  Message _messageFromJson(Map<String, dynamic> json) {
    final rawText = json['text'] as String;
    final isCli = json['isCli'] as bool? ?? false;
    final wasMcmpCompressed =
        json['wasMcmpCompressed'] as bool? ??
        MeshCompressor.instance.hasPrefix(rawText);
    final decodedText = isCli
        ? rawText
        : (MessageTextCodec.tryDecodeKnownCompression(rawText) ?? rawText);
    final detectedCompression = isCli
        ? null
        : MessageCompressionMetadata.fromEncodedText(
            encodedText: rawText,
            decodedText: decodedText,
          );

    final rawPathLength = json['pathLength'] as int?;
    final rawPathBytes = json['pathBytes'] != null
        ? Uint8List.fromList(base64Decode(json['pathBytes'] as String))
        : Uint8List(0);

    int? decodedPathLength = rawPathLength;
    Uint8List decodedPathBytes = rawPathBytes;

    if (rawPathLength != null) {
      if (rawPathLength == 0xFF || rawPathLength < 0) {
        decodedPathLength = -1;
        decodedPathBytes = Uint8List(0);
      } else if (rawPathLength >= 64) {
        final mode = (rawPathLength & 0xC0) >> 6;
        final hopCount = rawPathLength & 0x3F;
        final width = mode + 1;
        final byteLen = hopCount * width;
        decodedPathLength = hopCount;
        if (byteLen <= rawPathBytes.length) {
          decodedPathBytes = rawPathBytes.sublist(0, byteLen);
        } else {
          decodedPathBytes = Uint8List(0);
        }
      } else if (rawPathLength == 0) {
        decodedPathBytes = Uint8List(0);
      }
    }

    return Message(
      senderKey: Uint8List.fromList(base64Decode(json['senderKey'] as String)),
      text: decodedText,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      receivedAt: json['receivedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['receivedAt'] as int)
          : null,
      isOutgoing: json['isOutgoing'] as bool,
      isCli: isCli,
      status: MessageStatus.values[json['status'] as int],
      messageId: json['messageId'] as String?,
      originalText: json['originalText'] as String?,
      translatedText: json['translatedText'] as String?,
      translatedLanguageCode: json['translatedLanguageCode'] as String?,
      translationStatus: parseMessageTranslationStatus(
        json['translationStatus'],
      ),
      translationModelId: json['translationModelId'] as String?,
      wasMcmpCompressed: wasMcmpCompressed,
      compressionType:
          MessageCompressionTypeLabel.fromJson(json['compressionType']) ??
          detectedCompression?.type ??
          (wasMcmpCompressed ? MessageCompressionType.mcmp : null),
      compressionSavingsPercent:
          json['compressionSavingsPercent'] as int? ??
          detectedCompression?.savingsPercent,
      compressionOriginalBytes:
          json['compressionOriginalBytes'] as int? ??
          detectedCompression?.originalBytes,
      compressionPayloadBytes:
          json['compressionPayloadBytes'] as int? ??
          detectedCompression?.payloadBytes,
      mcmpSignatureStatus: _parseMcmpSignatureStatus(
        json['mcmpSignatureStatus'],
      ),
      mcmpTimestamp: json['mcmpTimestamp'] as int?,
      mcmpSenderName: json['mcmpSenderName'] as String?,
      mcmpIsSigned: json['mcmpIsSigned'] as bool? ?? false,
      mcmpSignature: json['mcmpSignature'] != null
          ? Uint8List.fromList(base64Decode(json['mcmpSignature'] as String))
          : null,
      mcmpReplyAuthorName: json['mcmpReplyAuthorName'] as String?,
      mcmpReplyTimestamp: json['mcmpReplyTimestamp'] as int?,
      verifiedSenderKeyHex: json['verifiedSenderKeyHex'] as String?,
      mcmpNameCollision: json['mcmpNameCollision'] as bool? ?? false,
      replyToMessageId: json['replyToMessageId'] as String?,
      replyToSenderName: json['replyToSenderName'] as String?,
      replyToText: json['replyToText'] as String?,
      retryCount: json['retryCount'] as int? ?? 0,
      estimatedTimeoutMs: json['estimatedTimeoutMs'] as int?,
      expectedAckHash: json['expectedAckHash'] as int? ?? 0,
      sentAt: json['sentAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['sentAt'] as int)
          : null,
      sentByRadioAt: json['sentByRadioAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['sentByRadioAt'] as int)
          : null,
      sentByRadioWaitSeconds: (json['sentByRadioWaitSeconds'] as List<dynamic>?)
          ?.map((value) => value as int)
          .toList(),
      deliveredAt: json['deliveredAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['deliveredAt'] as int)
          : null,
      tripTimeMs: json['tripTimeMs'] as int?,
      pathLength: decodedPathLength,
      pathBytes: decodedPathBytes,
      deliveryProgressTotalSteps:
          json['deliveryProgressTotalSteps'] as int? ?? 0,
      deliveryProgressCompletedSteps:
          json['deliveryProgressCompletedSteps'] as int? ?? 0,
      reactions:
          (json['reactions'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              key,
              (value is int)
                  ? List<String?>.filled(value, null)
                  : List<String?>.from(value),
            ),
          ) ??
          {},
      reactionStatuses:
          (json['reactionStatuses'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(key, MessageStatus.values[value as int]),
          ) ??
          {},
      wasBlocked: json['wasBlocked'] as bool? ?? false,
      sourceLabel: json['sourceLabel'] as String?,
      fourByteRoomContactKey: json['fourByteRoomContactKey'] != null
          ? Uint8List.fromList(
              base64Decode(json['fourByteRoomContactKey'] as String),
            )
          : null,
    );
  }

  McmpSignatureStatus _parseMcmpSignatureStatus(dynamic value) {
    if (value is! String) return McmpSignatureStatus.none;
    for (final status in McmpSignatureStatus.values) {
      if (status.name == value) return status;
    }
    return McmpSignatureStatus.none;
  }
}

class MessageStoreSummary {
  const MessageStoreSummary({
    required this.messageCount,
    required this.latestMessageAt,
    required this.latestMessageText,
  });

  final int messageCount;
  final DateTime latestMessageAt;
  final String latestMessageText;
}
