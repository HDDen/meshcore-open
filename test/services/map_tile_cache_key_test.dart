import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/map_tile_cache_service.dart';

// The cache key is what ties a stored tile to its record. Every key below is
// what the current build writes, so a repository that replaces the JSON index
// on desktop has to find the old records under the very same strings.

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

  test('a Yandex key drops the apikey and the signature and keeps the rest', () {
    expect(
      MapTileCacheService.tileCacheKey(
        'https://tiles.api-maps.yandex.ru/v1/tiles/?apikey=k%2Fx&lang=ru_RU'
        '&l=map&projection=web_mercator&maptype=map&x=1234&y=567&z=11&scale=1',
      ),
      'https://tiles.api-maps.yandex.ru/v1/tiles/?lang=ru_RU'
      '&l=map&projection=web_mercator&maptype=map&x=1234&y=567&z=11&scale=1',
    );
    // A signed dark tile: the signature goes, the theme stays, since the
    // theme is what tells the dark source's tiles from the light one's.
    expect(
      MapTileCacheService.tileCacheKey(
        'https://tiles.api-maps.yandex.ru/v1/tiles/?apikey=k&lang=en_US&l=map'
        '&projection=web_mercator&maptype=map&x=1&y=2&z=3&scale=1.5'
        '&theme=dark&signature=AbC_d-e%3D',
      ),
      'https://tiles.api-maps.yandex.ru/v1/tiles/?lang=en_US&l=map'
      '&projection=web_mercator&maptype=map&x=1&y=2&z=3&scale=1.5&theme=dark',
    );
  });

  test('a record of the current index carries the key of its url', () {
    // The url and key of a record as the JSON index on a Windows machine
    // holds them today, the API key replaced.
    expect(
      MapTileCacheService.tileCacheKey(
        'https://tiles.api-maps.yandex.ru/v1/tiles/'
        '?apikey=00000000-0000-0000-0000-000000000000&lang=ru_RU&l=map'
        '&projection=web_mercator&maptype=map&x=9962&y=5889&z=14&scale=2.0',
      ),
      'https://tiles.api-maps.yandex.ru/v1/tiles/?lang=ru_RU&l=map'
      '&projection=web_mercator&maptype=map&x=9962&y=5889&z=14&scale=2.0',
    );
  });

  test('keying a key changes nothing', () {
    const keys = [
      'https://tiles.stadiamaps.com/tiles/outdoors/10/1/2@2x.png',
      'https://tiles-eu.stadiamaps.com/tiles/osm_bright/12/3/4.png',
      'https://tile.openstreetmap.org/1/2/3.png',
      'https://tiles.api-maps.yandex.ru/v1/tiles/?lang=en_US&l=map'
          '&projection=web_mercator&maptype=map&x=1&y=2&z=3&scale=1&theme=dark',
    ];
    for (final key in keys) {
      expect(MapTileCacheService.tileCacheKey(key), key);
    }
  });

  test('a string that is no url is its own key', () {
    expect(
      MapTileCacheService.tileCacheKey('not a url at all'),
      'not a url at all',
    );
  });
}
