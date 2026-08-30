import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'message_history_database.dart';
import 'message_history_storage.dart';

class MessageHistoryMaintenanceSnapshot {
  const MessageHistoryMaintenanceSnapshot({
    required this.databasePath,
    required this.databaseBytes,
    required this.stats,
  });

  final String databasePath;
  final int databaseBytes;
  final MessageHistoryDatabaseStats stats;
}

class MessageHistoryMaintenance {
  MessageHistoryMaintenance({MessageHistoryStorage? storage})
    : _storage = storage ?? MessageHistoryStorage.instance;

  final MessageHistoryStorage _storage;

  Future<String> databasePath() async {
    final directory = await getApplicationSupportDirectory();
    return '${directory.path}${Platform.pathSeparator}'
        '${MessageHistoryStorage.databaseFileName}';
  }

  Future<MessageHistoryMaintenanceSnapshot?> snapshot() async {
    final stats = await _storage.maintenanceStats();
    if (stats == null) return null;
    final path = await databasePath();
    final file = File(path);
    final size = await file.exists() ? await file.length() : 0;
    return MessageHistoryMaintenanceSnapshot(
      databasePath: path,
      databaseBytes: size,
      stats: stats,
    );
  }

  Future<LegacyQuarantineRetryResult> retryRejected() {
    return _storage.retryLegacyRejected();
  }

  Future<int> clearRejected() => _storage.clearLegacyRejected();

  Future<String> diagnosticReport() async {
    final records = await _storage.legacyRejectedRecords();
    final package = await PackageInfo.fromPlatform();
    final payload = <String, Object?>{
      'format': 'mco-message-history-migration-diagnostic',
      'version': 1,
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'application': {
        'name': package.appName,
        'version': package.version,
        'build': package.buildNumber,
      },
      'databaseSchema': MessageHistoryDatabase.currentSchemaVersion,
      'rejectedCount': records.length,
      'entries': records
          .map(
            (record) => {
              'kind': _kindName(record.kind),
              'storageKeyHash': sha256
                  .convert(utf8.encode(record.storageKey))
                  .toString(),
              'messageIndex': record.messageIndex,
              'errorType': record.errorType,
              'createdAtMs': record.createdAtMs,
              'lastAttemptAtMs': record.lastAttemptAtMs,
            },
          )
          .toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<String> diagnosticLogSummary({int maxEntries = 100}) async {
    final records = await _storage.legacyRejectedRecords();
    final buffer = StringBuffer(
      'Message history migration quarantine contains ${records.length} '
      'entries.',
    );
    for (final record in records.take(maxEntries)) {
      final storageKeyHash = sha256
          .convert(utf8.encode(record.storageKey))
          .toString();
      buffer.write(
        '\nkind=${_kindName(record.kind)}, '
        'storageKeyHash=$storageKeyHash, '
        'messageIndex=${record.messageIndex}, '
        'errorType=${record.errorType}',
      );
    }
    if (records.length > maxEntries) {
      buffer.write('\n... ${records.length - maxEntries} more entries');
    }
    return buffer.toString();
  }

  Future<String> exportDiagnosticReport() async {
    final report = await diagnosticReport();
    return _writeExport('diagnostic', report);
  }

  Future<String> exportRecoveryData() async {
    final records = await _storage.legacyRejectedRecords();
    final payload = <String, Object?>{
      'format': 'mco-message-history-recovery',
      'version': 1,
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'containsPrivateMessageData': true,
      'entries': records
          .map(
            (record) => {
              'kind': _kindName(record.kind),
              'storageKey': record.storageKey,
              'messageIndex': record.messageIndex,
              'resolvedMessageId': record.resolvedMessageId,
              'rawValue': record.rawValue,
              'errorType': record.errorType,
              'errorText': record.errorText,
              'createdAtMs': record.createdAtMs,
              'lastAttemptAtMs': record.lastAttemptAtMs,
            },
          )
          .toList(growable: false),
    };
    final contents = const JsonEncoder.withIndent('  ').convert(payload);
    return _writeExport('recovery', contents);
  }

  Future<String> _writeExport(String suffix, String contents) async {
    final directory = await getApplicationSupportDirectory();
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'message_history_${suffix}_$timestamp.json',
    );
    await file.writeAsString(contents, flush: true);
    return file.path;
  }

  Future<void> incrementalVacuum({int pagesPerStep = 512}) async {
    var previousFreePages = -1;
    while (true) {
      final stats = await _storage.maintenanceStats();
      if (stats == null || stats.freePageCount <= 0) return;
      if (stats.freePageCount == previousFreePages) return;
      previousFreePages = stats.freePageCount;
      await _storage.incrementalVacuum(pages: pagesPerStep);
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> fullVacuum() => _storage.fullVacuum();

  String _kindName(int kind) => kind == MessageHistoryKind.channel.index
      ? 'channel'
      : 'direct';
}
