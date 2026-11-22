import 'dart:convert';

import '../models/bookmarked_message.dart';
import '../utils/app_logger.dart';
import 'message_history_storage.dart';
import 'prefs_manager.dart';

/// Bookmark snapshots survive removal/eviction of the original chat message.
class BookmarkStore {
  String _publicKeyHex = '';
  String get publicKeyHex => _publicKeyHex;
  set setPublicKeyHex(String value) {
    final next = value.length >= 10 ? value.substring(0, 10) : '';
    if (next != _publicKeyHex) {
      _publicKeyHex = next;
      _cache.removeWhere((scope, _) => scope != next);
    }
  }
  String get keyFor => 'message_bookmarks_$publicKeyHex';
  final _cache = <String, Map<String, BookmarkedMessage>>{};
  final _writes = <String, Future<void>>{};

  bool contains(BookmarkSourceType type, String source, String id) =>
      _cache[publicKeyHex]?.containsKey(BookmarkedMessage.storageIdFor(type, source, id)) ?? false;

  Future<Map<String, BookmarkedMessage>> _read(String scope) async {
    final existing = _cache[scope];
    if (existing != null) {
      return existing;
    }
    final history = MessageHistoryStorage.instance;
    final raw = history.hasDatabase
        ? await history.readMessageBookmarks(scope)
        : <String>[];
    if (!history.hasDatabase) {
      final value = PrefsManager.instance.getString('message_bookmarks_$scope');
      if (value != null) {
        try { raw.addAll((jsonDecode(value) as List).map(jsonEncode)); }
        on Object catch (error) { appLogger.warn('Unreadable bookmarks: $error'); }
      }
    }
    final result = <String, BookmarkedMessage>{};
    for (final value in raw) {
      try {
        final bookmark = BookmarkedMessage.fromJson(jsonDecode(value) as Map<String, dynamic>);
        result[bookmark.storageId] = bookmark;
      } on Object catch (error) { appLogger.warn('Skipping malformed bookmark: $error'); }
    }
    return scope == publicKeyHex ? _cache.putIfAbsent(scope, () => result) : result;
  }

  Future<List<BookmarkedMessage>> loadBookmarks() async {
    final scope = publicKeyHex;
    if (scope.isEmpty) {
      return [];
    }
    final writes = _writes[scope];
    if (writes != null) {
      await writes;
    }
    return (await _read(scope)).values.toList();
  }

  Future<void> saveBookmark(BookmarkedMessage bookmark) => _change(bookmark, true);
  Future<void> removeBookmark(BookmarkedMessage bookmark) => _change(bookmark, false);

  Future<void> _change(BookmarkedMessage bookmark, bool save) {
    final scope = publicKeyHex;
    if (scope.isEmpty) {
      return Future.value();
    }
    Future<void> write() async {
      final entries = await _read(scope);
      final history = MessageHistoryStorage.instance;
      if (history.hasDatabase) {
        if (save) {
          await history.writeMessageBookmark(scope, bookmark.storageId,
              bookmark.receivedAt.millisecondsSinceEpoch, jsonEncode(bookmark.toJson()));
        } else {
          await history.removeMessageBookmark(scope, bookmark.storageId);
        }
      } else {
        final next = {...entries};
        if (save) { next[bookmark.storageId] = bookmark; }
        else { next.remove(bookmark.storageId); }
        if (!await PrefsManager.instance.setString('message_bookmarks_$scope',
            jsonEncode(next.values.map((entry) => entry.toJson()).toList()))) {
          throw StateError('Could not save bookmarks');
        }
      }
      if (save) { entries[bookmark.storageId] = bookmark; }
      else { entries.remove(bookmark.storageId); }
    }
    final previous = _writes[scope];
    final next = previous == null ? write() : previous.then((_) => write());
    _writes[scope] = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}
