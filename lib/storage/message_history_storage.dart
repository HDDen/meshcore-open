import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/wardrive_sample.dart';
import 'message_history_database.dart';
import 'prefs_manager.dart';

enum MessageHistoryKind { direct, channel }

class MessageHistoryStorage {
  MessageHistoryStorage._();

  static final MessageHistoryStorage instance = MessageHistoryStorage._();

  static const String databaseFileName = 'message_history.sqlite';
  static const String _discoveredContactsKey = 'discovered_contacts';
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
    // Tests hand in a database over an in-memory executor; production opens
    // the file in the application support directory.
    MessageHistoryDatabase Function()? databaseFactory,
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

    final database = databaseFactory?.call() ?? MessageHistoryDatabase();
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
      await _moveDiscoveredContacts(prefs, database);
      await _moveWardriveData(prefs, database);

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

  /// Moves the discovered-contacts list out of preferences, where it was one
  /// JSON array, into its table, one row per node. The key is removed only
  /// after the rows are committed, and rows already in the table win, so an
  /// import cut short runs again at the next launch without touching newer
  /// rows. A failure costs this launch the old list and leaves the key for
  /// the next one: a cache of heard nodes is not worth refusing to start.
  Future<void> _moveDiscoveredContacts(
    SharedPreferences prefs,
    MessageHistoryDatabase database,
  ) async {
    final value = prefs.get(_discoveredContactsKey);
    if (value == null) return;
    try {
      final decoded = value is String ? jsonDecode(value) : null;
      if (decoded is! List) {
        developer.log(
          'Discovered contacts in preferences are not a JSON array; '
          'left in place',
          name: 'MessageHistoryMigration',
        );
        return;
      }
      final rows = <String, String>{};
      var skipped = 0;
      for (final entry in decoded) {
        final key = _discoveredContactKey(entry);
        if (key == null) {
          skipped++;
          continue;
        }
        rows[key] = jsonEncode(entry);
      }
      await database.importDiscoveredContacts(rows);
      await prefs.remove(_discoveredContactsKey);
      developer.log(
        'Moved ${rows.length} discovered contacts into the database'
        '${skipped > 0 ? ', skipped $skipped without a readable key' : ''}',
        name: 'MessageHistoryMigration',
      );
    } catch (error, stackTrace) {
      developer.log(
        'Discovered contacts stay in preferences for now: $error',
        name: 'MessageHistoryMigration',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// The row key of a stored discovered contact: its public key as the
  /// lowercase hex `Contact.publicKeyHex` gives, or null when the entry has
  /// none, which the store could not have read either.
  static String? _discoveredContactKey(Object? entry) {
    if (entry is! Map) return null;
    final encoded = entry['publicKey'];
    if (encoded is! String) return null;
    final List<int> bytes;
    try {
      bytes = base64Decode(encoded);
    } on FormatException {
      return null;
    }
    if (bytes.length != 32) return null;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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

  Future<List<ContactLocationCacheRecord>> loadContactLocationCache() async {
    _requireInitialized();
    if (kIsWeb) return const [];
    return _database!.readContactLocationCache();
  }

  Future<void> upsertContactLocationCache(
    List<ContactLocationCacheUpsert> rows,
  ) async {
    _requireInitialized();
    if (kIsWeb || rows.isEmpty) return;
    await _database!.upsertContactLocationCache(rows);
  }

  Future<void> clearContactLocationEstimatesForKeys(
    Iterable<String> publicKeyHexes,
  ) async {
    _requireInitialized();
    if (kIsWeb) return;
    await _database!.clearContactLocationEstimatesForKeys(publicKeyHexes);
  }

  Future<void> insertHeardPackets(List<HeardPacketInsert> packets) async {
    _requireInitialized();
    if (kIsWeb || packets.isEmpty) return;
    await _database!.insertHeardPackets(packets);
  }

  Future<List<HeardPacketRecord>> latestHeardPackets({
    required int limit,
  }) async {
    _requireInitialized();
    if (kIsWeb) return const [];
    return _database!.readLatestHeardPackets(limit: limit);
  }

  static const String _wardriveSamplesKey = 'wardrive_samples_v1';
  static const String _wardriveSessionsKey = 'wardrive_sessions_v1';
  static const String _wardriveUploadsKey = 'wardrive_uploaded_samples_v1';

  /// How many wardrive samples and sessions the tables keep, the oldest
  /// going first. The preference form kept 3000 samples for the size of the
  /// preferences file; the database does not care about that.
  static const int wardriveSampleLimit = 6000;
  static const int wardriveSessionLimit = 200;

  /// Moves wardrive samples, sessions and upload records out of their
  /// preference keys into the tables, once. The three go in one transaction
  /// and the keys are removed only after it commits, so a move cut short runs
  /// again at the next launch with rows already there winning. An upload
  /// record is carried over only for a sample that is carried over: a record
  /// about a sample that is gone is of no use. A failure leaves the keys for
  /// the next launch; this launch then sees empty tables, as the discovered
  /// contacts do in the same case.
  Future<void> _moveWardriveData(
    SharedPreferences prefs,
    MessageHistoryDatabase database,
  ) async {
    final rawSamples = prefs.getStringList(_wardriveSamplesKey);
    final rawSessions = prefs.getStringList(_wardriveSessionsKey);
    final rawUploads = prefs.getString(_wardriveUploadsKey);
    if (rawSamples == null && rawSessions == null && rawUploads == null) {
      return;
    }
    try {
      var skipped = 0;
      final samples = <WardriveSampleRow>[];
      for (final raw in rawSamples ?? const <String>[]) {
        final sample = _decodeWardriveSample(raw);
        if (sample == null) {
          skipped++;
          continue;
        }
        samples.add((
          id: sample.id,
          timestampMs: sample.timestamp.millisecondsSinceEpoch,
          publicKeyHex: sample.publicKeyHex,
          pingSuccess: sample.pingSuccess,
          sampleJson: jsonEncode(sample.toStorageJson()),
        ));
      }
      final sessions = <({int startTimeMs, String sessionJson})>[];
      for (final raw in rawSessions ?? const <String>[]) {
        final session = _decodeWardriveSession(raw);
        if (session == null) {
          skipped++;
          continue;
        }
        sessions.add((
          startTimeMs: session.startTime.millisecondsSinceEpoch,
          sessionJson: jsonEncode(session.toJson()),
        ));
      }
      final uploads = <({String sampleId, String endpointUrl})>[];
      if (rawUploads != null && rawUploads.isNotEmpty) {
        final decoded = jsonDecode(rawUploads);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final ids = entry.value;
            if (ids is! List) continue;
            for (final id in ids) {
              uploads.add((
                sampleId: id.toString(),
                endpointUrl: entry.key.toString(),
              ));
            }
          }
        }
      }
      await database.importWardriveData(
        samples: samples,
        sessions: sessions,
        uploads: uploads,
        sampleCap: wardriveSampleLimit,
        sessionCap: wardriveSessionLimit,
        uploadedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.remove(_wardriveSamplesKey);
      await prefs.remove(_wardriveSessionsKey);
      await prefs.remove(_wardriveUploadsKey);
      developer.log(
        'Moved ${samples.length} wardrive samples, ${sessions.length} sessions '
        'and ${uploads.length} upload records into the database'
        '${skipped > 0 ? ', skipped $skipped unreadable rows' : ''}',
        name: 'MessageHistoryMigration',
      );
    } catch (error, stackTrace) {
      developer.log(
        'Wardrive data stays in preferences for now: $error',
        name: 'MessageHistoryMigration',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static WardriveSample? _decodeWardriveSample(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return WardriveSample.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  static WardriveSession? _decodeWardriveSession(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return WardriveSession.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<bool> insertWardriveSample(
    WardriveSampleRow row, {
    required int cap,
  }) {
    _requireInitialized();
    return _database!.insertWardriveSample(row, cap: cap);
  }

  Future<int> importWardriveSamples(
    List<WardriveSampleRow> rows, {
    required int cap,
  }) {
    _requireInitialized();
    return _database!.importWardriveSamples(rows, cap: cap);
  }

  Future<List<String>> readWardriveSamples({
    required int limit,
    int offset = 0,
  }) {
    _requireInitialized();
    return _database!.readWardriveSamples(limit: limit, offset: offset);
  }

  Future<int> countWardriveSamples() {
    _requireInitialized();
    return _database!.countWardriveSamples();
  }

  Future<void> deleteWardriveSamples(List<String> ids) {
    _requireInitialized();
    return _database!.deleteWardriveSamples(ids);
  }

  Future<void> clearWardriveData() {
    _requireInitialized();
    return _database!.clearWardriveData();
  }

  Future<void> insertWardriveSession({
    required int startTimeMs,
    required String sessionJson,
    required int cap,
  }) {
    _requireInitialized();
    return _database!.insertWardriveSession(
      startTimeMs: startTimeMs,
      sessionJson: sessionJson,
      cap: cap,
    );
  }

  Future<List<String>> readWardriveSessions() {
    _requireInitialized();
    return _database!.readWardriveSessions();
  }

  Future<void> markWardriveUploaded({
    required String endpointUrl,
    required Iterable<String> sampleIds,
  }) {
    _requireInitialized();
    return _database!.markWardriveUploaded(
      endpointUrl: endpointUrl,
      sampleIds: sampleIds,
      uploadedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<List<String>> readWardrivePendingUploads({
    required String endpointUrl,
    required bool includeUploaded,
    required int limit,
    required int offset,
  }) {
    _requireInitialized();
    return _database!.readWardrivePendingUploads(
      endpointUrl: endpointUrl,
      includeUploaded: includeUploaded,
      limit: limit,
      offset: offset,
    );
  }

  /// Closes the database and forgets every cache, for a test that
  /// initialises the storage more than once in one process.
  Future<void> resetForTesting() async {
    await _database?.close();
    _database = null;
    for (final keys in _keys.values) {
      keys.clear();
    }
    _directMarkerKeys.clear();
    _initialized = false;
  }

  /// Whether the database is open: false on the web, which never creates it,
  /// and in a process that has not initialised the storage, such as a unit
  /// test.
  bool get hasDatabase => _initialized && _database != null;

  Future<List<String>> loadDiscoveredContacts() async {
    _requireInitialized();
    if (kIsWeb) return const [];
    return _database!.readDiscoveredContacts();
  }

  Future<void> writeDiscoveredContacts({
    required Map<String, String> upserts,
    required List<String> deleteKeys,
  }) async {
    _requireInitialized();
    if (kIsWeb) return;
    await _database!.writeDiscoveredContacts(
      upserts: upserts,
      deleteKeys: deleteKeys,
    );
  }

  Future<Map<String, String>> loadContactSettings(
    String nodeKey,
    String name,
  ) async {
    _requireInitialized();
    if (kIsWeb) return const {};
    return _database!.readContactSettings(nodeKey, name);
  }

  Future<void> saveContactSetting({
    required String nodeKey,
    required String contactKey,
    required String name,
    required String value,
  }) async {
    _requireInitialized();
    if (kIsWeb) return;
    await _database!.upsertContactSetting(
      nodeKey: nodeKey,
      contactKey: contactKey,
      name: name,
      value: value,
    );
  }

  Future<void> deleteContactSetting({
    required String nodeKey,
    required String contactKey,
    required String name,
  }) async {
    _requireInitialized();
    if (kIsWeb) return;
    await _database!.deleteContactSetting(
      nodeKey: nodeKey,
      contactKey: contactKey,
      name: name,
    );
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
