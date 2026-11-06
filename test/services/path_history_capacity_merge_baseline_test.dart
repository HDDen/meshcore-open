import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_history.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/services/path_history_service.dart';
import 'package:meshcore_open/services/storage_service.dart';

const _key =
    '00000000000000000000000000000000'
    '00000000000000000000000000000001';
final _at = DateTime.utc(2026, 1, 2);

List<int> _path(int index, int width) => switch (width) {
  1 => [index, 0xEE],
  2 => [0xA0, index, 0xB0, 0xEE],
  3 => [0xA0, 0xB0, index, 0xC0, 0xD0, 0xEE],
  _ => throw ArgumentError.value(width),
};

PathRecord _record(
  int index, {
  int width = 1,
  int successes = 2,
  int failures = 1,
  int tripMs = 1000,
  double weight = 3,
}) => PathRecord(
  hopCount: 2,
  tripTimeMs: tripMs,
  timestamp: _at,
  wasFloodDiscovery: false,
  pathBytes: _path(index, width),
  successCount: successes,
  failureCount: failures,
  routeWeight: weight,
);

ContactPathHistory _history({int count = 100, int width = 1}) => ContactPathHistory(
  contactPubKeyHex: _key,
  recentPaths: List.generate(count, (i) => _record(i, width: width)),
);

class _Storage extends StorageService {
  _Storage(this.history);

  ContactPathHistory history;
  int loads = 0;
  final writes = <ContactPathHistory>[];
  final savedKeys = <String>[];

  @override
  Future<ContactPathHistory?> loadPathHistory(String contactPubKeyHex) async {
    loads++;
    return contactPubKeyHex == _key ? history : null;
  }

  @override
  Future<void> savePathHistory(String contactPubKeyHex, ContactPathHistory value) async {
    savedKeys.add(contactPubKeyHex);
    writes.add(value);
    history = value;
  }
}

class _Fixture {
  _Fixture(ContactPathHistory history) : storage = _Storage(history) {
    service = PathHistoryService(storage);
    service.addListener(() => notifications++);
  }

  final _Storage storage;
  late final PathHistoryService service;
  int notifications = 0;
}

Future<_Fixture> _loadFixture({
  int count = 100,
  int width = 1,
  ContactPathHistory? history,
}) async {
  final f = _Fixture(history ?? _history(count: count, width: width));
  addTearDown(f.service.dispose);
  await f.service.ensureLoaded([_key]);
  expect(f.storage.loads, 1);
  expect(f.service.peekRecentPaths(_key), hasLength(count));
  f.notifications = 0;
  return f;
}

PathSelection _selection(int index, {int width = 1}) => PathSelection(
  pathBytes: _path(index, width), hopCount: 2, useFlood: false,
);

Contact _discovery(int index, int width) => Contact(
  publicKey: Uint8List(32)..[31] = 1,
  name: 'Synthetic recipient',
  type: 1,
  pathLength: 2,
  pathHashWidth: width,
  path: Uint8List.fromList(_path(index, width)),
  lastSeen: _at,
);

ContactPathHistory _withWeakRoute(int width) {
  final history = _history(width: width);
  // A route's full score matters: route 8 has lower weight but is reliable
  // and fast. Route 7 must lose despite having the ordinary weight of 3.
  history.recentPaths[7] = _record(
    7, width: width, successes: 0, failures: 20, tripMs: 9000,
  );
  history.recentPaths[8] = _record(
    8, width: width, successes: 20, failures: 0, tripMs: 500, weight: 0.1,
  );
  return history;
}

Map<String, Map<String, dynamic>> _snapshots(Iterable<PathRecord> records) => {
  for (final record in records) record.pathBytes.join(','): {
    ...record.toJson(),
    'path_bytes': List<int>.of(record.pathBytes),
  },
};

