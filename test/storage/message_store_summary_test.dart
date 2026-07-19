import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/message_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/storage/shared_message_history_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const contactKey = 'abcdef0123456789';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  test(
    'message summary includes text from the latest non-CLI message',
    () async {
      final store = MessageStore()..setPublicKeyHex = '00112233445566778899';
      await PrefsManager.instance.setString(
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
    await PrefsManager.instance.setString(
      'messages_1111111111$contactKey',
      jsonEncode([
        {'text': 'secondary older', 'timestamp': 1000, 'isCli': false},
      ]),
    );
    await PrefsManager.instance.setString(
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
}
