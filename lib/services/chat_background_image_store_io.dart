import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../helpers/theme_media.dart';
import 'chat_background_image_store_base.dart';

ChatBackgroundImageStore createChatBackgroundImageStore() =>
    _FileChatBackgroundImageStore();

class _FileChatBackgroundImageStore implements ChatBackgroundImageStore {
  Future<Directory>? _directory;

  Future<Directory> _resolveDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/chat_backgrounds');
  }

  Future<Directory> _dir() => _directory ??= _resolveDirectory();

  Future<File> _file(String id) async {
    if (!isStoredThemeImageId(id)) throw ArgumentError('Invalid background ID');
    return File('${(await _dir()).path}/$id.jxl');
  }

  @override
  Future<void> write(String id, Uint8List bytes) async {
    final file = await _file(id);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  @override
  Future<Uint8List?> read(String id) async {
    final file = await _file(id);
    if (!await file.exists() || await file.length() > maxThemeBackgroundBytes) {
      return null;
    }
    final bytes = await file.readAsBytes();
    return bytes.length <= maxThemeBackgroundBytes ? bytes : null;
  }

  @override
  Future<void> delete(String id) async {
    final file = await _file(id);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<Set<String>> listIds() async {
    final dir = await _dir();
    if (!await dir.exists()) return {};
    final ids = <String>{};
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (!name.endsWith('.jxl')) continue;
      final id = name.substring(0, name.length - 4);
      if (isStoredThemeImageId(id)) ids.add(id);
    }
    return ids;
  }
}
