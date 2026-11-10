import 'dart:convert';

import 'package:drift/drift.dart';

import '../services/backup_file_codec.dart';
import 'message_history_database.dart';

extension MessageHistoryBackupSnapshot on MessageHistoryDatabase {
  /// Captures both selected histories from one SQLite read transaction.
  Future<Map<String, List<String>>> snapshotBackupMessages({
    required String scope,
    required bool includeDirect,
    required Map<String, List<String>> channelKeys,
    required bool Function() stillCurrent,
  }) => _readSnapshot(() async {
    final result = <String, List<String>>{};
    final primaryKeys = {for (final keys in channelKeys.values) keys.first};
    final destinationKeys = {
      for (final channel in channelKeys.entries)
        for (final key in channel.value) key: channel.key,
    };
    final channelRows = <String, Map<String, String>>{};
    final directPrefix = 'messages_$scope';
    final directKey = RegExp('^${directPrefix}[0-9a-f]{64}\$');
    var bytes = 0;

    void checkDestination() {
      if (!stillCurrent()) throw StateError('Backup history source changed');
    }

    Future<void> read(
      int kind,
      String filter,
      List<Variable<String>> parameters,
    ) async {
      var afterKey = '';
      var afterId = '';
      while (true) {
        checkDestination();
        final page = await customSelect(
          '''
SELECT storage_key, message_id, message_json
FROM history_messages
WHERE kind = ? AND $filter AND (storage_key, message_id) > (?, ?)
ORDER BY storage_key, message_id
LIMIT 128
''',
          variables: [
            Variable<int>(kind),
            ...parameters,
            Variable<String>(afterKey),
            Variable<String>(afterId),
          ],
          readsFrom: {historyMessages},
        ).get();
        if (page.isEmpty) return;
        afterKey = page.last.read<String>('storage_key');
        afterId = page.last.read<String>('message_id');
        for (final row in page) {
          final key = row.read<String>('storage_key');
          if (kind == 0 && !directKey.hasMatch(key)) continue;
          final json = row.read<String>('message_json');
          if (kind == 0) {
            (result[key] ??= []).add(json);
          } else {
            final messages = channelRows[destinationKeys[key]!] ??= {};
            final id = row.read<String>('message_id');
            if (messages[id] case final previous?) {
              if (!primaryKeys.contains(key)) continue;
              bytes -= utf8.encode(previous).length;
            }
            messages[id] = json;
          }
          bytes += utf8.encode(json).length;
          if (bytes > backupMaxJsonBytes) throw const BackupFileTooLarge();
        }
      }
    }

    if (includeDirect) {
      await read(
        0,
        'storage_key >= ? AND storage_key < ?',
        [Variable(directPrefix), Variable('${directPrefix}g')],
      );
    }
    final keys = destinationKeys.keys.toList();
    for (var start = 0; start < keys.length; start += 200) {
      final chunk = keys.skip(start).take(200).toList();
      final placeholders = List.filled(chunk.length, '?').join(', ');
      await read(
        1,
        'storage_key IN ($placeholders)',
        [for (final key in chunk) Variable(key)],
      );
    }
    for (final channel in channelRows.entries) {
      result[channel.key] = channel.value.values.toList();
    }
    checkDestination();
    return result;
  });

  Future<T> _readSnapshot<T>(Future<T> Function() read) => exclusively(() async {
    // Drift starts ordinary transactions with BEGIN IMMEDIATE, which takes
    // the WAL writer lock even when all of the statements are reads.
    await customStatement('BEGIN DEFERRED');
    try {
      return await read();
    } finally {
      // No writes are made. End the read transaction before releasing the
      // executor, including when the source changes or the size check fails.
      await customStatement('ROLLBACK');
    }
  });
}
