import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'message_history_database.dart';
import 'prefs_manager.dart';

enum MessageHistoryKind { direct, channel }

class MessageHistoryStorage {
  MessageHistoryStorage._();

  static final MessageHistoryStorage instance = MessageHistoryStorage._();

  static const String databaseFileName = 'message_history.sqlite';
  static const String _directPrefix = 'messages_';
  static const String _channelPrefix = 'channel_messages_';
  static final RegExp _directKeyPattern = RegExp(
    r'^messages_(?:[0-9a-fA-F]{10}(?:[0-9a-fA-F]{64})?|[0-9a-fA-F]{64})$',
  );
  static final RegExp _channelKeyPattern = RegExp(
    r'^channel_messages_(?:[0-9a-fA-F]{10}(?:\d+|name_[A-Za-z0-9_-]+)|\d+)$',
  );

  MessageHistoryDatabase? _database;
  final Map<MessageHistoryKind, Set<String>> _keys = {
    for (final kind in MessageHistoryKind.values) kind: <String>{},
  };
  final Set<String> _directMarkerKeys = {};
  LegacyMessageValidator? _legacyMessageValidator;
  final ValueNotifier<LegacyMessageHistoryProgress> migrationProgress =
      ValueNotifier(
        const LegacyMessageHistoryProgress(
          completedHistories: 0,
          totalHistories: 0,
          processedMessages: 0,
        ),
      );
  bool _initialized = false;

  Future<bool> initializeAndMigrate({
    Future<void> Function()? onMigrationStarted,
    LegacyMessageValidator? validateMessage,
  }) async {
    _legacyMessageValidator = validateMessage;
    if (_initialized) return false;

    if (kIsWeb) {
      final prefs = PrefsManager.instance;
      for (final key in prefs.getKeys()) {
        final kind = key.startsWith(_channelPrefix)
            ? MessageHistoryKind.channel
            : key.startsWith(_directPrefix)
            ? MessageHistoryKind.direct
            : null;
        if (kind == null) continue;
        _keys[kind]!.add(key);
        if (kind == MessageHistoryKind.direct &&
            (prefs.getString(key)?.contains('m:') ?? false)) {
          _directMarkerKeys.add(key);
        }
      }
      _initialized = true;
      return false;
    }

    final prefs = PrefsManager.instance;
    final directPreferenceKeys = prefs
        .getKeys()
        .where(_directKeyPattern.hasMatch)
        .toList();
    final channelPreferenceKeys = prefs
        .getKeys()
        .where(_channelKeyPattern.hasMatch)
        .toList();
    final hasPreferenceHistory =
        directPreferenceKeys.isNotEmpty || channelPreferenceKeys.isNotEmpty;

    final database = MessageHistoryDatabase();
    _database = database;
    try {
      final migrationComplete = await database.isLegacyMigrationComplete();
      var migrated = false;
      if (!migrationComplete && hasPreferenceHistory) {
        await onMigrationStarted?.call();
        final histories = _readPreferenceHistories(
          prefs,
          directPreferenceKeys,
          channelPreferenceKeys,
        );
        migrationProgress.value = LegacyMessageHistoryProgress(
          completedHistories: 0,
          totalHistories: histories.length,
          processedMessages: 0,
        );
        await database.importLegacyHistories(
          histories,
          onProgress: (progress) => migrationProgress.value = progress,
          validateMessage: validateMessage,
        );
        migrated = true;
      } else if (!migrationComplete) {
        await database.markLegacyMigrationComplete();
      }

      if (hasPreferenceHistory) {
        // The database transaction and its completion marker are committed
        // before cleanup. If cleanup is interrupted, the next launch safely
        // resumes these removals without importing the same messages twice.
        for (final key in [...directPreferenceKeys, ...channelPreferenceKeys]) {
          await prefs.remove(key);
        }
      }

      await _refreshCaches();
      _initialized = true;
      return migrated;
    } catch (_) {
      await database.close();
      _database = null;
      rethrow;
    }
  }

