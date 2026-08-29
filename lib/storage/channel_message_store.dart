import 'dart:convert';
import 'dart:typed_data';
import 'package:meshcore_open/utils/app_logger.dart';

import '../models/channel_message.dart';
import '../models/message_compression.dart';
import '../models/translation_support.dart';
import '../helpers/mcmp_app_codec.dart';
import '../helpers/channel_path_signal_helper.dart';
import '../helpers/channel_message_timeline_helper.dart';
import '../helpers/message_text_codec.dart';
import '../helpers/mesh_compressor.dart';
import 'channel_name_keyed_store.dart';
import 'message_history_storage.dart';

class ChannelMessageStore with ChannelNameKeyedStore {
  static const String _keyPrefix = 'channel_messages_';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length >= 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';

  /// Save messages for a specific channel
  Future<void> saveChannelMessages(
    int channelIndex,
    List<ChannelMessage> messages, {
    bool orderMessages = true,
  }) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save channel messages.',
      );
      return;
    }
    final history = MessageHistoryStorage.instance;
    final key = channelStorageKey(keyFor, channelIndex);
    if (key == null) {
      appLogger.warn(
        'Channel name is not registered. Cannot save channel messages.',
      );
      return;
    }

    final orderedMessages = orderMessages
        ? _orderedMessages(messages)
        : messages;
    final jsonList = orderedMessages.map((msg) => _messageToJson(msg)).toList();
    final jsonString = jsonEncode(jsonList);

    await history.setString(MessageHistoryKind.channel, key, jsonString);
  }

  Future<void> saveChannelMessage(
    int channelIndex,
    ChannelMessage message,
  ) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot save channel message.');
      return;
    }
    final key = channelStorageKey(keyFor, channelIndex);
    if (key == null) {
      appLogger.warn(
        'Channel name is not registered. Cannot save channel message.',
      );
      return;
    }
    await MessageHistoryStorage.instance.setString(
      MessageHistoryKind.channel,
      key,
      jsonEncode([_messageToJson(message)]),
    );
  }

  Future<void> replaceChannelMessages(
    int channelIndex,
    List<ChannelMessage> messages, {
    bool orderMessages = true,
  }) async {
    if (publicKeyHex.isEmpty) return;
    final key = channelStorageKey(keyFor, channelIndex);
    if (key == null) return;
    final ordered = orderMessages ? _orderedMessages(messages) : messages;
    await MessageHistoryStorage.instance.replaceString(
      MessageHistoryKind.channel,
      key,
      jsonEncode(ordered.map(_messageToJson).toList()),
    );
  }

  Future<void> deleteChannelMessage(int channelIndex, String messageId) async {
    if (publicKeyHex.isEmpty || messageId.isEmpty) return;
    final key = channelStorageKey(keyFor, channelIndex);
    if (key == null) return;
    await MessageHistoryStorage.instance.deleteMessage(
      MessageHistoryKind.channel,
      key,
      messageId,
    );
  }

  /// Load messages for a specific channel
  Future<List<ChannelMessage>> loadChannelMessages(
    int channelIndex, {
    bool allowLegacyMigration = true,
  }) async {
    final jsonString = await _loadChannelMessagesJson(
      channelIndex,
      allowLegacyMigration: allowLegacyMigration,
    );
    return _channelMessagesFromJson(jsonString, channelIndex);
  }

  Future<List<ChannelMessage>> loadLatestChannelMessages(
    int channelIndex, {
    required int limit,
    bool allowLegacyMigration = true,
  }) async {
    final key = await _ensureChannelHistoryKey(
      channelIndex,
      allowLegacyMigration: allowLegacyMigration,
    );
    if (key == null) return const [];
    final jsonString = await MessageHistoryStorage.instance.getLatestString(
      MessageHistoryKind.channel,
      key,
      limit: limit,
    );
    return _channelMessagesFromJson(jsonString, channelIndex);
  }

  Future<List<ChannelMessage>> loadChannelMessagesBefore(
    int channelIndex, {
    required ChannelMessage before,
    required int limit,
    bool allowLegacyMigration = true,
  }) async {
    final key = await _ensureChannelHistoryKey(
      channelIndex,
      allowLegacyMigration: allowLegacyMigration,
    );
    if (key == null) return const [];
    final jsonString = await MessageHistoryStorage.instance.getStringBefore(
      MessageHistoryKind.channel,
      key,
      timelineAtMs: before.receivedAt.millisecondsSinceEpoch,
      messageId: before.messageId,
      limit: limit,
    );
    return _channelMessagesFromJson(jsonString, channelIndex);
  }

  List<ChannelMessage> _channelMessagesFromJson(
    String? jsonString,
    int channelIndex,
  ) {
    if (jsonString == null) return const [];
    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      final messages = <ChannelMessage>[];
      for (var index = 0; index < jsonList.length; index++) {
        final entry = jsonList[index];
        try {
          if (entry is! Map<String, dynamic>) {
            throw const FormatException('Message entry is not an object');
          }
          messages.add(
            decodeStoredMessage(entry).copyWith(channelIndex: channelIndex),
          );
        } catch (error, stackTrace) {
          if (error is OutOfMemoryError || error is StackOverflowError) {
            rethrow;
          }
          appLogger.warn(
            'Skipping invalid channel message at index $index '
            'for channel $channelIndex: ${error.runtimeType}: $error\n'
            '$stackTrace',
            tag: 'MessageHistory',
          );
        }
      }
      return _orderedMessages(messages);
    } catch (error) {
      if (error is OutOfMemoryError || error is StackOverflowError) rethrow;
      appLogger.warn(
        'Could not decode message history for channel $channelIndex: '
        '${error.runtimeType}: $error',
        tag: 'MessageHistory',
      );
      return const [];
    }
  }

  Future<String?> loadChannelMessagesJsonForSearch(
    int channelIndex, {
    bool includeLegacyIndexFallback = false,
    String? normalizedQuery,
  }) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load channel messages.',
      );
      return null;
    }
    final history = MessageHistoryStorage.instance;
    final key = channelStorageKey(keyFor, channelIndex);
    if (key == null) return null;
    var jsonString = normalizedQuery == null
        ? await history.getString(MessageHistoryKind.channel, key)
        : await history.searchString(
            MessageHistoryKind.channel,
            key,
            normalizedQuery,
          );
    if ((jsonString == null || jsonString.isEmpty) &&
        includeLegacyIndexFallback &&
        !history.getKeys(MessageHistoryKind.channel).contains(key)) {
      jsonString =
          await _historyStringForSearch(
            history,
            '$keyFor$channelIndex',
            normalizedQuery,
          ) ??
          await _historyStringForSearch(
            history,
            '$_keyPrefix$channelIndex',
            normalizedQuery,
          );
    }
    return jsonString == null || jsonString.isEmpty ? null : jsonString;
  }

  Future<String?> _historyStringForSearch(
    MessageHistoryStorage history,
    String key,
    String? normalizedQuery,
  ) {
    return normalizedQuery == null
        ? history.getString(MessageHistoryKind.channel, key)
        : history.searchString(
            MessageHistoryKind.channel,
            key,
            normalizedQuery,
          );
  }

  Future<String?> _loadChannelMessagesJson(
    int channelIndex, {
    bool allowLegacyMigration = true,
  }) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load channel messages.',
      );
      return null;
    }
    final history = MessageHistoryStorage.instance;
    final key = channelStorageKey(keyFor, channelIndex);
    if (key == null) return null;
    final scopedIndexKey = '$keyFor$channelIndex';
    final oldKey = '$_keyPrefix$channelIndex';

    String? jsonString = await history.getString(
      MessageHistoryKind.channel,
      key,
    );
    if ((jsonString == null || jsonString.isEmpty) &&
        allowLegacyMigration &&
        allowsLegacyIndexMigration) {
      // One-time migration from the old slot-based storage.
      final legacyJsonString =
          await history.getString(MessageHistoryKind.channel, scopedIndexKey) ??
          await history.getString(MessageHistoryKind.channel, oldKey);
      await history.remove(MessageHistoryKind.channel, scopedIndexKey);
      await history.remove(MessageHistoryKind.channel, oldKey);
      if (legacyJsonString != null && legacyJsonString.isNotEmpty) {
        appLogger.info('Migrating channel messages to name-keyed storage $key');
        await history.setString(
          MessageHistoryKind.channel,
          key,
          legacyJsonString,
        );
        jsonString = legacyJsonString;
      }
    }
    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }
    return jsonString;
  }

  Future<String?> _ensureChannelHistoryKey(
    int channelIndex, {
    required bool allowLegacyMigration,
  }) async {
    if (publicKeyHex.isEmpty) return null;
    final history = MessageHistoryStorage.instance;
    final key = channelStorageKey(keyFor, channelIndex);
    if (key == null) return null;
    if (history.getKeys(MessageHistoryKind.channel).contains(key)) return key;
    if (!allowLegacyMigration || !allowsLegacyIndexMigration) return null;

    final scopedIndexKey = '$keyFor$channelIndex';
    final oldKey = '$_keyPrefix$channelIndex';
    final legacyJsonString =
        await history.getString(MessageHistoryKind.channel, scopedIndexKey) ??
        await history.getString(MessageHistoryKind.channel, oldKey);
    await history.remove(MessageHistoryKind.channel, scopedIndexKey);
    await history.remove(MessageHistoryKind.channel, oldKey);
    if (legacyJsonString == null || legacyJsonString.isEmpty) return null;
    await history.replaceString(
      MessageHistoryKind.channel,
      key,
      legacyJsonString,
    );
    return key;
  }

  List<ChannelMessage> _orderedMessages(List<ChannelMessage> messages) {
    if (messages.length < 2) return messages;
    final ordered = List<ChannelMessage>.of(messages);
    ordered.sort(ChannelMessageTimelineHelper.compare);
    return ordered;
  }

  /// Clear messages for a specific channel
  Future<void> clearChannelMessages(int channelIndex) async {
    final history = MessageHistoryStorage.instance;
    final key = channelStorageKey(keyFor, channelIndex);
    if (key != null) {
      await history.remove(MessageHistoryKind.channel, key);
    }
    await history.remove(MessageHistoryKind.channel, '$keyFor$channelIndex');
  }

  /// Clear all channel messages
  Future<void> clearAllChannelMessages() async {
    final history = MessageHistoryStorage.instance;
    final keys = history
        .getKeys(MessageHistoryKind.channel)
        .where((k) => k.startsWith(keyFor));
    for (var key in keys) {
      await history.remove(MessageHistoryKind.channel, key);
    }
  }

  /// Convert ChannelMessage to JSON map
  Map<String, dynamic> _messageToJson(ChannelMessage msg) {
    return {
      'senderKey': msg.senderKey != null ? base64Encode(msg.senderKey!) : null,
      'senderName': msg.senderName,
      'text': msg.text,
      'rawText': msg.rawText ?? msg.text,
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
      'wasBinaryTransport': msg.wasBinaryTransport,
      'wasBlocked': msg.wasBlocked,
      'binaryPacketBytes': msg.binaryPacketBytes,
      'rawPayload': msg.rawPayload != null
          ? base64Encode(msg.rawPayload!)
          : null,
      'timestamp': msg.timestamp.millisecondsSinceEpoch,
      'receivedAt': msg.receivedAt.millisecondsSinceEpoch,
      'sentByRadioAt': msg.sentByRadioAt?.millisecondsSinceEpoch,
      'isOutgoing': msg.isOutgoing,
      'status': msg.status.index,
      'channelIndex': msg.channelIndex,
      'repeatCount': msg.repeatCount,
      'pathLength': msg.pathLength,
      'pathHashWidth': msg.pathHashWidth,
      'pathBytes': base64Encode(msg.pathBytes),
      'pathVariants': msg.pathVariants.map(base64Encode).toList(),
      'pathObservations': ChannelPathSignalHelper.encode(msg.pathObservations),
      'packetRegion': msg.packetRegion,
      'packetRegionInfoAvailable': msg.packetRegionInfoAvailable,
      'packetRegionNotMatched': msg.packetRegionNotMatched,
      'noRetransmissionWarningSeconds': msg.noRetransmissionWarningSeconds,
      'repeats': msg.repeats.map(_repeatToJson).toList(),
      'messageId': msg.messageId,
      'packetHash': msg.packetHash,
      'replyToMessageId': msg.replyToMessageId,
      'replyToSenderName': msg.replyToSenderName,
      'replyToText': msg.replyToText,
      'replyIsExact': msg.replyIsExact,
      'reactions': msg.reactions,
      'sourceLabel': msg.sourceLabel,
    };
  }

  /// Convert JSON map to ChannelMessage
  static ChannelMessage decodeStoredMessage(Map<String, dynamic> json) {
    final storedText = json['text'] as String;
    final rawText = json['rawText'] as String? ?? storedText;
    final wasMcmpCompressed =
        json['wasMcmpCompressed'] as bool? ??
        MeshCompressor.instance.hasPrefix(rawText);
    final decodedText = json['rawText'] != null
        ? storedText
        : (MessageTextCodec.tryDecodeKnownCompression(rawText) ?? rawText);
    final detectedCompression = MessageCompressionMetadata.fromEncodedText(
      encodedText: rawText,
      decodedText: decodedText,
    );

    final rawPathLength = json['pathLength'] as int?;
    final rawPathBytes = json['pathBytes'] != null
        ? Uint8List.fromList(base64Decode(json['pathBytes'] as String))
        : Uint8List(0);
    final rawPathHashWidth = json['pathHashWidth'] as int?;

    int? decodedPathLength = rawPathLength;
    Uint8List decodedPathBytes = rawPathBytes;
    int? decodedPathHashWidth = rawPathHashWidth;

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
        decodedPathHashWidth = width;
        if (byteLen <= rawPathBytes.length) {
          decodedPathBytes = rawPathBytes.sublist(0, byteLen);
        } else {
          decodedPathBytes = Uint8List(0);
        }
      } else if (rawPathLength == 0) {
        decodedPathBytes = Uint8List(0);
      }
    }

    return ChannelMessage(
      senderKey: json['senderKey'] != null
          ? Uint8List.fromList(base64Decode(json['senderKey']))
          : null,
      senderName: json['senderName'] as String,
      text: decodedText,
      rawText: rawText,
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
      wasBinaryTransport: json['wasBinaryTransport'] as bool? ?? false,
      wasBlocked: json['wasBlocked'] as bool? ?? false,
      binaryPacketBytes: json['binaryPacketBytes'] as int?,
      rawPayload: json['rawPayload'] is String
          ? Uint8List.fromList(base64Decode(json['rawPayload'] as String))
          : null,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['receivedAt'] as int?) ?? (json['timestamp'] as int),
      ),
      sentByRadioAt: json['sentByRadioAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['sentByRadioAt'] as int)
          : null,
      isOutgoing: json['isOutgoing'] as bool,
      status: ChannelMessageStatus.values[json['status'] as int],
      repeatCount: (json['repeatCount'] as int?) ?? 0,
      pathLength: decodedPathLength,
      pathHashWidth: decodedPathHashWidth,
      pathBytes: decodedPathBytes,
      pathVariants: (json['pathVariants'] as List<dynamic>?)
          ?.map((entry) => Uint8List.fromList(base64Decode(entry as String)))
          .toList(),
      pathObservations: ChannelPathSignalHelper.decode(
        json['pathObservations'],
      ),
      packetRegion: json['packetRegion'] as String?,
      packetRegionInfoAvailable:
          json['packetRegionInfoAvailable'] as bool? ?? false,
      packetRegionNotMatched: json['packetRegionNotMatched'] as bool? ?? false,
      noRetransmissionWarningSeconds:
          json['noRetransmissionWarningSeconds'] as int?,
      repeats:
          (json['repeats'] as List<dynamic>?)
              ?.map((entry) => _repeatFromJson(entry as Map<String, dynamic>))
              .toList() ??
          const [],
      channelIndex: json['channelIndex'] as int?,
      messageId: json['messageId'] as String?,
      packetHash: json['packetHash'] as String?,
      replyToMessageId: json['replyToMessageId'] as String?,
      replyToSenderName: json['replyToSenderName'] as String?,
      replyToText: json['replyToText'] as String?,
      replyIsExact: json['replyIsExact'] as bool? ?? false,
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
      sourceLabel: json['sourceLabel'] as String?,
    );
  }

  static McmpSignatureStatus _parseMcmpSignatureStatus(dynamic value) {
    if (value is! String) return McmpSignatureStatus.none;
    for (final status in McmpSignatureStatus.values) {
      if (status.name == value) return status;
    }
    return McmpSignatureStatus.none;
  }

  Map<String, dynamic> _repeatToJson(Repeat repeat) {
    return {
      'repeaterKey': repeat.repeaterKey != null
          ? base64Encode(repeat.repeaterKey!)
          : null,
      'repeaterName': repeat.repeaterName,
      'tripTimeMs': repeat.tripTimeMs,
      'path': repeat.path?.map((bytes) => base64Encode(bytes)).toList() ?? [],
    };
  }

  static Repeat _repeatFromJson(Map<String, dynamic> json) {
    return Repeat(
      repeaterKey: json['repeaterKey'] != null
          ? Uint8List.fromList(base64Decode(json['repeaterKey']))
          : null,
      repeaterName: json['repeaterName'] as String? ?? 'Unknown',
      tripTimeMs: json['tripTimeMs'] as int? ?? 0,
      path: (json['path'] as List<dynamic>?)
          ?.map((entry) => Uint8List.fromList(base64Decode(entry as String)))
          .toList(),
    );
  }
}
