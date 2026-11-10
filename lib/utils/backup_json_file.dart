import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

import 'platform_info.dart';

const backupJsonFileType = XTypeGroup(
  label: 'JSON',
  extensions: ['json'],
  mimeTypes: ['application/json'],
  uniformTypeIdentifiers: ['public.json'],
);

enum BackupJsonSaveResult { saved, shareOpened, cancelled }

/// Saves directly on desktop and web, or offers the file via the share sheet.
Future<BackupJsonSaveResult> saveBackupJson(
  String contents,
  String fileName, {
  Rect? sharePositionOrigin,
}) async {
  final file = XFile.fromData(
    utf8.encode(contents),
    name: fileName,
    mimeType: 'application/json',
  );
  if (PlatformInfo.isWeb) {
    await file.saveTo(fileName);
    return BackupJsonSaveResult.saved;
  }
  if (PlatformInfo.isDesktop) {
    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: const [backupJsonFileType],
    );
    if (location == null) return BackupJsonSaveResult.cancelled;
    await file.saveTo(location.path);
    return BackupJsonSaveResult.saved;
  }

  final result = await SharePlus.instance.share(
    ShareParams(
      files: [file],
      fileNameOverrides: [fileName],
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
  return result.status == ShareResultStatus.dismissed
      ? BackupJsonSaveResult.cancelled
      : BackupJsonSaveResult.shareOpened;
}
