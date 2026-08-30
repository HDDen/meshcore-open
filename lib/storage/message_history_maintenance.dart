import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

  Future<String?> exportDiagnosticReport() async {
    final report = await diagnosticReport();
    return _deliverExport('diagnostic', report);
  }

  Future<String?> exportRecoveryData() async {
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
    return _deliverExport('recovery', contents);
  }

  Future<String?> _deliverExport(String suffix, String contents) async {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final fileName = 'message_history_${suffix}_$timestamp.json';
    final bytes = Uint8List.fromList(utf8.encode(contents));
    if (Platform.isAndroid || Platform.isIOS) {
      return _shareExport(bytes, fileName);
    }
    try {
      final location = await file_selector.getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          file_selector.XTypeGroup(
            label: 'JSON document',
            extensions: ['json'],
            mimeTypes: ['application/json'],
            uniformTypeIdentifiers: ['public.json'],
          ),
        ],
      );
      if (location == null) return null;
      await XFile.fromData(
        bytes,
        mimeType: 'application/json',
        name: fileName,
      ).saveTo(location.path);
      return location.path;
    } catch (saveError) {
      return _shareExport(bytes, fileName, saveError: saveError);
    }
  }

  Future<String?> _shareExport(
    Uint8List bytes,
    String fileName, {
    Object? saveError,
  }) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'application/json',
            name: fileName,
          ),
        ],
        fileNameOverrides: [fileName],
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => '',
      ShareResultStatus.dismissed => null,
      ShareResultStatus.unavailable => throw StateError(
        saveError == null
            ? 'Sharing is unavailable on this platform'
            : 'Saving and sharing are unavailable: $saveError',
      ),
    };
  }

  Future<void> incrementalVacuum({int pagesPerStep = 512}) async {
    final initialStats = await _storage.maintenanceStats();
    if (initialStats == null) return;
    if (initialStats.autoVacuumMode != 2) {
      throw UnsupportedError(
        'Incremental vacuum requires auto_vacuum = INCREMENTAL',
      );
    }
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
