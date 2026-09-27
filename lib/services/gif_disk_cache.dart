import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// GIFs from chat messages, kept on disk between launches.
///
/// The file system is the whole index. A file is named by the SHA-256 of its
/// URL, its size is what counts against [maxBytes], and its modification time
/// is the moment it was last shown: [write] sets it and every [read] moves it
/// forward. After each write, and once a session before the first read, the
/// files not shown for longer than [lifetime] are deleted, then the ones shown
/// longest ago until the rest fits. No record is kept anywhere else, so none
/// can drift from the files.
///
/// Every method is total: a failure costs the cache, never the image, which
/// the caller then fetches from the network as it always did.
class GifDiskCache {
  GifDiskCache({
    required Future<Directory> Function() baseDirectory,
    this.maxBytes = 200 * 1024 * 1024,
    this.lifetime = const Duration(days: 365),
    DateTime Function()? now,
  }) : _baseDirectory = baseDirectory,
       _now = now ?? DateTime.now;

  static const String directoryName = 'gif_cache';
  static const String _partialSuffix = '.tmp';
  static final RegExp _cachedName = RegExp(r'^[0-9a-f]{64}\.gif$');

  final int maxBytes;
  final Duration lifetime;
  final Future<Directory> Function() _baseDirectory;
  final DateTime Function() _now;

  String? _directoryPath;
  bool _swept = false;

  // Every operation starts after the previous one has finished, so a trim
  // never deletes a file that is being read or written.
  Future<void> _queue = Future<void>.value();

  /// The name [url] is kept under inside the cache directory.
  static String fileNameFor(String url) =>
      '${sha256.convert(utf8.encode(url))}.gif';

  /// The cached bytes of [url], or null on a miss. A hit counts as a showing.
  Future<Uint8List?> read(String url) {
    if (!_swept) {
      // The lifetime has to hold even in a session that downloads nothing.
      _swept = true;
      unawaited(_serial(_trim));
    }
    return _serial(() => _read(url));
  }

  /// Keeps [bytes] as the content of [url], then trims the cache. Nothing
  /// larger than the whole cache is kept.
  Future<void> write(String url, Uint8List bytes) =>
      _serial(() => _write(url, bytes));

  /// Drops [url], whose bytes no longer decode.
  Future<void> remove(String url) => _serial(() async {
    try {
      await _delete(await _fileFor(url));
    } on Exception {
      // Nothing to drop.
    }
  });

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Uint8List?> _read(String url) async {
    try {
      final file = await _fileFor(url);
      final bytes = await file.readAsBytes();
      await _markShown(file);
      return bytes;
    } on Exception {
      return null;
    }
  }

  Future<void> _write(String url, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxBytes) return;
    File? partial;
    try {
      final file = await _fileFor(url);
      // Written aside and renamed, so an interrupted write leaves a partial
      // file for the next trim and never a truncated GIF under the real name.
      partial = File('${file.path}$_partialSuffix');
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(file.path);
      await _markShown(file);
    } on Exception {
      if (partial != null) await _delete(partial);
      return;
    }
    await _trim(keep: fileNameFor(url));
  }

  /// Deletes what went unshown for longer than [lifetime], then what was
  /// shown longest ago until the rest fits in [maxBytes]. [keep] names the
  /// file just written, which stays even when the clock has gone back.
  Future<void> _trim({String? keep}) async {
    final entries = <({File file, String name, int size, DateTime shownAt})>[];
    try {
      final directory = await _directory();
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.endsWith(_partialSuffix)) {
          // Left by a write the app did not live to finish: writes run in
          // the queue, so none is in progress now.
          await _delete(entity);
          continue;
        }
        if (!_cachedName.hasMatch(name)) continue;
        final stat = await entity.stat();
        if (stat.type != FileSystemEntityType.file) continue;
        entries.add((
          file: entity,
          name: name,
          size: stat.size,
          shownAt: stat.modified,
        ));
      }
    } on Exception {
      return;
    }
    entries.sort((a, b) => a.shownAt.compareTo(b.shownAt));
    var total = entries.fold<int>(0, (sum, entry) => sum + entry.size);
    final expiredBefore = _now().subtract(lifetime);
    for (final entry in entries) {
      if (total <= maxBytes && !entry.shownAt.isBefore(expiredBefore)) break;
      if (entry.name == keep) continue;
      if (await _delete(entry.file)) total -= entry.size;
    }
  }

  /// Puts [file] last in line for eviction.
  Future<void> _markShown(File file) async {
    try {
      await file.setLastModified(_now());
    } on Exception {
      // The file keeps its older place in line.
    }
  }

  Future<File> _fileFor(String url) async {
    final directory = await _directory();
    return File(
      '${directory.path}${Platform.pathSeparator}${fileNameFor(url)}',
    );
  }

  /// Created again whenever it is asked for: the system may empty the
  /// application cache while the app runs.
  Future<Directory> _directory() async {
    final path = _directoryPath ??=
        '${(await _baseDirectory()).path}${Platform.pathSeparator}'
        '$directoryName';
    return Directory(path).create(recursive: true);
  }

  /// Whether [file] is gone afterwards.
  static Future<bool> _delete(File file) async {
    try {
      await file.delete();
      return true;
    } on PathNotFoundException {
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
