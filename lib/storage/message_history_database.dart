import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../helpers/message_text_codec.dart';

part 'message_history_database.g.dart';

@TableIndex(
  name: 'history_message_timeline',
  columns: {#kind, #storageKey, #timelineAtMs, #messageId},
)
@TableIndex(
  name: 'history_message_identity',
  columns: {#kind, #storageKey, #messageId},
  unique: true,
)
@TableIndex(
  name: 'history_message_summary',
  columns: {#kind, #storageKey, #isCli, #timelineAtMs, #messageId},
)
@TableIndex(
  name: 'history_message_marker',
  columns: {#kind, #storageKey, #containsMarker},
)
class HistoryMessages extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get kind => integer()();

  TextColumn get storageKey => text()();

  TextColumn get messageId => text()();

  TextColumn get packetHash => text().nullable()();

  IntColumn get timelineAtMs => integer()();

  IntColumn get timestampMs => integer()();

  IntColumn get receivedAtMs => integer().nullable()();

  TextColumn get senderKey => text().nullable()();

  TextColumn get senderName => text().nullable()();

  BoolColumn get isOutgoing => boolean()();

  BoolColumn get isCli => boolean().withDefault(const Constant(false))();

  IntColumn get status => integer()();

  TextColumn get rawText => text()();

  BlobColumn get rawPayload => blob().nullable()();

  TextColumn get searchText => text()();

  BoolColumn get containsMarker =>
      boolean().withDefault(const Constant(false))();

  TextColumn get messageJson => text()();
}

class HistoryMetadata extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class MessageHistoryCursor {
  const MessageHistoryCursor({
    required this.timelineAtMs,
    required this.messageId,
  });

  final int timelineAtMs;
  final String messageId;
}

class MessageHistorySummaryRow {
  const MessageHistorySummaryRow({
    required this.messageCount,
    required this.latestTimestampMs,
    required this.latestRawText,
  });

  final int messageCount;
  final int latestTimestampMs;
  final String latestRawText;
}

class LegacyMessageHistoryEntry {
  const LegacyMessageHistoryEntry({
    required this.kind,
    required this.storageKey,
    required this.jsonValue,
  });

  final int kind;
  final String storageKey;
  final String? jsonValue;
}

typedef LegacyMessageValidator =
    void Function(int kind, Map<String, dynamic> message);

class LegacyMessageHistoryProgress {
  const LegacyMessageHistoryProgress({
    required this.completedHistories,
    required this.totalHistories,
    required this.processedMessages,
    this.skippedHistories = 0,
    this.skippedMessages = 0,
  });

  final int completedHistories;
  final int totalHistories;
  final int processedMessages;
  final int skippedHistories;
  final int skippedMessages;
}

class LegacyMessageMigrationWarning {
  const LegacyMessageMigrationWarning({
    required this.skippedHistories,
    required this.skippedMessages,
  });

  final int skippedHistories;
  final int skippedMessages;
}

class MessageHistoryState {
  const MessageHistoryState({
    required this.hasMessages,
    required this.containsMarker,
  });

  final bool hasMessages;
  final bool containsMarker;
}

@DriftDatabase(tables: [HistoryMessages, HistoryMetadata])
class MessageHistoryDatabase extends _$MessageHistoryDatabase {
  static const String _legacyMigrationKey = 'legacy_migration_complete';
  static const String _legacySkippedHistoriesKey =
      'legacy_migration_skipped_histories';
  static const String _legacySkippedMessagesKey =
      'legacy_migration_skipped_messages';
  static const String _legacyWarningPendingKey =
      'legacy_migration_warning_pending';

  MessageHistoryDatabase()
    : super(
        driftDatabase(
          name: 'message_history',
          native: DriftNativeOptions(
            databaseDirectory: getApplicationSupportDirectory,
          ),
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );

  @override
  int get schemaVersion => 1;

  Future<bool> isLegacyMigrationComplete() async {
    final row = await (select(
      historyMetadata,
    )..where((row) => row.key.equals(_legacyMigrationKey))).getSingleOrNull();
    return row?.value == '1';
  }

  Future<void> markLegacyMigrationComplete() async {
    await into(historyMetadata).insertOnConflictUpdate(
      HistoryMetadataCompanion.insert(key: _legacyMigrationKey, value: '1'),
    );
  }

  Future<LegacyMessageMigrationWarning?> pendingLegacyMigrationWarning() async {
    final values = await _metadataValues({
      _legacyWarningPendingKey,
      _legacySkippedHistoriesKey,
      _legacySkippedMessagesKey,
    });
    if (values[_legacyWarningPendingKey] != '1') return null;
    return LegacyMessageMigrationWarning(
      skippedHistories:
          int.tryParse(values[_legacySkippedHistoriesKey] ?? '') ?? 0,
      skippedMessages:
          int.tryParse(values[_legacySkippedMessagesKey] ?? '') ?? 0,
    );
  }

  Future<void> acknowledgeLegacyMigrationWarning() async {
    await into(historyMetadata).insertOnConflictUpdate(
      HistoryMetadataCompanion.insert(
        key: _legacyWarningPendingKey,
        value: '0',
      ),
    );
  }

  Future<Map<String, String>> _metadataValues(Set<String> keys) async {
    final query = select(historyMetadata)..where((row) => row.key.isIn(keys));
    return {for (final row in await query.get()) row.key: row.value};
  }

  Future<Set<String>> storageKeys(int kind) async {
    final query = selectOnly(historyMessages, distinct: true)
      ..addColumns([historyMessages.storageKey])
      ..where(historyMessages.kind.equals(kind));
    return (await query.get())
        .map((row) => row.read(historyMessages.storageKey)!)
        .toSet();
  }

  Future<Set<String>> markerStorageKeys(int kind) async {
    final query = selectOnly(historyMessages, distinct: true)
      ..addColumns([historyMessages.storageKey])
      ..where(
        historyMessages.kind.equals(kind) &
            historyMessages.containsMarker.equals(true),
      );
    return (await query.get())
        .map((row) => row.read(historyMessages.storageKey)!)
        .toSet();
  }

  Future<List<String>> readMessageJson(int kind, String storageKey) async {
    final query = select(historyMessages)
      ..where(
        (row) => row.kind.equals(kind) & row.storageKey.equals(storageKey),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.timelineAtMs),
        (row) => OrderingTerm.asc(row.messageId),
      ]);
    return (await query.get()).map((row) => row.messageJson).toList();
  }

  Future<List<String>> readLatestMessageJson(
    int kind,
    String storageKey, {
    required int limit,
  }) async {
    if (limit <= 0) return const [];
    final query = select(historyMessages)
      ..where(
        (row) => row.kind.equals(kind) & row.storageKey.equals(storageKey),
      )
      ..orderBy([
        (row) => OrderingTerm.desc(row.timelineAtMs),
        (row) => OrderingTerm.desc(row.messageId),
      ])
      ..limit(limit);
    return (await query.get()).reversed.map((row) => row.messageJson).toList();
  }

  Future<List<String>> readMessageJsonBefore(
    int kind,
    String storageKey, {
    required MessageHistoryCursor cursor,
    required int limit,
  }) async {
    if (limit <= 0) return const [];
    final query = select(historyMessages)
      ..where(
        (row) =>
            row.kind.equals(kind) &
            row.storageKey.equals(storageKey) &
            (row.timelineAtMs.isSmallerThanValue(cursor.timelineAtMs) |
                (row.timelineAtMs.equals(cursor.timelineAtMs) &
                    row.messageId.isSmallerThanValue(cursor.messageId))),
      )
      ..orderBy([
        (row) => OrderingTerm.desc(row.timelineAtMs),
        (row) => OrderingTerm.desc(row.messageId),
      ])
      ..limit(limit);
    return (await query.get()).reversed.map((row) => row.messageJson).toList();
  }

  Future<List<String>> readMessageJsonAfter(
    int kind,
    String storageKey, {
    required MessageHistoryCursor cursor,
    required int limit,
  }) async {
    if (limit <= 0) return const [];
    final query = select(historyMessages)
      ..where(
        (row) =>
            row.kind.equals(kind) &
            row.storageKey.equals(storageKey) &
            (row.timelineAtMs.isBiggerThanValue(cursor.timelineAtMs) |
                (row.timelineAtMs.equals(cursor.timelineAtMs) &
                    row.messageId.isBiggerThanValue(cursor.messageId))),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.timelineAtMs),
        (row) => OrderingTerm.asc(row.messageId),
      ])
      ..limit(limit);
    return (await query.get()).map((row) => row.messageJson).toList();
  }

  Future<List<String>> searchMessageJson(
    int kind,
    String storageKey,
    String normalizedQuery,
  ) async {
    final query = select(historyMessages)
      ..where(
        (row) =>
            row.kind.equals(kind) &
            row.storageKey.equals(storageKey) &
            row.searchText.contains(normalizedQuery),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.timelineAtMs),
        (row) => OrderingTerm.asc(row.messageId),
      ]);
    return (await query.get()).map((row) => row.messageJson).toList();
  }

  Future<MessageHistorySummaryRow?> readDirectSummary(String storageKey) async {
    return (await readDirectSummaries([storageKey]))[storageKey];
  }

  Future<Map<String, MessageHistorySummaryRow>> readDirectSummaries(
    Iterable<String> storageKeys,
  ) async {
    final keys = storageKeys.toSet().toList(growable: false);
    if (keys.isEmpty) return const {};

    final result = <String, MessageHistorySummaryRow>{};
    const chunkSize = 400;
    for (var offset = 0; offset < keys.length; offset += chunkSize) {
      final end = offset + chunkSize < keys.length
          ? offset + chunkSize
          : keys.length;
      final chunk = keys.sublist(offset, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final query = customSelect(
        '''
SELECT grouped.storage_key,
       grouped.message_count,
       latest.timeline_at_ms AS latest_timestamp_ms,
       latest.raw_text AS latest_raw_text
FROM (
  SELECT storage_key, COUNT(*) AS message_count
  FROM history_messages
  WHERE kind = 0
    AND is_cli = 0
    AND storage_key IN ($placeholders)
  GROUP BY storage_key
) AS grouped
JOIN history_messages AS latest
  ON latest.id = (
    SELECT candidate.id
    FROM history_messages AS candidate
    WHERE candidate.kind = 0
      AND candidate.is_cli = 0
      AND candidate.storage_key = grouped.storage_key
    ORDER BY candidate.timeline_at_ms DESC, candidate.message_id DESC
    LIMIT 1
  )
''',
        variables: [for (final key in chunk) Variable<String>(key)],
        readsFrom: {historyMessages},
      );
      for (final row in await query.get()) {
        result[row.read<String>('storage_key')] = MessageHistorySummaryRow(
          messageCount: row.read<int>('message_count'),
          latestTimestampMs: row.read<int>('latest_timestamp_ms'),
          latestRawText: row.read<String>('latest_raw_text'),
        );
      }
    }
    return result;
  }

  Future<bool> upsertMessages(
    int kind,
    String storageKey,
    List<Map<String, dynamic>> messages,
  ) async {
    if (messages.isEmpty) return false;
    final companions = _companionsFor(kind, storageKey, messages);
    await batch((batch) {
      batch.insertAllOnConflictUpdate(historyMessages, companions);
    });
    return companions.any((companion) => companion.containsMarker.value);
  }

  Future<bool> replaceMessages(
    int kind,
    String storageKey,
    List<Map<String, dynamic>> messages,
  ) async {
    var containsMarker = false;
    await transaction(() async {
      await removeHistory(kind, storageKey);
      if (messages.isEmpty) return;
      final companions = _companionsFor(kind, storageKey, messages);
      containsMarker = companions.any(
        (companion) => companion.containsMarker.value,
      );
      await batch((batch) {
        batch.insertAll(historyMessages, companions);
      });
    });
    return containsMarker;
  }

  Future<MessageHistoryState> deleteMessage(
    int kind,
    String storageKey,
    String messageId,
  ) async {
    await (delete(historyMessages)..where(
          (row) =>
              row.kind.equals(kind) &
              row.storageKey.equals(storageKey) &
              row.messageId.equals(messageId),
        ))
        .go();
    final state = await customSelect(
      '''
SELECT COUNT(*) AS message_count,
       COALESCE(MAX(CASE WHEN contains_marker THEN 1 ELSE 0 END), 0)
         AS contains_marker
FROM history_messages
WHERE kind = ? AND storage_key = ?
''',
      variables: [Variable<int>(kind), Variable<String>(storageKey)],
      readsFrom: {historyMessages},
    ).getSingle();
    return MessageHistoryState(
      hasMessages: state.read<int>('message_count') > 0,
      containsMarker: state.read<int>('contains_marker') != 0,
    );
  }

  Future<void> importLegacyHistories(
    List<LegacyMessageHistoryEntry> histories, {
    void Function(LegacyMessageHistoryProgress progress)? onProgress,
    LegacyMessageValidator? validateMessage,
    int chunkSize = 200,
  }) async {
    if (chunkSize <= 0) throw ArgumentError.value(chunkSize, 'chunkSize');
    var processedMessages = 0;
    var skippedHistories = 0;
    var skippedMessages = 0;
    await transaction(() async {
      for (
        var historyIndex = 0;
        historyIndex < histories.length;
        historyIndex++
      ) {
        final history = histories[historyIndex];
        late final List<dynamic> decoded;
        try {
          final value = history.jsonValue;
          final parsed = value == null ? null : jsonDecode(value);
          if (parsed is! List<dynamic>) {
            throw const FormatException('History entry is not a JSON array');
          }
          decoded = parsed;
        } catch (error, stackTrace) {
          if (_isFatalLegacyDataError(error)) rethrow;
          skippedHistories++;
          _logSkippedLegacyData(history.storageKey, null, error, stackTrace);
          onProgress?.call(
            LegacyMessageHistoryProgress(
              completedHistories: historyIndex + 1,
              totalHistories: histories.length,
              processedMessages: processedMessages,
              skippedHistories: skippedHistories,
              skippedMessages: skippedMessages,
            ),
          );
          await Future<void>.delayed(Duration.zero);
          continue;
        }
        final fallbackOccurrences = <String, int>{};
        for (var offset = 0; offset < decoded.length; offset += chunkSize) {
          final end = offset + chunkSize < decoded.length
              ? offset + chunkSize
              : decoded.length;
          final messages = <Map<String, dynamic>>[];
          final companions = <HistoryMessagesCompanion>[];
          for (var index = offset; index < end; index++) {
            final entry = decoded[index];
            try {
              if (entry is! Map<String, dynamic>) {
                throw const FormatException('History message is not an object');
              }
              final message = Map<String, dynamic>.from(entry);
              validateMessage?.call(history.kind, message);
              companions.addAll(
                _companionsFor(
                  history.kind,
                  history.storageKey,
                  [message],
                  fallbackOccurrences: fallbackOccurrences,
                ),
              );
              messages.add(message);
            } catch (error, stackTrace) {
              if (_isFatalLegacyDataError(error)) rethrow;
              skippedMessages++;
              _logSkippedLegacyData(
                history.storageKey,
                index,
                error,
                stackTrace,
              );
            }
          }
          if (companions.isNotEmpty) {
            await batch((batch) {
              batch.insertAll(historyMessages, companions);
            });
          }
          processedMessages += messages.length;
          onProgress?.call(
            LegacyMessageHistoryProgress(
              completedHistories: historyIndex,
              totalHistories: histories.length,
              processedMessages: processedMessages,
              skippedHistories: skippedHistories,
              skippedMessages: skippedMessages,
            ),
          );
          await Future<void>.delayed(Duration.zero);
        }
        onProgress?.call(
          LegacyMessageHistoryProgress(
            completedHistories: historyIndex + 1,
            totalHistories: histories.length,
            processedMessages: processedMessages,
            skippedHistories: skippedHistories,
            skippedMessages: skippedMessages,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
      await _storeLegacyMigrationOutcome(
        skippedHistories: skippedHistories,
        skippedMessages: skippedMessages,
      );
      await markLegacyMigrationComplete();
    });
  }

  Future<void> _storeLegacyMigrationOutcome({
    required int skippedHistories,
    required int skippedMessages,
  }) async {
    final hasSkipped = skippedHistories > 0 || skippedMessages > 0;
    await batch((batch) {
      batch.insertAllOnConflictUpdate(historyMetadata, [
        HistoryMetadataCompanion.insert(
          key: _legacySkippedHistoriesKey,
          value: '$skippedHistories',
        ),
        HistoryMetadataCompanion.insert(
          key: _legacySkippedMessagesKey,
          value: '$skippedMessages',
        ),
        HistoryMetadataCompanion.insert(
          key: _legacyWarningPendingKey,
          value: hasSkipped ? '1' : '0',
        ),
      ]);
    });
  }

  bool _isFatalLegacyDataError(Object error) {
    return error is OutOfMemoryError || error is StackOverflowError;
  }

  void _logSkippedLegacyData(
    String storageKey,
    int? messageIndex,
    Object error,
    StackTrace stackTrace,
  ) {
    final location = messageIndex == null
        ? storageKey
        : '$storageKey[$messageIndex]';
    developer.log(
      'Skipping invalid legacy message history entry $location: '
      '${error.runtimeType}: $error',
      name: 'MessageHistoryMigration',
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<void> removeHistory(int kind, String storageKey) async {
    await (delete(historyMessages)..where(
          (row) => row.kind.equals(kind) & row.storageKey.equals(storageKey),
        ))
        .go();
  }

  List<HistoryMessagesCompanion> _companionsFor(
    int kind,
    String storageKey,
    List<Map<String, dynamic>> messages, {
    Map<String, int>? fallbackOccurrences,
  }) {
    final occurrences = fallbackOccurrences ?? <String, int>{};
    return messages.map((message) {
      final messageId = _messageIdFor(message, occurrences);
      final timestamp = message['timestamp'] as int? ?? 0;
      final receivedAt = message['receivedAt'] as int?;
      final displayText = message['text'] as String? ?? '';
      final rawText = message['rawText'] as String? ?? displayText;
      final decodedText = message['rawText'] != null
          ? displayText
          : (MessageTextCodec.tryDecodeKnownCompression(rawText) ?? rawText);
      final senderName = message['senderName'] as String?;
      final timelineAt = kind == 1 || _hasRoomAuthorKey(message)
          ? receivedAt ?? timestamp
          : timestamp;
      final storedMessage = Map<String, dynamic>.from(message)
        ..['messageId'] = messageId;

      return HistoryMessagesCompanion.insert(
        kind: kind,
        storageKey: storageKey,
        messageId: messageId,
        packetHash: Value(message['packetHash'] as String?),
        timelineAtMs: timelineAt,
        timestampMs: timestamp,
        receivedAtMs: Value(receivedAt),
        senderKey: Value(message['senderKey'] as String?),
        senderName: Value(senderName),
        isOutgoing: message['isOutgoing'] as bool? ?? false,
        isCli: Value(message['isCli'] as bool? ?? false),
        status: message['status'] as int? ?? 0,
        rawText: rawText,
        rawPayload: Value(_decodePayload(message['rawPayload'])),
        searchText: '${senderName ?? ''} $decodedText'.trim().toLowerCase(),
        containsMarker: Value(
          rawText.contains('m:') || decodedText.contains('m:'),
        ),
        messageJson: jsonEncode(storedMessage),
      );
    }).toList();
  }

  bool _hasRoomAuthorKey(Map<String, dynamic> message) {
    final encoded = message['fourByteRoomContactKey'];
    if (encoded is! String || encoded.isEmpty) return false;
    try {
      return base64Decode(encoded).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Uint8List? _decodePayload(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return Uint8List.fromList(base64Decode(value));
    } catch (_) {
      return null;
    }
  }

  String _messageIdFor(
    Map<String, dynamic> message,
    Map<String, int> fallbackOccurrences,
  ) {
    final messageId = message['messageId'];
    final fallbackJson = jsonEncode({
      'timestamp': message['timestamp'],
      'receivedAt': message['receivedAt'],
      'senderKey': message['senderKey'],
      'senderName': message['senderName'],
      'isOutgoing': message['isOutgoing'],
      'isCli': message['isCli'],
      'text': message['text'],
    });
    final fallbackHash = sha256.convert(utf8.encode(fallbackJson));
    final baseId = messageId is String && messageId.isNotEmpty
        ? messageId
        : 'legacy_$fallbackHash';
    final occurrence = fallbackOccurrences.update(
      baseId,
      (value) => value + 1,
      ifAbsent: () => 0,
    );
    return occurrence == 0 ? baseId : '$baseId#$occurrence';
  }
}
