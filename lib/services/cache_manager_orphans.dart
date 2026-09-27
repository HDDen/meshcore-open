import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute, debugPrint, kIsWeb;
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    show CacheObject, Config;

typedef _SweepJob = ({
  String directoryPath,
  Set<String> recordedNames,
  DateTime changedBefore,
});

final Set<String> _sweptCaches = {};

/// Deletes, once per cache and session and in the background, the files of a
/// flutter_cache_manager cache that none of its [records] names.
///
/// Before 3.4.2 the package deleted a cached file by its bare name against
/// the working directory of the process, so every removal dropped the record
/// and kept the file: a cleared map cache read 0 bytes while its tiles stayed
/// on disk. The package deletes the right file now; this takes back what the
/// old versions left, and any file whose record was lost some other way.
/// [records] has to be the cache's whole record list, read just before.
void sweepOrphanedCacheFilesOnce(Config config, Iterable<CacheObject> records) {
  if (kIsWeb || !_sweptCaches.add(config.cacheKey)) return;
  unawaited(deleteOrphanedCacheFiles(config, records));
}

/// The sweep itself, returning how many files went. A file changed within
/// [minimumAge] stays, since a file being downloaded exists before its record
/// does.
Future<int> deleteOrphanedCacheFiles(
  Config config,
  Iterable<CacheObject> records, {
  Duration minimumAge = const Duration(hours: 1),
}) async {
  try {
    // A name the cache never stores resolves to its directory without
    // creating anything there.
    final probe = await config.fileSystem.createFile('probe');
    return await compute(_deleteOrphans, (
      directoryPath: probe.parent.path,
      recordedNames: {for (final record in records) record.relativePath},
      changedBefore: DateTime.now().subtract(minimumAge),
    ));
  } catch (error) {
    debugPrint('cache_manager_orphans: ${config.cacheKey}: $error');
    return 0;
  }
}

// Runs in a background isolate: a leaked offline region can be tens of
// thousands of files.
int _deleteOrphans(_SweepJob job) {
  var deleted = 0;
  final entities = Directory(job.directoryPath).listSync(followLinks: false);
  for (final entity in entities) {
    if (entity is! File) continue;
    if (job.recordedNames.contains(entity.uri.pathSegments.last)) continue;
    try {
      if (!entity.lastModifiedSync().isBefore(job.changedBefore)) continue;
      entity.deleteSync();
      deleted++;
    } on FileSystemException {
      // Locked or already gone: the next sweep sees it again.
    }
  }
  return deleted;
}
