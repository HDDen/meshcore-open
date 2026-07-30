import 'dart:convert';

import 'mcmp_app_codec.dart';
import 'message_text_codec.dart';
import 'mesh_compressor.dart';
import 'smaz.dart';

enum StoredMessageSearchType { channel, contact, room }

class StoredMessageSearchSource {
  final String sourceId;
  final String jsonString;
  final StoredMessageSearchType type;
  final String contactName;

  const StoredMessageSearchSource({
    required this.sourceId,
    required this.jsonString,
    required this.type,
    this.contactName = '',
  });
}

class StoredMessageSearchRequest {
  final String normalizedQuery;
  final List<StoredMessageSearchSource> sources;
  final Map<String, String> roomSenderNamesByPrefix;

  const StoredMessageSearchRequest({
    required this.normalizedQuery,
    required this.sources,
    this.roomSenderNamesByPrefix = const {},
  });
}

class StoredMessageSearchHit {
  final String sourceId;
  final String messageId;
  final int timestampMs;
  final int identityTimestampMs;
  final String senderName;
  final String text;

  const StoredMessageSearchHit({
    required this.sourceId,
    required this.messageId,
    required this.timestampMs,
    required this.identityTimestampMs,
    required this.senderName,
    required this.text,
  });
}

List<StoredMessageSearchHit> searchStoredMessageBatch(
  StoredMessageSearchRequest request,
) {
  final results = <StoredMessageSearchHit>[];
  for (final source in request.sources) {
    _searchStoredMessages(
      source: source,
      normalizedQuery: request.normalizedQuery,
      roomSenderNamesByPrefix: request.roomSenderNamesByPrefix,
      results: results,
    );
  }
  return results;
}

void _searchStoredMessages({
  required StoredMessageSearchSource source,
  required String normalizedQuery,
  required Map<String, String> roomSenderNamesByPrefix,
  required List<StoredMessageSearchHit> results,
}) {
  dynamic decoded;
  try {
    decoded = jsonDecode(source.jsonString);
  } catch (_) {
    return;
  }
  if (decoded is! List<dynamic>) return;

  for (final entry in decoded) {
    if (entry is! Map<String, dynamic>) continue;
    try {
      final rawText = entry['text'];
      if (rawText is! String || _isMcoImageText(rawText)) continue;
      final text = _decodeStoredTextIfNeeded(rawText);
      final timestampMs = _timestampFor(entry, source.type);
      if (timestampMs == null) continue;
      final senderName = _senderNameFor(
        entry,
        source.type,
        source.contactName,
        roomSenderNamesByPrefix,
      );
      if (!'$senderName: $text'.toLowerCase().contains(normalizedQuery)) {
        continue;
      }

      results.add(
        StoredMessageSearchHit(
          sourceId: source.sourceId,
          messageId: _messageIdFor(
            entry,
            source.type,
            timestampMs,
            senderName,
            text,
          ),
          timestampMs: timestampMs,
          identityTimestampMs:
              source.type == StoredMessageSearchType.channel
              ? entry['timestamp'] as int? ?? timestampMs
              : timestampMs,
          senderName: senderName,
          text: text,
        ),
      );
    } catch (_) {
      // A malformed stored message must not abort the remaining search.
    }
  }
}

bool _isMcoImageText(String text) {
  final trimmed = text.trimLeft();
  return trimmed.startsWith('im:') || trimmed.startsWith('im3:');
}

String _decodeStoredTextIfNeeded(String text) {
  final trimmed = text.trimLeft();
  final isKnownCompressedText =
      trimmed.startsWith(McmpAppCodec.textPrefix) ||
      MeshCompressor.instance.hasPrefix(trimmed) ||
      Smaz.hasPrefix(trimmed);
  if (!isKnownCompressedText) return text;
  return MessageTextCodec.tryDecodeKnownCompression(text) ?? text;
}

int? _timestampFor(
  Map<String, dynamic> entry,
  StoredMessageSearchType type,
) {
  if (type == StoredMessageSearchType.channel) {
    return entry['receivedAt'] as int? ?? entry['timestamp'] as int?;
  }
  return entry['timestamp'] as int?;
}

String _senderNameFor(
  Map<String, dynamic> entry,
  StoredMessageSearchType type,
  String contactName,
  Map<String, String> roomSenderNamesByPrefix,
) {
  if (type == StoredMessageSearchType.channel) {
    return entry['senderName'] as String? ?? '';
  }
  if (type == StoredMessageSearchType.contact) {
    return (entry['isOutgoing'] as bool? ?? false) ? 'Me' : contactName;
  }

  final roomKey = entry['fourByteRoomContactKey'];
  if (roomKey is String && roomKey.isNotEmpty) {
    try {
      final bytes = base64Decode(roomKey);
      if (bytes.length >= 4) {
        final name = roomSenderNamesByPrefix[hexPrefix(bytes, 4)];
        if (name != null) return name;
      }
    } catch (_) {
      // Fall back to the room/contact name below.
    }
  }
  return (entry['isOutgoing'] as bool? ?? false) ? 'Me' : contactName;
}

String _messageIdFor(
  Map<String, dynamic> entry,
  StoredMessageSearchType type,
  int timestampMs,
  String senderName,
  String text,
) {
  final storedId = entry['messageId'];
  if (storedId is String && storedId.isNotEmpty) return storedId;
  if (type == StoredMessageSearchType.channel) {
    final packetTimestampMs = entry['timestamp'] as int? ?? timestampMs;
    return '${packetTimestampMs}_${senderName.hashCode}_${text.hashCode}';
  }

  final senderKey = entry['senderKey'];
  var senderKeyHex = '';
  if (senderKey is String && senderKey.isNotEmpty) {
    try {
      senderKeyHex = hexPrefix(base64Decode(senderKey));
    } catch (_) {
      // Keep the fallback ID deterministic even for malformed legacy data.
    }
  }
  return '${timestampMs}_${senderKeyHex}_${text.hashCode}';
}

String hexPrefix(List<int> bytes, [int? count]) {
  final length = count == null || count > bytes.length ? bytes.length : count;
  final buffer = StringBuffer();
  for (var index = 0; index < length; index++) {
    buffer.write(bytes[index].toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
