import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'gif_disk_cache.dart';

/// The one cache every GIF on screen shares.
final GifDiskCache _cache = GifDiskCache(
  baseDirectory: getApplicationCacheDirectory,
);

ImageProvider gifImageProvider(String url) => CachedGifImage(url);

/// A GIF read from [GifDiskCache] first and from the network only on a miss.
///
/// A download is kept only once it has decoded, so an error page served with
/// a 200 never takes a place in the cache, and a cached file that no longer
/// decodes is dropped and fetched again.
class CachedGifImage extends ImageProvider<CachedGifImage> {
  const CachedGifImage(this.url);

  final String url;

  @override
  Future<CachedGifImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedGifImage>(this);

  @override
  ImageStreamCompleter loadImage(
    CachedGifImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: url,
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final cached = await _cache.read(url);
    if (cached != null) {
      try {
        return await _decode(cached, decode);
      } catch (_) {
        await _cache.remove(url);
      }
    }
    final uri = Uri.parse(url);
    final response = await http.get(uri);
    final bytes = response.bodyBytes;
    if (response.statusCode != 200 || bytes.isEmpty) {
      throw NetworkImageLoadException(
        statusCode: response.statusCode,
        uri: uri,
      );
    }
    final codec = await _decode(bytes, decode);
    unawaited(_cache.write(url, bytes));
    return codec;
  }

  static Future<ui.Codec> _decode(
    Uint8List bytes,
    ImageDecoderCallback decode,
  ) async => decode(await ui.ImmutableBuffer.fromUint8List(bytes));

  @override
  bool operator ==(Object other) => other is CachedGifImage && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => '${objectRuntimeType(this, 'CachedGifImage')}("$url")';
}
