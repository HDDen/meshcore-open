import 'dart:convert';
import 'dart:isolate';

import 'message_text_codec.dart';

enum StoredMessageSearchType { channel, contact, room }

class StoredMessageSearchHit {
  final String messageId;
  final int timestampMs;
  final String senderName;
  final String text;

  const StoredMessageSearchHit({
    required this.messageId,
    required this.timestampMs,
    required this.senderName,
    required this.text,
  });
}

Future<List<StoredMessageSearchHit>> searchStoredMessages({
  required String jsonString,
  required String normalizedQuery,
  required StoredMessageSearchType type,
  String contactName = '',
  Map<String, String> roomSenderNamesByPrefix = const {},
}) async {
  try {
    return await Isolate.run(
      () => _searchStoredMessages(
        jsonString: jsonString,
        normalizedQuery: normalizedQuery,
        type: type,
        contactName: contactName,
        roomSenderNamesByPrefix: roomSenderNamesByPrefix,
      ),
    );
  } catch (_) {
    return const [];
  }
}

List<StoredMessageSearchHit> _searchStoredMessages({
  required String jsonString,
  required String normalizedQuery,
  required StoredMessageSearchType type,
  required String contactName,
  required Map<String, String> roomSenderNamesByPrefix,
}) {
  dynamic decoded;
  try {
    decoded = jsonDecode(jsonString);
  } catch (_) {
    return const [];
  }
  if (decoded is! List<dynamic>) return const [];

  final results = <StoredMessageSearchHit>[];
  for (final entry in decoded) {
    if (entry is! Map<String, dynamic>) continue;
    try {
      final rawText = entry['text'];
      if (rawText is! String) continue;
      final text =
          MessageTextCodec.tryDecodeKnownCompression(rawText) ?? rawText;
      final timestampMs = _timestampFor(entry, type);
      if (timestampMs == null) continue;
      final senderName = _senderNameFor(
        entry,
        type,
        contactName,
        roomSenderNamesByPrefix,
      );
      if (!'$senderName: $text'.toLowerCase().contains(normalizedQuery)) {
        continue;
      }

      results.add(
        StoredMessageSearchHit(
          messageId: _messageIdFor(
            entry,
            type,
            timestampMs,
            senderName,
            text,
          ),
          timestampMs: timestampMs,
          senderName: senderName,
          text: text,
        ),
      );
    } catch (_) {
      // A malformed stored message must not abort the remaining search.
    }
  }
  return results;
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
        final name = roomSenderNamesByPrefix[_hexPrefix(bytes, 4)];
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
    return '${timestampMs}_${senderName.hashCode}_${text.hashCode}';
  }

  final senderKey = entry['senderKey'];
  var senderKeyHex = '';
  if (senderKey is String && senderKey.isNotEmpty) {
    try {
      senderKeyHex = _hexPrefix(base64Decode(senderKey));
    } catch (_) {
      // Keep the fallback ID deterministic even for malformed legacy data.
    }
  }
  return '${timestampMs}_${senderKeyHex}_${text.hashCode}';
}

String _hexPrefix(List<int> bytes, [int? count]) {
  final length = count == null || count > bytes.length ? bytes.length : count;
  final buffer = StringBuffer();
  for (var index = 0; index < length; index++) {
    buffer.write(bytes[index].toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
