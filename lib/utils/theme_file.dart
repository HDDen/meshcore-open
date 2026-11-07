import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

import '../models/custom_theme.dart';
import 'platform_info.dart';

/// File extension for exported themes: JSON Lines, one theme per line, each
/// line the same JSON as a theme's share code.
const String kThemeFileExtension = 'jsonl';
const int maxThemeFileBytes = 16 * 1024 * 1024;

const _typeGroup = XTypeGroup(
  label: 'MeshCore themes',
  extensions: [kThemeFileExtension, 'json', 'txt'],
  mimeTypes: [
    'application/jsonl',
    'application/x-ndjson',
    'application/json',
    'text/plain',
    'application/octet-stream',
  ],
  uniformTypeIdentifiers: ['public.json', 'public.plain-text', 'public.data'],
);

/// One theme per line, newline-terminated.
String encodeThemesJsonl(Iterable<CustomTheme> themes) {
  final buffer = StringBuffer();
  var count = 0;
  for (final theme in themes) {
    if (++count > CustomTheme.maxSavedThemes) {
      throw const FormatException('Too many themes in the export');
    }
    final line = theme.toShareCode();
    if (line.length > CustomTheme.maxShareCodeCharacters ||
        buffer.length + line.length + 1 > maxThemeFileBytes) {
      throw const FormatException('Theme export exceeds the size limit');
    }
    buffer.writeln(line);
  }
  return buffer.toString();
}

/// Reads every valid theme in [text], giving each a fresh ID from [newId].
///
/// Accepts JSON Lines (blank and invalid lines are skipped), and for
/// convenience a single theme object spread over several lines, as a
/// hand-edited or pretty-printed file would be.
List<CustomTheme> decodeThemesJsonl(
  String text, {
  required String Function() newId,
}) {
  if (text.length > maxThemeFileBytes) return const [];
  final themes = <CustomTheme>[];
  for (final line in LineSplitter.split(text)) {
    final theme = CustomTheme.fromShareCode(line, newId: '');
    if (theme == null) continue;
    if (themes.length == CustomTheme.maxSavedThemes) return const [];
    themes.add(theme.copyWith(id: newId()));
  }
  if (themes.isEmpty) {
    final whole = CustomTheme.fromShareCode(text, newId: '');
    if (whole != null) themes.add(whole.copyWith(id: newId()));
  }
  return themes;
}

/// A safe file name stem for [name] (letters, digits, dashes).
String themeFileStem(String name) {
  final stem = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return stem.isEmpty ? 'theme' : stem;
}

enum ThemeFileResult { saved, cancelled, failed }

/// Saves [themes] as a `.jsonl` file: a save dialog on desktop, a download
/// on web, and the share sheet on phones (which have no save dialog).
Future<ThemeFileResult> exportThemesFile(
  List<CustomTheme> themes, {
  required String fileStem,
  Rect? sharePositionOrigin,
}) async {
  try {
    final fileName = '${themeFileStem(fileStem)}.$kThemeFileExtension';
    final bytes = utf8.encode(encodeThemesJsonl(themes));
    if (bytes.length > maxThemeFileBytes) return ThemeFileResult.failed;
    final file = XFile.fromData(
      bytes,
      name: fileName,
      mimeType: 'application/jsonl',
    );
    if (PlatformInfo.isWeb) {
      await file.saveTo(fileName);
      return ThemeFileResult.saved;
    }
    if (PlatformInfo.isDesktop) {
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [_typeGroup],
      );
      if (location == null) return ThemeFileResult.cancelled;
      await file.saveTo(location.path);
      return ThemeFileResult.saved;
    }
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [file],
        fileNameOverrides: [fileName],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return result.status == ShareResultStatus.dismissed
        ? ThemeFileResult.cancelled
        : ThemeFileResult.saved;
  } catch (_) {
    return ThemeFileResult.failed;
  }
}

/// Lets the user pick a theme file and returns its text, or null when they
/// cancel. Throws when the file cannot be read.
Future<String?> pickThemesFile() async {
  final file = await openFile(acceptedTypeGroups: const [_typeGroup]);
  if (file == null) return null;
  if (await file.length() > maxThemeFileBytes) {
    throw const FormatException('Theme file exceeds the size limit');
  }
  final data = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    if (data.length + chunk.length > maxThemeFileBytes) {
      throw const FormatException('Theme file exceeds the size limit');
    }
    data.add(chunk);
  }
  return utf8.decode(data.takeBytes(), allowMalformed: true);
}
