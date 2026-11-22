import 'dart:typed_data';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/storage/message_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/bookmarked_message.dart';
import 'package:meshcore_open/storage/bookmark_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/history_test_environment.dart';

BookmarkedMessage _bookmark(String id, {String text = 'saved text'}) => BookmarkedMessage(
  sourceType: BookmarkSourceType.contact, sourceId: 'ab' * 32,
  sourceName: 'Alice', messageId: id, senderName: 'Alice', text: text,
  timestamp: DateTime(2026), receivedAt: DateTime(2026), isOutgoing: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('preferences fallback', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      PrefsManager.reset();
      await PrefsManager.initialize();
    });
    tearDown(PrefsManager.reset);

    test('queued writes retain both snapshots', () async {
      final store = BookmarkStore()..setPublicKeyHex = 'aa' * 32;
      await Future.wait([store.saveBookmark(_bookmark('one')), store.saveBookmark(_bookmark('two'))]);
      expect((await store.loadBookmarks()).map((row) => row.messageId), ['one', 'two']);
      final reborn = BookmarkStore()..setPublicKeyHex = 'aa' * 32;
      expect(await reborn.loadBookmarks(), hasLength(2));
    });
  });

  group('SQLite', () {
    final environment = HistoryTestEnvironment();
    setUp(environment.setUp);
    tearDown(environment.tearDown);

    test('independent writers upsert rows without replacing the bookmark list', () async {
      final first = BookmarkStore()..setPublicKeyHex = 'aa' * 32;
      final second = BookmarkStore()..setPublicKeyHex = 'aa' * 32;
      await Future.wait([first.saveBookmark(_bookmark('one')), second.saveBookmark(_bookmark('two'))]);
      final reborn = BookmarkStore()..setPublicKeyHex = 'aa' * 32;
      expect((await reborn.loadBookmarks()).map((row) => row.messageId), unorderedEquals(['one', 'two']));
      expect(PrefsManager.instance.getString(reborn.keyFor), isNull);
    });

    test('queued writes capture their node scope and removal is isolated', () async {
      final store = BookmarkStore()..setPublicKeyHex = 'aa' * 32;
      final oldWrite = store.saveBookmark(_bookmark('same', text: 'node A'));
      store.setPublicKeyHex = 'bb' * 32;
      final newWrite = store.saveBookmark(_bookmark('same', text: 'node B'));
      await Future.wait([oldWrite, newWrite]);
      expect((await store.loadBookmarks()).single.text, 'node B');
      await store.removeBookmark(_bookmark('same'));
      expect(await store.loadBookmarks(), isEmpty);
      store.setPublicKeyHex = 'aa' * 32;
      expect((await store.loadBookmarks()).single.text, 'node A');
    });

    test('identity message IDs keep recipients separate even for the same peer and row', () async {
      final store = BookmarkStore()..setPublicKeyHex = 'aa' * 32;
      final one = _bookmark('identity:${'11' * 32}:1');
      final two = _bookmark('identity:${'22' * 32}:1');
      await store.saveBookmark(one);
      expect(store.contains(two.sourceType, two.sourceId, two.messageId), isFalse);
      await store.saveBookmark(two);
      await store.removeBookmark(one);
      expect((await store.loadBookmarks()).single.messageId, two.messageId);
    });

    test('snapshots survive message deletion and are persisted independently', () async {
      final store = BookmarkStore()..setPublicKeyHex = 'aa' * 32;
      final messages = MessageStore()..setPublicKeyHex = 'aa' * 32;
      await messages.saveMessages('ab' * 32, [Message(senderKey: Uint8List(32),
        text: 'saved text', timestamp: DateTime(2026), isOutgoing: false, messageId: 'gone')]);
      await store.saveBookmark(_bookmark('gone'));
      await messages.clearMessages('ab' * 32);
      expect(await messages.loadMessages('ab' * 32), isEmpty);
      final reborn = BookmarkStore()..setPublicKeyHex = 'aa' * 32;
      expect((await reborn.loadBookmarks()).single.text, 'saved text');
      await reborn.removeBookmark(_bookmark('gone'));
      final again = BookmarkStore()..setPublicKeyHex = 'aa' * 32;
      expect(await again.loadBookmarks(), isEmpty);
    });
  });
}
