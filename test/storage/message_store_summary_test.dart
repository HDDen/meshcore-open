import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/message_store.dart';
import 'package:meshcore_open/storage/shared_message_history_helper.dart';

import '../support/history_test_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const contactKey =
      'abcdef0123456789abcdef0123456789'
      'abcdef0123456789abcdef0123456789';

  final environment = HistoryTestEnvironment();
  final history = MessageHistoryStorage.instance;
  setUp(environment.setUp);
  tearDown(environment.tearDown);

  test(
    'message summary includes text from the latest non-CLI message',
    () async {
      final store = MessageStore()..setPublicKeyHex = '00112233445566778899';
      await history.setString(
        MessageHistoryKind.direct,
        'messages_0011223344$contactKey',
        jsonEncode([
          {'text': 'older', 'timestamp': 1000, 'isCli': false},
          {'text': 'ignored CLI', 'timestamp': 3000, 'isCli': true},
          {'text': 'newest', 'timestamp': 2000, 'isCli': false},
        ]),
      );

      final summary = await store.loadMessageSummary(contactKey);

      expect(summary, isNotNull);
      expect(summary!.messageCount, 2);
      expect(summary.latestMessageAt.millisecondsSinceEpoch, 2000);
      expect(summary.latestMessageText, 'newest');
    },
  );

  test('shared summary keeps text paired with the newest timestamp', () async {
    await history.setString(
      MessageHistoryKind.direct,
      'messages_1111111111$contactKey',
      jsonEncode([
        {'text': 'secondary older', 'timestamp': 1000, 'isCli': false},
      ]),
    );
    await history.setString(
      MessageHistoryKind.direct,
      'messages_2222222222$contactKey',
      jsonEncode([
        {'text': 'secondary newest', 'timestamp': 2000, 'isCli': false},
      ]),
    );

    final summary = await SharedMessageHistoryHelper()
        .loadSecondaryContactMessageSummary(
          currentPublicKeyHex: '00000000000000000000',
          contactKeyHex: contactKey,
        );

    expect(summary, isNotNull);
    expect(summary!.messageCount, 2);
    expect(summary.latestMessageAt.millisecondsSinceEpoch, 2000);
    expect(summary.latestMessageText, 'secondary newest');
  });

  test('known scopes do not treat an unscoped contact key as a node', () async {
    const message = '[{"text":"synthetic","timestamp":1}]';
    await history.setString(
      MessageHistoryKind.direct,
      'messages_$contactKey',
      message,
    );
    await history.setString(
      MessageHistoryKind.direct,
      'messages_1111111111$contactKey',
      message,
    );

    expect(SharedMessageHistoryHelper.knownScopes(), {'1111111111'});
  });
}