void main() {
  for (final width in [1, 2, 3]) {
    test('U12c baseline: full history updates one route with $width-byte hops', () async {
      final f = await _loadFixture(width: width);
      final before = _snapshots(f.service.getRecentPaths(_key));
      final version = f.service.version;
      final routes = f.service.routesVersion;
      final selected = _selection(7, width: width);
      f.service.recordPathResult(_key, selected, success: true, tripTimeMs: 1200);
      final paths = f.service.getRecentPaths(_key);
      expect(paths, hasLength(100));
      final updated = paths.first;
      expect(updated.pathBytes, selected.pathBytes);
      expect(updated.hopCount, 2);
      expect(updated.pathBytes, hasLength(width * 2));
      expect(updated.successCount, 3);
      expect(updated.failureCount, 1);
      expect(updated.routeWeight, 3.5);
      expect(updated.tripTimeMs, 1200);
      expect(updated.wasFloodDiscovery, isFalse);
      expect(updated.timestamp, isNotNull);
      final after = _snapshots(paths);
      before.remove(selected.pathBytes.join(','));
      after.remove(selected.pathBytes.join(','));
      expect(after, before, reason: 'Updating a route must not evict another');
      expect(f.service.version, version + 1);
      expect(f.service.routesVersion, routes);
      expect(f.notifications, 1);
      expect(f.storage.writes, hasLength(1));
      expect(f.storage.savedKeys, [_key]);
      expect(f.storage.history.toJson(), {'recent_paths': paths.map((p) => p.toJson()).toList()});
    });
  }

  test('U12c baseline: discovery below capacity adds exactly one route and save', () async {
    final f = await _loadFixture(count: 99, width: 3);
    final before = _snapshots(f.service.getRecentPaths(_key));
    final version = f.service.version;
    final routes = f.service.routesVersion;
    final contact = _discovery(0xFE, 3);
    f.service.handlePathUpdated(contact);
    final paths = f.service.getRecentPaths(_key);
    expect(paths, hasLength(100));
    expect(paths.first.pathBytes, contact.path);
    expect(paths.first.hopCount, 2);
    expect(paths.first.wasFloodDiscovery, isTrue);
    expect(paths.first.successCount, 0);
    expect(paths.first.failureCount, 0);
    expect(_snapshots(paths.skip(1)), before);
    expect(f.service.version, version + 1);
    expect(f.service.routesVersion, routes + 1);
    expect(f.notifications, 1);
    expect(f.storage.writes, hasLength(1));
  });

  test('U12c baseline: recording an existing attempt preserves learned metadata at capacity', () async {
    final f = await _loadFixture(width: 2);
    final selected = _selection(7, width: 2);
    final before = f.service.getRecentPaths(_key)[7].toJson();
    final routes = f.service.routesVersion;
    f.service.recordPathAttempt(_key, selected);
    final paths = f.service.getRecentPaths(_key);
    expect(paths, hasLength(100));
    expect(paths.first.toJson(), before);
    expect(f.service.routesVersion, routes);
    expect(f.storage.writes, hasLength(1));
    expect(f.notifications, 1);
  });

  test('U12c baseline: flood statistics do not evict or save direct routes', () async {
    final f = await _loadFixture();
    final before = _snapshots(f.service.getRecentPaths(_key));
    final version = f.service.version;
    final routes = f.service.routesVersion;
    const flood = PathSelection(pathBytes: [], hopCount: -1, useFlood: true);
    f.service.recordPathAttempt(_key, flood);
    f.service.recordPathResult(_key, flood, success: true, tripTimeMs: 700);
    expect(_snapshots(f.service.getRecentPaths(_key)), before);
    expect(f.service.getFloodStats(_key)?.successCount, 1);
    expect(f.service.getFloodStats(_key)?.lastTripTimeMs, 700);
    expect(f.service.version, version);
    expect(f.service.routesVersion, routes);
    expect(f.notifications, 0);
    expect(f.storage.writes, isEmpty);
  });

  test('U12c baseline: ranking and retry diversity remain read-only at capacity', () async {
    final history = _history(width: 2);
    history.recentPaths[7] = _record(
      7, width: 2, successes: 20, failures: 0, tripMs: 500, weight: 5,
    );
    final f = await _loadFixture(width: 2, history: history);
    final before = _snapshots(f.service.getRecentPaths(_key));
    final version = f.service.version;
    final routes = f.service.routesVersion;
    final best = f.service.selectPathForAttempt(_key, attemptIndex: 0, maxRetries: 5);
    expect(best.pathBytes, _path(7, 2));
    expect(best.hopCount, 2);
    final next = f.service.selectPathForAttempt(
      _key, attemptIndex: 1, maxRetries: 5, recentSelections: [best],
    );
    expect(next.useFlood, isFalse);
    expect(next.pathBytes, isNot(best.pathBytes));
    expect(f.service.selectPathForAttempt(_key, attemptIndex: 4, maxRetries: 5).useFlood, isTrue);
    expect(_snapshots(f.service.getRecentPaths(_key)), before);
    expect(f.service.version, version);
    expect(f.service.routesVersion, routes);
    expect(f.storage.loads, 1);
    expect(f.storage.writes, isEmpty);
    expect(f.notifications, 0);
  });

  for (final width in [1, 2, 3]) {
    test('U12c: full history replaces the lowest-scored route with $width-byte hops', () async {
      final f = await _loadFixture(width: width, history: _withWeakRoute(width));
      final before = _snapshots(f.service.getRecentPaths(_key))
        ..remove(_path(7, width).join(','));
      final version = f.service.version;
      final routes = f.service.routesVersion;
      final discovered = _discovery(0xFE, width);
      f.service.handlePathUpdated(discovered);
      final paths = f.service.getRecentPaths(_key);
      expect(paths, hasLength(100));
      expect(paths.first.pathBytes, discovered.path);
      expect(paths.first.hopCount, 2);
      expect(paths.first.pathBytes, hasLength(width * 2));
      expect(paths.first.wasFloodDiscovery, isTrue);
      expect(paths.first.successCount, 0);
      expect(paths.first.failureCount, 0);
      expect(_snapshots(paths.skip(1)), before,
          reason: 'Evict route 7, preserve the faster low-weight route and all others');
      expect(f.service.version, version + 1);
      expect(f.service.routesVersion, routes + 1);
      expect(f.storage.writes, hasLength(1));
      expect(f.storage.savedKeys, [_key]);
      expect(f.notifications, 1);
      expect(f.storage.loads, 1);
      expect(f.storage.history.recentPaths, paths);
    });
  }

  test('U12c: a newly successful route is retained at capacity', () async {
    final f = await _loadFixture(width: 2, history: _withWeakRoute(2));
    final routes = f.service.routesVersion;
    f.service.recordPathResult(
      _key, _selection(0xFE, width: 2), success: true, tripTimeMs: 600,
    );
    final paths = f.service.getRecentPaths(_key);
    expect(paths, hasLength(100));
    expect(paths.first.pathBytes, _path(0xFE, 2));
    expect(paths.first.successCount, 1);
    expect(paths.first.failureCount, 0);
    expect(paths.first.routeWeight, 1.5);
    expect(paths.first.tripTimeMs, 600);
    expect(paths.any((path) => path.pathBytes.join(',') == _path(7, 2).join(',')), isFalse);
    expect(f.service.routesVersion, routes + 1);
    expect(f.storage.writes, hasLength(1));
    expect(f.notifications, 1);
  });

  test('U12c: flood attribution can retain a newly learned direct route at capacity', () async {
    final f = await _loadFixture(width: 3, history: _withWeakRoute(3));
    f.service.recordFloodPathAttribution(
      contactPubKeyHex: _key,
      pathBytes: _path(0xFE, 3),
      hopCount: 2,
      tripTimeMs: 700,
    );
    final paths = f.service.getRecentPaths(_key);
    expect(paths, hasLength(100));
    expect(paths.first.pathBytes, _path(0xFE, 3));
    expect(paths.first.hopCount, 2);
    expect(paths.first.wasFloodDiscovery, isTrue);
    expect(paths.first.successCount, 1);
    expect(paths.first.routeWeight, 1.5);
    expect(paths.first.tripTimeMs, 700);
    expect(paths.any((path) => path.pathBytes.join(',') == _path(7, 3).join(',')), isFalse);
    expect(f.storage.writes, hasLength(1));
    expect(f.notifications, 1);
  });

  test('U12c: equal scores evict the first tied record without reordering the rest', () async {
    final history = _history(width: 2);
    for (var i = 0; i < history.recentPaths.length; i++) {
      final original = history.recentPaths[i];
      // Null freshness makes an exact tie independent of the wall clock.
      history.recentPaths[i] = PathRecord(
        hopCount: original.hopCount,
        tripTimeMs: original.tripTimeMs,
        timestamp: null,
        wasFloodDiscovery: original.wasFloodDiscovery,
        pathBytes: original.pathBytes,
        successCount: original.successCount,
        failureCount: original.failureCount,
        routeWeight: original.routeWeight,
      );
    }
    final expectedRest = history.recentPaths.skip(1).map((path) => path.toJson()).toList();
    final f = await _loadFixture(width: 2, history: history);
    f.service.handlePathUpdated(_discovery(0xFE, 2));
    final paths = f.service.getRecentPaths(_key);
    expect(paths, hasLength(100));
    expect(paths.first.pathBytes, _path(0xFE, 2));
    expect(paths.skip(1).map((path) => path.toJson()), expectedRest);
    expect(f.storage.writes, hasLength(1));
    expect(f.notifications, 1);
  });
}
