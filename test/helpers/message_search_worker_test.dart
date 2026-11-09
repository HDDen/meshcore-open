import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/message_search_worker.dart';
import 'package:meshcore_open/models/message_filter.dart';

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
    expect(hits.single.identityTimestampMs, 1000);
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
    expect(hits.single.identityTimestampMs, packetTimestamp);
  });

  test('U27b: filtering suppresses only known channel verdicts', () {
    final rows = jsonEncode([
      {
        'messageId': 'marked',
        'senderName': 'Alice',
        'text': 'hello',
        'timestamp': 1000,
        'filterReason': 'manual',
      },
      {
        'messageId': 'future',
        'senderName': 'Alice',
        'text': 'hello again',
        'timestamp': 2000,
        'filterReason': 'unknownFutureReason',
      },
    ]);
    final hits = searchStoredMessageBatch(
      StoredMessageSearchRequest(
        normalizedQuery: 'hello',
        sources: [
          StoredMessageSearchSource(
            sourceId: 'filtered',
            jsonString: rows,
            type: StoredMessageSearchType.channel,
            hideFiltered: true,
          ),
          StoredMessageSearchSource(
            sourceId: 'unfiltered',
            jsonString: rows,
            type: StoredMessageSearchType.channel,
          ),
        ],
      ),
    );
    expect(
      hits.map((hit) => (hit.sourceId, hit.messageId)),
      unorderedEquals([
        ('filtered', 'future'),
        ('unfiltered', 'marked'),
        ('unfiltered', 'future'),
      ]),
    );
  });

  test('U27e: search uses current rules and honours restored posts', () {
    final rows = jsonEncode([
      for (final (id, extra) in [
        ('old-rule', {'filterReason': 'textRule'}),
        ('untagged', <String, Object>{}),
        ('manual', {'filterReason': 'manual'}),
        ('learned', {'filterReason': 'learned'}),
        ('restored', {'filterRestored': true}),
        ('outgoing', {'isOutgoing': true}),
      ])
        {
          'messageId': id,
          'senderName': 'Alice',
          'text': 'buy this now',
          'timestamp': 1000,
          ...extra,
        },
    ]);
    List<String> ids(List<FilterRule> rules, {bool enabled = true}) =>
        searchStoredMessageBatch(
          StoredMessageSearchRequest(
            normalizedQuery: 'buy',
            channelFilterRules: rules,
            sources: [
              StoredMessageSearchSource(
                sourceId: 'channel',
                jsonString: rows,
                type: StoredMessageSearchType.channel,
                hideFiltered: enabled,
              ),
            ],
          ),
        ).map((hit) => hit.messageId).toList();

    const rules = [FilterRule(id: 'sales', pattern: 'buy this')];
    expect(ids(rules), ['restored', 'outgoing']);
    expect(ids(const []), ['old-rule', 'untagged', 'restored', 'outgoing']);
    expect(
      ids(rules, enabled: false),
      ['old-rule', 'untagged', 'manual', 'learned', 'restored', 'outgoing'],
    );
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
