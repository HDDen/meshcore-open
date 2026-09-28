import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/cache_manager_orphans.dart';

// The orphan sweep deletes every file of the cache directory that no record
// names. It therefore hangs on the records being complete: a repository that
// loses records, or an import that misses some, costs their files at the
// next sweep. This pins what it deletes and what it spares.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mco_tile_orphans_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    tempDir.deleteSync(recursive: true);
  });

  test('files no record names go once they are old enough; recorded, fresh '
      'and non-file entries stay', () async {
    const cacheKey = 'map_tile_cache_orphans';
    final repo = JsonCacheInfoRepository.withFile(
      File('${tempDir.path}${Platform.pathSeparator}$cacheKey.json'),
    );
    final config = Config(
      cacheKey,
      repo: repo,
      fileSystem: IOFileSystem(cacheKey),
    );
    final directory = Directory(
      '${tempDir.path}${Platform.pathSeparator}$cacheKey',
    )..createSync(recursive: true);
    final now = DateTime.now();
    File write(String name, DateTime modified) {
      final file = File('${directory.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(const [1, 2, 3])
        ..setLastModifiedSync(modified);
      return file;
    }

    final kept = write('kept.png', now.subtract(const Duration(hours: 3)));
    final orphanOld = write(
      'orphan_old.png',
      now.subtract(const Duration(hours: 3)),
    );
    final orphanFresh = write(
      'orphan_fresh.png',
      now.subtract(const Duration(minutes: 1)),
    );
    final subdirectory = Directory(
      '${directory.path}${Platform.pathSeparator}sub',
    )..createSync();
    final records = [
      CacheObject(
        'https://tile.openstreetmap.org/1/2/3.png',
        relativePath: 'kept.png',
        validTill: DateTime(2027, 1, 1),
      ),
    ];

    expect(await deleteOrphanedCacheFiles(config, records), 1);

    expect(kept.existsSync(), isTrue);
    expect(orphanOld.existsSync(), isFalse);
    expect(orphanFresh.existsSync(), isTrue);
    expect(subdirectory.existsSync(), isTrue);

    // With a shorter minimum age the fresh orphan goes as well.
    expect(
      await deleteOrphanedCacheFiles(
        config,
        records,
        minimumAge: const Duration(seconds: 30),
      ),
      1,
    );
    expect(orphanFresh.existsSync(), isFalse);
    expect(kept.existsSync(), isTrue);
  });

  test('with no records every old file is an orphan', () async {
    const cacheKey = 'map_tile_cache_orphans_empty';
    final repo = JsonCacheInfoRepository.withFile(
      File('${tempDir.path}${Platform.pathSeparator}$cacheKey.json'),
    );
    final config = Config(
      cacheKey,
      repo: repo,
      fileSystem: IOFileSystem(cacheKey),
    );
    final directory = Directory(
      '${tempDir.path}${Platform.pathSeparator}$cacheKey',
    )..createSync(recursive: true);
    final old = DateTime.now().subtract(const Duration(days: 2));
    for (var i = 0; i < 3; i++) {
      File('${directory.path}${Platform.pathSeparator}tile_$i.png')
        ..writeAsBytesSync(const [0])
        ..setLastModifiedSync(old);
    }

    expect(await deleteOrphanedCacheFiles(config, const []), 3);
    expect(directory.listSync(), isEmpty);
  });
}
