import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/message.dart';
import '../models/message_compression.dart';
import '../models/translation_support.dart';
import '../helpers/mcmp_app_codec.dart';
import '../helpers/message_text_codec.dart';
import '../helpers/mesh_compressor.dart';
import '../utils/app_logger.dart';
import 'message_history_database.dart';
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

  Future<void> saveMessage(String contactKeyHex, Message message) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot save message.');
      return;
    }
    await MessageHistoryStorage.instance.setString(
      MessageHistoryKind.direct,
      '$keyFor$contactKeyHex',
      jsonEncode([_messageToJson(message)]),
    );
  }

  Future<void> replaceMessages(
    String contactKeyHex,
    List<Message> messages,
  ) async {
    if (publicKeyHex.isEmpty) return;
    final key = '$keyFor$contactKeyHex';
    await MessageHistoryStorage.instance.replaceString(
      MessageHistoryKind.direct,
      key,
      jsonEncode(messages.map(_messageToJson).toList()),
    );
  }

  Future<void> deleteMessage(String contactKeyHex, String messageId) async {
    if (publicKeyHex.isEmpty || messageId.isEmpty) return;
    await MessageHistoryStorage.instance.deleteMessage(
      MessageHistoryKind.direct,
      '$keyFor$contactKeyHex',
      messageId,
    );
  }

  Future<List<Message>> loadMessages(String contactKeyHex) async {
    final jsonString = await _loadMessagesJson(contactKeyHex);
    return _messagesFromJson(jsonString, contextKey: contactKeyHex);
  }

  Future<List<Message>> loadLatestMessages(
    String contactKeyHex, {
    required int limit,
  }) async {
    final key = await _ensureScopedHistory(contactKeyHex);
    if (key == null) return const [];
    final jsonString = await MessageHistoryStorage.instance.getLatestString(
      MessageHistoryKind.direct,
      key,
      limit: limit,
    );
    return _messagesFromJson(jsonString, contextKey: contactKeyHex);
  }

  Future<List<Message>> loadMessagesBefore(
    String contactKeyHex, {
    required Message before,
    required int limit,
  }) async {
    final key = await _ensureScopedHistory(contactKeyHex);
    if (key == null) return const [];
    final jsonString = await MessageHistoryStorage.instance.getStringBefore(
      MessageHistoryKind.direct,
      key,
      timelineAtMs: _timelineAt(before).millisecondsSinceEpoch,
      messageId: before.messageId,
      limit: limit,
    );
    return _messagesFromJson(jsonString, contextKey: contactKeyHex);
  }

  Future<List<Message>> loadMessagesAfter(
    String contactKeyHex, {
    required Message after,
    required int limit,
  }) async {
    final key = await _ensureScopedHistory(contactKeyHex);
    if (key == null) return const [];
    final jsonString = await MessageHistoryStorage.instance.getStringAfter(
      MessageHistoryKind.direct,
      key,
      timelineAtMs: _timelineAt(after).millisecondsSinceEpoch,
      messageId: after.messageId,
      limit: limit,
    );
    return _messagesFromJson(jsonString, contextKey: contactKeyHex);
  }

  Future<List<Message>> loadScopedMessages(String contactKeyHex) async {
    final jsonString = await loadMessagesJsonForSearch(contactKeyHex);
    return _messagesFromJson(jsonString, contextKey: contactKeyHex);
  }

  List<Message> _messagesFromJson(
    String? jsonString, {
    required String contextKey,
  }) {
    if (jsonString == null) return [];

    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      final messages = <Message>[];
      for (var index = 0; index < jsonList.length; index++) {
        final entry = jsonList[index];
        try {
          if (entry is! Map<String, dynamic>) {
            throw const FormatException('Message entry is not an object');
          }
          messages.add(decodeStoredMessage(entry));
        } catch (error, stackTrace) {
          if (error is OutOfMemoryError || error is StackOverflowError) {
            rethrow;
          }
          appLogger.warn(
            'Skipping invalid direct message at index $index '
            'for $contextKey: '
            '${error.runtimeType}: $error\n$stackTrace',
            tag: 'MessageHistory',
          );
        }
      }
      return messages;
    } catch (error) {
      if (error is OutOfMemoryError || error is StackOverflowError) rethrow;
      appLogger.warn(
        'Could not decode direct message history for $contextKey: '
        '${error.runtimeType}: $error',
        tag: 'MessageHistory',
      );
      return [];
    }
  }

  Future<String?> loadMessagesJsonForSearch(
    String contactKeyHex, {
    bool includeLegacyUnscoped = false,
    String? normalizedQuery,
  }) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot load messages.');
      return null;
    }
    final history = MessageHistoryStorage.instance;
    final key = '$keyFor$contactKeyHex';
    var jsonString = normalizedQuery == null
        ? await history.getString(MessageHistoryKind.direct, key)
        : await history.searchString(
            MessageHistoryKind.direct,
            key,
            normalizedQuery,
          );
    if ((jsonString == null || jsonString.isEmpty) &&
        includeLegacyUnscoped &&
        !history.getKeys(MessageHistoryKind.direct).contains(key)) {
      final legacyKey = '$_keyPrefix$contactKeyHex';
      jsonString = normalizedQuery == null
          ? await history.getString(MessageHistoryKind.direct, legacyKey)
          : await history.searchString(
              MessageHistoryKind.direct,
              legacyKey,
              normalizedQuery,
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
    String? jsonString = await history.getString(
      MessageHistoryKind.direct,
      key,
    );
    if (jsonString == null || jsonString.isEmpty) {
      // Attempt migration from legacy unscoped key on first load
      final legacyJsonString = await history.getString(
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
      jsonString = await history.getString(MessageHistoryKind.direct, keyFor);
    }
    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }
    return jsonString;
  }

  Future<String?> _ensureScopedHistory(String contactKeyHex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot load messages.');
      return null;
    }
    final history = MessageHistoryStorage.instance;
    final key = '$keyFor$contactKeyHex';
    if (history.getKeys(MessageHistoryKind.direct).contains(key)) return key;

    final oldKey = '$_keyPrefix$contactKeyHex';
    final legacyJsonString = await history.getString(
      MessageHistoryKind.direct,
      oldKey,
    );
    if (legacyJsonString != null && legacyJsonString.isNotEmpty) {
      await history.remove(MessageHistoryKind.direct, oldKey);
      await history.replaceString(
        MessageHistoryKind.direct,
        key,
        legacyJsonString,
      );
      return key;
    }
    if (history.getKeys(MessageHistoryKind.direct).contains(keyFor)) {
      return keyFor;
    }
    return null;
  }

  DateTime _timelineAt(Message message) {
    if (message.fourByteRoomContactKey.isNotEmpty) {
      return message.receivedAt ?? message.timestamp;
    }
    return message.timestamp;
  }

  /// True when this conversation could hold a shared marker.
  ///
  /// The database prepares a small key cache at startup, so the map can reject
  /// conversations without markers without loading their message rows.
  ///
  /// This stays synchronous so a sweep over every contact pays no async hop.
  bool mayContainMarker(String contactKeyHex) {
    if (publicKeyHex.isEmpty) return false;
    final history = MessageHistoryStorage.instance;
    for (final key in [
      '$keyFor$contactKeyHex',
      '$_keyPrefix$contactKeyHex',
      keyFor,
    ]) {
      if (history.mayContainMarker(key)) return true;
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
    final MessageHistorySummaryRow? databaseSummary = await history
        .directSummary(key);
    if (databaseSummary != null) {
      return _summaryFromDatabase(databaseSummary);
    }
    var jsonString = await history.getString(MessageHistoryKind.direct, key);
    if ((jsonString == null || jsonString.isEmpty) && includeLegacyUnscoped) {
      final legacyJsonString = await history.getString(
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
        final roomAuthorKey = entry['fourByteRoomContactKey'] as String?;
        final timelineMs = roomAuthorKey?.isNotEmpty == true
            ? (entry['receivedAt'] as int? ?? timestampMs)
            : timestampMs;
        final timestamp = DateTime.fromMillisecondsSinceEpoch(timelineMs);
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

  Future<Map<String, MessageStoreSummary>> loadMessageSummaries(
    Iterable<String> contactKeyHexes, {
    bool includeLegacyUnscoped = false,
  }) async {
    final contactKeys = contactKeyHexes.toSet();
    if (publicKeyHex.isEmpty || contactKeys.isEmpty) return const {};

    if (kIsWeb) {
      final result = <String, MessageStoreSummary>{};
      for (final contactKeyHex in contactKeys) {
        final summary = await loadMessageSummary(
          contactKeyHex,
          includeLegacyUnscoped: includeLegacyUnscoped,
        );
        if (summary != null) result[contactKeyHex] = summary;
      }
      return result;
    }

    final scopedStorageKeys = {
      for (final contactKeyHex in contactKeys)
        '$keyFor$contactKeyHex': contactKeyHex,
    };
    final legacyStorageKeys = includeLegacyUnscoped
        ? {
            for (final contactKeyHex in contactKeys)
              '$_keyPrefix$contactKeyHex': contactKeyHex,
          }
        : const <String, String>{};
    final databaseSummaries = await MessageHistoryStorage.instance
        .directSummaries([
          ...scopedStorageKeys.keys,
          ...legacyStorageKeys.keys,
        ]);
    final result = <String, MessageStoreSummary>{};
    for (final contactKeyHex in contactKeys) {
      final scoped = databaseSummaries['$keyFor$contactKeyHex'];
      final legacy = databaseSummaries['$_keyPrefix$contactKeyHex'];
      final summary = scoped ?? legacy;
      if (summary != null) {
        result[contactKeyHex] = _summaryFromDatabase(summary);
      }
    }
    return result;
  }

  MessageStoreSummary _summaryFromDatabase(
    MessageHistorySummaryRow databaseSummary,
  ) {
    final latestMessageText =
        MessageTextCodec.tryDecodeKnownCompression(
          databaseSummary.latestRawText,
        ) ??
        databaseSummary.latestRawText;
    return MessageStoreSummary(
      messageCount: databaseSummary.messageCount,
      latestMessageAt: DateTime.fromMillisecondsSinceEpoch(
        databaseSummary.latestTimestampMs,
      ),
      latestMessageText: latestMessageText,
    );
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
      'rawText': msg.rawText ?? msg.text,
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
      'containerTimestamp': msg.containerTimestamp,
      'containerSenderName': msg.containerSenderName,
      'mcmpIsSigned': msg.mcmpIsSigned,
      'mcmpSignature': msg.mcmpSignature != null
          ? base64Encode(msg.mcmpSignature!)
          : null,
      'containerReplyAuthorName': msg.containerReplyAuthorName,
      'containerReplyTimestamp': msg.containerReplyTimestamp,
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

  static Message decodeStoredMessage(Map<String, dynamic> json) {
    final storedText = json['text'] as String;
    final rawText = json['rawText'] as String? ?? storedText;
    final isCli = json['isCli'] as bool? ?? false;
    final wasMcmpCompressed =
        json['wasMcmpCompressed'] as bool? ??
        MeshCompressor.instance.hasPrefix(rawText);
    final decodedText = json['rawText'] != null || isCli
        ? storedText
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
      rawText: rawText,
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
      // Rows written before the rename still carry the mcmp* keys.
      containerTimestamp:
          json['containerTimestamp'] as int? ?? json['mcmpTimestamp'] as int?,
      containerSenderName:
          json['containerSenderName'] as String? ??
          json['mcmpSenderName'] as String?,
      mcmpIsSigned: json['mcmpIsSigned'] as bool? ?? false,
      mcmpSignature: json['mcmpSignature'] != null
          ? Uint8List.fromList(base64Decode(json['mcmpSignature'] as String))
          : null,
      containerReplyAuthorName:
          json['containerReplyAuthorName'] as String? ??
          json['mcmpReplyAuthorName'] as String?,
      containerReplyTimestamp:
          json['containerReplyTimestamp'] as int? ??
          json['mcmpReplyTimestamp'] as int?,
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

  static McmpSignatureStatus _parseMcmpSignatureStatus(dynamic value) {
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
