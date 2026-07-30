import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/message_search_worker.dart';

void main() {
  test('batch search keeps source identity and is case-insensitive', () {
    final hits = searchStoredMessageBatch(
      StoredMessageSearchRequest(
        normalizedQuery: 'alice: hello',
        sources: [
          StoredMessageSearchSource(
            sourceId: 'first',
            jsonString: jsonEncode([
              {
                'messageId': 'message-1',
                'senderName': 'Alice',
                'text': 'Hello World',
                'timestamp': 1000,
                'receivedAt': 2000,
              },
            ]),
            type: StoredMessageSearchType.channel,
          ),
          StoredMessageSearchSource(
            sourceId: 'second',
            jsonString: jsonEncode([
              {
                'messageId': 'message-2',
                'senderName': 'Bob',
                'text': 'Hello World',
                'timestamp': 3000,
              },
            ]),
            type: StoredMessageSearchType.channel,
          ),
        ],
      ),
    );

    expect(hits, hasLength(1));
    expect(hits.single.sourceId, 'first');
    expect(hits.single.messageId, 'message-1');
    expect(hits.single.timestampMs, 2000);
  });

  test('legacy channel id uses packet timestamp instead of received time', () {
    const packetTimestamp = 1000;
    const receivedAt = 5000;
    const senderName = 'Alice';
    const text = 'legacy message';

    final hits = searchStoredMessageBatch(
      StoredMessageSearchRequest(
        normalizedQuery: 'legacy',
        sources: [
          StoredMessageSearchSource(
            sourceId: 'channel',
            jsonString: jsonEncode([
              {
                'senderName': senderName,
                'text': text,
                'timestamp': packetTimestamp,
                'receivedAt': receivedAt,
              },
            ]),
            type: StoredMessageSearchType.channel,
          ),
        ],
      ),
    );

    expect(hits, hasLength(1));
    expect(
      hits.single.messageId,
      '${packetTimestamp}_${senderName.hashCode}_${text.hashCode}',
    );
    expect(hits.single.timestampMs, receivedAt);
  });

  test('MCOimg text transports are excluded from text results', () {
    final hits = searchStoredMessageBatch(
      StoredMessageSearchRequest(
        normalizedQuery: 'payload',
        sources: [
          StoredMessageSearchSource(
            sourceId: 'images',
            jsonString: jsonEncode([
              {
                'messageId': 'legacy-image',
                'senderName': 'Alice',
                'text': 'im:payload',
                'timestamp': 1000,
              },
              {
                'messageId': 'v3-image',
                'senderName': 'Alice',
                'text': 'im3:payload',
                'timestamp': 2000,
              },
              {
                'messageId': 'plain-text',
                'senderName': 'Alice',
                'text': 'plain payload',
                'timestamp': 3000,
              },
            ]),
            type: StoredMessageSearchType.channel,
          ),
        ],
      ),
    );

    expect(hits.map((hit) => hit.messageId), ['plain-text']);
  });
}