  List<LegacyMessageHistoryEntry> _readPreferenceHistories(
    SharedPreferences prefs,
    Iterable<String> directKeys,
    Iterable<String> channelKeys,
  ) {
    final entries = <LegacyMessageHistoryEntry>[];
    void append(Iterable<String> keys, MessageHistoryKind kind) {
      for (final key in keys) {
        final storedValue = prefs.get(key);
        final value = storedValue is String ? storedValue : null;
        entries.add(
          LegacyMessageHistoryEntry(
            kind: kind.index,
            storageKey: key,
            jsonValue: value,
            rawValue: storedValue is String
                ? storedValue
                : jsonEncode(storedValue),
          ),
        );
      }
    }

    append(directKeys, MessageHistoryKind.direct);
    append(channelKeys, MessageHistoryKind.channel);
    return entries;
  }

  Future<void> _refreshCaches() async {
    for (final kind in MessageHistoryKind.values) {
      _keys[kind]!
        ..clear()
        ..addAll(await _database!.storageKeys(kind.index));
    }
    _directMarkerKeys
      ..clear()
      ..addAll(
        await _database!.markerStorageKeys(MessageHistoryKind.direct.index),
      );
  }

  Future<void> restartAfterMigration() async {
    if (kIsWeb) return;
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    await _database?.close();
    await Process.start(
      Platform.resolvedExecutable,
      Platform.executableArguments,
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  Future<LegacyMessageMigrationWarning?> pendingMigrationWarning() async {
    _requireInitialized();
    if (kIsWeb) return null;
    return _database!.pendingLegacyMigrationWarning();
  }

  Future<void> acknowledgeMigrationWarning() async {
    _requireInitialized();
    if (kIsWeb) return;
    await _database!.acknowledgeLegacyMigrationWarning();
  }

  Future<List<LegacyRejectedRecord>> legacyRejectedRecords() async {
    _requireInitialized();
    if (kIsWeb) return const [];
    return _database!.legacyRejectedRecords();
  }

  Future<LegacyQuarantineRetryResult> retryLegacyRejected() async {
    _requireInitialized();
    if (kIsWeb) {
      return const LegacyQuarantineRetryResult(restored: 0, remaining: 0);
    }
    final result = await _database!.retryLegacyRejected(
      validateMessage: _legacyMessageValidator,
    );
    await _refreshCaches();
    return result;
  }

  Future<int> clearLegacyRejected() async {
    _requireInitialized();
    if (kIsWeb) return 0;
    return _database!.clearLegacyRejected();
  }

  Future<MessageHistoryDatabaseStats?> maintenanceStats() async {
    _requireInitialized();
    if (kIsWeb) return null;
    return _database!.maintenanceStats();
  }

  Future<void> incrementalVacuum({int pages = 512}) async {
    _requireInitialized();
    if (kIsWeb) return;
    await _database!.incrementalVacuum(pages: pages);
  }

  Future<void> fullVacuum() async {
    _requireInitialized();
    if (kIsWeb) return;
    await _database!.fullVacuum();
  }

  Future<String?> getString(MessageHistoryKind kind, String key) async {
    _requireInitialized();
    if (kIsWeb) return PrefsManager.instance.getString(key);
    final messages = await _database!.readMessageJson(kind.index, key);
    return messages.isEmpty ? null : '[${messages.join(',')}]';
  }

  Future<String?> getLatestString(
    MessageHistoryKind kind,
    String key, {
    required int limit,
  }) async {
    _requireInitialized();
    if (kIsWeb) {
      final value = PrefsManager.instance.getString(key);
      if (value == null) return null;
      final messages = _decodeMessageList(value, key);
      final start = messages.length > limit ? messages.length - limit : 0;
      return jsonEncode(messages.sublist(start));
    }
    final messages = await _database!.readLatestMessageJson(
      kind.index,
      key,
      limit: limit,
    );
    return messages.isEmpty ? null : '[${messages.join(',')}]';
  }

  Future<String?> getStringBefore(
    MessageHistoryKind kind,
    String key, {
    required int timelineAtMs,
    required String messageId,
    required int limit,
  }) async {
    _requireInitialized();
    if (kIsWeb) {
      final value = PrefsManager.instance.getString(key);
      if (value == null) return null;
      final messages = _decodeMessageList(value, key);
      final anchor = messages.indexWhere(
        (message) => message['messageId'] == messageId,
      );
      if (anchor <= 0) return null;
      final start = anchor > limit ? anchor - limit : 0;
      return jsonEncode(messages.sublist(start, anchor));
    }
    final messages = await _database!.readMessageJsonBefore(
      kind.index,
      key,
      cursor: MessageHistoryCursor(
        timelineAtMs: timelineAtMs,
        messageId: messageId,
      ),
      limit: limit,
    );
    return messages.isEmpty ? null : '[${messages.join(',')}]';
  }

  Future<String?> getStringAfter(
    MessageHistoryKind kind,
    String key, {
    required int timelineAtMs,
    required String messageId,
    required int limit,
  }) async {
    _requireInitialized();
    if (limit <= 0) return null;
    if (kIsWeb) {
      final value = PrefsManager.instance.getString(key);
      if (value == null) return null;
      final messages = _decodeMessageList(value, key);
      final anchor = messages.indexWhere(
        (message) => message['messageId'] == messageId,
      );
      if (anchor < 0 || anchor >= messages.length - 1) return null;
      final available = messages.length - anchor - 1;
      final count = available < limit ? available : limit;
      return jsonEncode(messages.sublist(anchor + 1, anchor + 1 + count));
    }
    final messages = await _database!.readMessageJsonAfter(
      kind.index,
      key,
      cursor: MessageHistoryCursor(
        timelineAtMs: timelineAtMs,
        messageId: messageId,
      ),
      limit: limit,
    );
    return messages.isEmpty ? null : '[${messages.join(',')}]';
  }

  Future<String?> searchString(
    MessageHistoryKind kind,
    String key,
    String normalizedQuery,
  ) async {
    _requireInitialized();
    if (normalizedQuery.isEmpty || kIsWeb) return getString(kind, key);
    final messages = await _database!.searchMessageJson(
      kind.index,
      key,
      normalizedQuery,
    );
    return messages.isEmpty ? null : '[${messages.join(',')}]';
  }

  Future<MessageHistorySummaryRow?> directSummary(String key) async {
    _requireInitialized();
    if (kIsWeb) return null;
    return _database!.readDirectSummary(key);
  }

  Future<Map<String, MessageHistorySummaryRow>> directSummaries(
    Iterable<String> keys,
  ) async {
    _requireInitialized();
    if (kIsWeb) return const {};
    return _database!.readDirectSummaries(keys);
  }

  Set<String> getKeys(MessageHistoryKind kind) {
    _requireInitialized();
    return Set.unmodifiable(_keys[kind]!);
  }

  bool mayContainMarker(String key) {
    _requireInitialized();
    return _directMarkerKeys.contains(key);
  }

  Future<void> setString(
    MessageHistoryKind kind,
    String key,
    String value,
  ) async {
    _requireInitialized();
    final messages = _decodeMessageList(value, key);
    if (messages.isEmpty) return;
    if (kIsWeb) {
      final existingValue = PrefsManager.instance.getString(key);
      final existing = existingValue == null
          ? <Map<String, dynamic>>[]
          : _decodeMessageList(existingValue, key);
      final indexes = <String, int>{};
      for (var index = 0; index < existing.length; index++) {
        final id = existing[index]['messageId'];
        if (id is String && id.isNotEmpty) indexes[id] = index;
      }
      for (final message in messages) {
        final id = message['messageId'];
        final index = id is String ? indexes[id] : null;
        if (index == null) {
          existing.add(message);
          if (id is String && id.isNotEmpty) indexes[id] = existing.length - 1;
        } else {
          existing[index] = message;
        }
      }
      final encoded = jsonEncode(existing);
      await PrefsManager.instance.setString(key, encoded);
      _keys[kind]!.add(key);
      if (kind == MessageHistoryKind.direct) {
        if (encoded.contains('m:')) {
          _directMarkerKeys.add(key);
        } else {
          _directMarkerKeys.remove(key);
        }
      }
      return;
    }
    final containsMarker = await _database!.upsertMessages(
      kind.index,
      key,
      messages,
    );
    _keys[kind]!.add(key);
    // Point upserts keep this cache add-only. A stale positive only causes one
    // harmless extra history read; replace/delete paths recompute it exactly.
    if (kind == MessageHistoryKind.direct && containsMarker) {
      _directMarkerKeys.add(key);
    }
  }

  Future<void> replaceString(
    MessageHistoryKind kind,
    String key,
    String value,
  ) async {
    _requireInitialized();
    final messages = _decodeMessageList(value, key);
    if (kIsWeb) {
      if (messages.isEmpty) {
        await remove(kind, key);
        return;
      }
      await PrefsManager.instance.setString(key, value);
    } else {
      final containsMarker = await _database!.replaceMessages(
        kind.index,
        key,
        messages,
      );
      if (kind == MessageHistoryKind.direct) {
        if (containsMarker) {
          _directMarkerKeys.add(key);
        } else {
          _directMarkerKeys.remove(key);
        }
      }
    }
    if (messages.isEmpty) {
      _keys[kind]!.remove(key);
      _directMarkerKeys.remove(key);
      return;
    }
    _keys[kind]!.add(key);
    if (kind == MessageHistoryKind.direct && kIsWeb) {
      final hasMarker = value.contains('m:');
      if (hasMarker) {
        _directMarkerKeys.add(key);
      } else {
        _directMarkerKeys.remove(key);
      }
    }
  }

  Future<void> deleteMessage(
    MessageHistoryKind kind,
    String key,
    String messageId,
  ) async {
    _requireInitialized();
    if (kIsWeb) {
      final value = PrefsManager.instance.getString(key);
      if (value == null) return;
      final messages = _decodeMessageList(value, key)
        ..removeWhere((message) => message['messageId'] == messageId);
      await replaceString(kind, key, jsonEncode(messages));
      return;
    }
    final state = await _database!.deleteMessage(kind.index, key, messageId);
    if (!state.hasMessages) {
      _keys[kind]!.remove(key);
    }
    if (kind == MessageHistoryKind.direct) {
      if (state.containsMarker) {
        _directMarkerKeys.add(key);
      } else {
        _directMarkerKeys.remove(key);
      }
    }
  }

  Future<void> remove(MessageHistoryKind kind, String key) async {
    _requireInitialized();
    if (kIsWeb) {
      await PrefsManager.instance.remove(key);
      _keys[kind]!.remove(key);
      if (kind == MessageHistoryKind.direct) {
        _directMarkerKeys.remove(key);
      }
      return;
    }
    await _database!.removeHistory(kind.index, key);
    _keys[kind]!.remove(key);
    if (kind == MessageHistoryKind.direct) {
      _directMarkerKeys.remove(key);
    }
  }

  void _requireInitialized() {
    if (!_initialized) {
      throw StateError('MessageHistoryStorage is not initialized.');
    }
  }

  List<Map<String, dynamic>> _decodeMessageList(String value, String key) {
    final decoded = jsonDecode(value);
    if (decoded is! List) {
      throw FormatException('History entry is not a JSON array: $key');
    }
    return decoded.map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw FormatException('History message is not an object: $key');
      }
      return Map<String, dynamic>.from(entry);
    }).toList();
  }
}
