import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/gif_disk_cache.dart';

void main() {
  late Directory tempDir;
  late DateTime now;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gif_cache_test');
    now = DateTime(2026, 1, 1, 12);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  GifDiskCache newCache({int maxBytes = 100}) => GifDiskCache(
    baseDirectory: () async => tempDir,
    maxBytes: maxBytes,
    now: () => now,
  );

  Uint8List bytesOf(int length, [int fill = 1]) =>
      Uint8List.fromList(List<int>.filled(length, fill));

  File fileOf(String url) => File(
    '${tempDir.path}${Platform.pathSeparator}${GifDiskCache.directoryName}'
    '${Platform.pathSeparator}${GifDiskCache.fileNameFor(url)}',
  );

  const a = 'https://media.giphy.com/media/a/giphy.gif';
  const b = 'https://media.giphy.com/media/b/giphy.gif';
  const c = 'https://media.giphy.com/media/c/giphy.gif';

  test('a GIF outlives the instance that stored it', () async {
    await newCache().write(a, bytesOf(40));
    expect(await newCache().read(a), bytesOf(40));
    expect(await newCache().read(b), isNull);
  });

  test('a second write replaces the first', () async {
    final cache = newCache();
    await cache.write(a, bytesOf(10));
    await cache.write(a, bytesOf(20, 2));
    expect(await cache.read(a), bytesOf(20, 2));
  });

  test('showing a GIF moves its time forward', () async {
    final cache = newCache();
    await cache.write(a, bytesOf(40));
    expect(fileOf(a).lastModifiedSync(), now);
    now = now.add(const Duration(days: 3));
    await cache.read(a);
    expect(fileOf(a).lastModifiedSync(), now);
  });

  test('over the limit, the GIF shown longest ago goes first', () async {
    final cache = newCache();
    await cache.write(a, bytesOf(40));
    now = now.add(const Duration(minutes: 1));
    await cache.write(b, bytesOf(40));
    now = now.add(const Duration(minutes: 1));
    // Shown again, so b is now the one shown longest ago.
    await cache.read(a);
    now = now.add(const Duration(minutes: 1));
    await cache.write(c, bytesOf(40));

    expect(fileOf(a).existsSync(), isTrue);
    expect(fileOf(b).existsSync(), isFalse);
    expect(fileOf(c).existsSync(), isTrue);
  });

  test('a write drops GIFs unshown for longer than the lifetime', () async {
    await newCache().write(a, bytesOf(10));
    now = now.add(const Duration(days: 366));
    await newCache().write(b, bytesOf(10));

    expect(fileOf(a).existsSync(), isFalse);
    expect(fileOf(b).existsSync(), isTrue);
  });

  test('the first read of a session sweeps expired GIFs', () async {
    await newCache().write(a, bytesOf(10));
    now = now.add(const Duration(days: 364));
    await newCache().write(b, bytesOf(10));
    now = now.add(const Duration(days: 2));

    expect(await newCache().read(c), isNull);

    expect(fileOf(a).existsSync(), isFalse);
    expect(fileOf(b).existsSync(), isTrue);
  });

  test('nothing larger than the whole cache is kept', () async {
    final cache = newCache();
    await cache.write(a, bytesOf(101));
    expect(await cache.read(a), isNull);
  });

  test('a partial file left by an interrupted write is swept', () async {
    final cache = newCache();
    await cache.write(a, bytesOf(10));
    final partial = File('${fileOf(b).path}.tmp');
    await partial.writeAsBytes(bytesOf(10));
    await cache.write(c, bytesOf(10));

    expect(partial.existsSync(), isFalse);
    expect(fileOf(a).existsSync(), isTrue);
  });

  test('remove drops the file', () async {
    final cache = newCache();
    await cache.write(a, bytesOf(10));
    await cache.remove(a);
    expect(await cache.read(a), isNull);
  });
}
