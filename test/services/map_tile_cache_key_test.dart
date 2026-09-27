import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/map_tile_cache_service.dart';

void main() {
  test('tile cache key drops api_key and keeps everything else', () {
    expect(
      MapTileCacheService.tileCacheKey(
        'https://tiles.stadiamaps.com/tiles/outdoors/10/1/2@2x.png?api_key=k1',
      ),
      'https://tiles.stadiamaps.com/tiles/outdoors/10/1/2@2x.png',
    );
    expect(
      MapTileCacheService.tileCacheKey('https://x/t/1/2/3.png?a=1&api_key=k2'),
      'https://x/t/1/2/3.png?a=1',
    );
    expect(
      MapTileCacheService.tileCacheKey(
        'https://tile.openstreetmap.org/1/2/3.png',
      ),
      'https://tile.openstreetmap.org/1/2/3.png',
    );
  });
}
