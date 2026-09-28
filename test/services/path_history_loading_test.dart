import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_history.dart';
import 'package:meshcore_open/services/path_history_service.dart';
import 'package:meshcore_open/services/storage_service.dart';

// Invariants of how path histories reach the service's cache and its
// listeners: what a first read of an unloaded contact does, what a write
// does, what a node switch does, and that an evicted history comes back on
// the next read. Pinned before the loading side is reworked for the map: the
// retry service, the routing sheet and the trace map all read through
// getRecentPaths and rely on exactly this.

class FakeStorageService extends StorageService {
  final Map<String, ContactPathHistory> store = {};
  int loads = 0;

  @override
  Future<void> savePathHistory(
    String contactPubKeyHex,
    ContactPathHistory history,
  ) async {
    store[contactPubKeyHex] = history;
  }

  @override
  Future<ContactPathHistory?> loadPathHistory(String contactPubKeyHex) async {
    loads++;
    return store[contactPubKeyHex];
  }

  @override
  Future<void> clearPathHistory(String contactPubKeyHex) async {
    store.remove(contactPubKeyHex);
  }
}

String _hex(int tag) => tag.toRadixString(16).padLeft(64, '0');

Contact _contact(String publicKeyHex, List<int> path) {
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[i] = int.parse(publicKeyHex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return Contact(
    publicKey: bytes,
    name: 'Test',
    type: 1,
    pathLength: path.length,
    path: Uint8List.fromList(path),
    lastSeen: DateTime.now(),
  );
}

ContactPathHistory _history(String key, List<List<int>> paths) =>
    ContactPathHistory(
      contactPubKeyHex: key,
      recentPaths: [
        for (final path in paths)
          PathRecord(
            hopCount: path.length,
            tripTimeMs: 0,
            timestamp: DateTime(2026, 9, 20),
            wasFloodDiscovery: true,
            pathBytes: path,
            successCount: 0,
            failureCount: 0,
          ),
      ],
    );

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeStorageService storage;
  late PathHistoryService service;
  late int notifications;

  setUp(() {
    storage = FakeStorageService();
    service = PathHistoryService(storage);
    notifications = 0;
    service.addListener(() => notifications++);
  });

  test('a stored history is loaded on the first read and reported once there',
      () async {
    final key = _hex(1);
    storage.store[key] = _history(key, [
      [0x11],
      [0x22, 0x33],
    ]);
    final version = service.version;

    expect(service.getRecentPaths(key), isEmpty);
    await _flush();

    expect(service.getRecentPaths(key).map((r) => r.pathBytes), [
      [0x11],
      [0x22, 0x33],
    ]);
    expect(service.version, greaterThan(version));
    expect(notifications, 1);
    expect(storage.loads, 1);
  });

  test('a contact with nothing stored is read once and reports nothing',
      () async {
    final key = _hex(2);
    final version = service.version;

    expect(service.getRecentPaths(key), isEmpty);
    await _flush();
    expect(service.getRecentPaths(key), isEmpty);
    await _flush();

    expect(service.version, version);
    expect(notifications, 0);
    expect(storage.loads, 1);
  });

  test('a write is readable at once and reported', () async {
    final key = _hex(3);
    final version = service.version;

    service.handlePathUpdated(_contact(key, [0x11, 0x22]));
    await _flush();

    expect(service.getRecentPaths(key).single.pathBytes, [0x11, 0x22]);
    expect(storage.store[key]?.recentPaths.single.pathBytes, [0x11, 0x22]);
    expect(service.version, greaterThan(version));
    expect(notifications, greaterThanOrEqualTo(1));
  });

  test('a known route written again refreshes its record instead of adding one',
      () async {
    final key = _hex(4);
    service.handlePathUpdated(_contact(key, [0x11]));
    await _flush();
    service.handlePathUpdated(_contact(key, [0x11]));
    await _flush();
    service.handlePathUpdated(_contact(key, [0x22]));
    await _flush();

    expect(service.getRecentPaths(key).map((r) => r.pathBytes), [
      [0x22],
      [0x11],
    ]);
  });

  test('switching the node drops the cache and reports', () async {
    final key = _hex(5);
    storage.store[key] = _history(key, [
      [0x11],
    ]);
    service.setDevicePublicKey(_hex(0xA));
    service.getRecentPaths(key);
    await _flush();
    expect(service.getRecentPaths(key), isNotEmpty);
    final version = service.version;
    final seen = notifications;

    service.setDevicePublicKey(_hex(0xB));

    expect(service.version, greaterThan(version));
    expect(notifications, greaterThan(seen));
    // The next read starts over from storage.
    final loads = storage.loads;
    expect(service.getRecentPaths(key), isEmpty);
    await _flush();
    expect(storage.loads, greaterThan(loads));
  });

  test('an evicted history comes back from storage on the next read',
      () async {
    // The cache keeps a bounded number of contacts; reading more than that
    // evicts the least recently used one, which storage still holds.
    const cap = 50;
    final first = _hex(0x100);
    storage.store[first] = _history(first, [
      [0x11],
    ]);
    service.getRecentPaths(first);
    await _flush();
    expect(service.getRecentPaths(first), isNotEmpty);

    for (var i = 1; i <= cap; i++) {
      final key = _hex(0x100 + i);
      storage.store[key] = _history(key, [
        [i & 0xFF],
      ]);
      service.getRecentPaths(key);
    }
    await _flush();

    final loads = storage.loads;
    expect(service.getRecentPaths(first), isEmpty);
    await _flush();
    expect(storage.loads, loads + 1);
    expect(service.getRecentPaths(first).single.pathBytes, [0x11]);
  });

  test('clearing one contact forgets it in memory and in storage', () async {
    final key = _hex(6);
    service.handlePathUpdated(_contact(key, [0x11]));
    await _flush();

    await service.clearPathHistory(key);

    expect(storage.store.containsKey(key), isFalse);
    expect(service.getRecentPaths(key), isEmpty);
    await _flush();
    expect(service.getRecentPaths(key), isEmpty);
  });
}
