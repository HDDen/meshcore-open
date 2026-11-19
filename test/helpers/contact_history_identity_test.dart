import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/contact_history_identity.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/storage/shared_message_history_helper.dart';

void main() {
  final radio = 'aa' * 32;
  final extra = 'bb' * 32;
  final other = 'cc' * 32;
  Message post({String id = 'radio-message', String? key, String? name, bool flood = false}) => Message(
    messageId: id, senderKey: Uint8List(32), text: 'Message',
    timestamp: DateTime.utc(2026), isOutgoing: true,
    status: MessageStatus.delivered, sentByFlood: flood,
    sharedHistorySourceKey: key, sharedHistorySourceName: name,
  );
  Message view(Message message, String? selected) => contactHistoryForIdentity(
    message, selectedIdentityKey: selected, radioKey: radio, radioName: 'Тук-тук',
  );

  for (final flood in [false, true]) {
    test('radio source is shown only in other identity chats (flood=$flood)', () {
      final original = post(flood: flood);
      expect(view(original, null).sharedHistorySourceName, isNull);
      expect(view(original, extra).sharedHistorySourceName, 'Тук-тук');
      expect(view(original, other).sharedHistorySourceName, 'Тук-тук');
      expect(original.sharedHistorySourceName, isNull);
      expect(view(original, extra).sentByFlood, flood);
    });
  }
  test('additional source is hidden in its own chat without changing the cache', () {
    final original = post(id: 'identity:$extra:1', key: extra, name: 'JustNS');
    expect(view(original, extra).sharedHistorySourceName, isNull);
    expect(view(original, null).sharedHistorySourceName, 'JustNS');
    expect(view(original, other).sharedHistorySourceName, 'JustNS');
    expect(original.sharedHistorySourceName, 'JustNS');
    expect(original.copyWith(text: 'Updated').sharedHistorySourceKey, extra);
    expect(original.copyWith(sharedHistorySourceKey: null).sharedHistorySourceKey, isNull);
  });
  test('equal names and matching prefixes do not collapse distinct full keys', () {
    final different = '${extra.substring(0, 62)}01';
    final original = post(key: extra, name: 'Same name');
    expect(view(original, different).sharedHistorySourceName, 'Same name');
    expect(view(original, extra).sharedHistorySourceName, isNull);
  });
  test('historical node scopes are compared by scope, not by display name', () {
    final original = post(key: SharedMessageHistoryHelper.scopeFor(extra), name: 'Same name');
    expect(view(original, extra).sharedHistorySourceName, isNull);
    expect(view(original, other).sharedHistorySourceName, 'Same name');
    expect(view(original, null).sharedHistorySourceName, 'Same name');
  });
  test('identity message ids support older projections without source keys', () {
    final original = post(id: 'identity:$extra:1', name: 'JustNS');
    expect(view(original, extra).sharedHistorySourceName, isNull);
    expect(view(original, null).sharedHistorySourceName, 'JustNS');
  });
  test('legacy labels without a known identity are retained', () {
    final original = post(name: 'Archived node');
    expect(identical(view(original, extra), original), isTrue);
    expect(view(original, null).sharedHistorySourceName, 'Archived node');
  });
}
