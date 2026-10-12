import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshcore_open/services/network_map/network_map_api_client.dart';

const _cell = {
  'cell': '872830828ffffff',
  'lat': 33.45,
  'lon': -112.08,
  'boundary': [
    [33.46, -112.09],
    [33.45, -112.07],
    [33.44, -112.07],
    [33.43, -112.08],
    [33.44, -112.10],
    [33.45, -112.10],
  ],
};

final _repeater = {
  'key': 'AB' * 32,
  'name': 'Hilltop RPT',
  'type': 2,
  'cell': _cell,
  'locationSource': 'advert',
  'confidence': 1.0,
  'status': 'active',
  'confirmed': true,
  'sightings': 14,
  'firstSeen': '2026-10-01T12:00:00Z',
  'lastSeen': '2026-10-11T18:41:00Z',
};

const _bbox = NetworkMapBbox(
  minLon: -113,
  minLat: 33,
  maxLon: -112,
  maxLat: 34,
);

void main() {
  test('parses repeaters and sends bbox', () async {
    late Uri requested;
    final client = NetworkMapApiClient(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'repeaters': [
              _repeater,
              {
                ..._repeater,
                'key': 'cd' * 32,
                'name': null,
                'type': 3,
                'locationSource': 'estimated',
                'confidence': 0.4,
                'status': 'stale',
                'confirmed': false,
              },
            ],
          }),
          200,
        );
      }),
    );
    final repeaters = await client.fetchRepeaters(_bbox);
    expect(requested.path, '/v1/repeaters');
    expect(requested.host, 'map.meshcoreopen.org');
    expect(
      requested.queryParameters['bbox'],
      '-113.00000,33.00000,-112.00000,34.00000',
    );
    expect(requested.queryParameters['includeUnconfirmed'], 'true');

    expect(repeaters, hasLength(2));
    final first = repeaters.first;
    expect(first.key, 'ab' * 32);
    expect(first.name, 'Hilltop RPT');
    expect(first.type, 2);
    expect(first.cell.cell, '872830828ffffff');
    expect(first.cell.center.latitude, 33.45);
    expect(first.cell.boundary, hasLength(6));
    expect(first.cell.boundary.first.latitude, 33.46);
    expect(first.cell.boundary.first.longitude, -112.09);
    expect(first.status, NetworkMapRepeaterStatus.active);
    expect(first.confirmed, isTrue);
    expect(first.isEstimated, isFalse);
    expect(first.sightings, 14);
    expect(first.lastSeen, DateTime.utc(2026, 10, 11, 18, 41));

    final second = repeaters.last;
    expect(second.name, isNull);
    expect(second.type, 3);
    expect(second.isEstimated, isTrue);
    expect(second.status, NetworkMapRepeaterStatus.stale);
    expect(second.confirmed, isFalse);
  });

  test('parses a single repeater and treats 404 as unknown', () async {
    final client = NetworkMapApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('ab' * 32)) {
          return http.Response(
            jsonEncode({
              ..._repeater,
              'links': 4,
              'coverageCells': 12,
              'reachableArea': '852830bffffffff',
            }),
            200,
          );
        }
        return http.Response('{"error":"not_found"}', 404);
      }),
    );
    final repeater = (await client.fetchRepeater('AB' * 32))!;
    expect(repeater.links, 4);
    expect(repeater.coverageCells, 12);
    expect(repeater.reachableArea, '852830bffffffff');
    expect(await client.fetchRepeater('ef' * 32), isNull);
  });

  test('parses links', () async {
    late Uri requested;
    final client = NetworkMapApiClient(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'links': [
              {
                'a': 'ab' * 32,
                'b': 'cd' * 32,
                'aCell': _cell,
                'bCell': _cell,
                'packets': 120,
                'snr': 6.5,
                'confirmed': true,
              },
              {
                'a': 'ab' * 32,
                'b': 'ef' * 32,
                'aCell': _cell,
                'bCell': _cell,
                'packets': 3,
                'snr': null,
                'confirmed': false,
              },
            ],
          }),
          200,
        );
      }),
    );
    final links = await client.fetchLinks(_bbox, window: '24h');
    expect(requested.path, '/v1/links');
    expect(requested.queryParameters['window'], '24h');
    expect(links, hasLength(2));
    expect(links.first.packets, 120);
    expect(links.first.snr, 6.5);
    expect(links.first.confirmed, isTrue);
    expect(links.first.aCell.boundary, hasLength(6));
    expect(links.last.snr, isNull);
  });

  test('errors surface the status code', () async {
    final client = NetworkMapApiClient(
      client: MockClient((_) async => http.Response('bad', 400)),
    );
    expect(
      () => client.fetchRepeaters(_bbox),
      throwsA(isA<NetworkMapApiException>()),
    );
  });

  test('bbox limit is 20 degrees per side', () {
    expect(_bbox.isWithinLimit, isTrue);
    expect(
      const NetworkMapBbox(
        minLon: -130,
        minLat: 30,
        maxLon: -105,
        maxLat: 40,
      ).isWithinLimit,
      isFalse,
    );
  });
}
