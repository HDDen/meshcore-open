import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_history.dart';
import 'package:meshcore_open/services/path_history_service.dart';
import 'package:meshcore_open/services/storage_service.dart';

class _Load {
  _Load(this.scope, this.contact);
  final String scope;
  final String contact;
  final result = Completer<ContactPathHistory?>();
}

class _Storage extends StorageService {
  String scope = 'a';
  bool delayLoads = true;
  final loads = <_Load>[];
  final saved = <String, ContactPathHistory>{};

  @override
  set setPublicKeyHex(String value) => scope = value;

  @override
  Future<ContactPathHistory?> loadPathHistory(String contactPubKeyHex) async {
    final load = _Load(scope, contactPubKeyHex);
    loads.add(load);
    if (delayLoads) return load.result.future;
    return saved['${load.scope}:$contactPubKeyHex'];
  }

  @override
  Future<void> savePathHistory(
    String contactPubKeyHex,
    ContactPathHistory history,
  ) async {
    final key = '$scope:$contactPubKeyHex';
    saved[key] = history;
  }

  @override
  Future<void> clearPathHistory(String contactPubKeyHex) async {
    saved.remove('$scope:$contactPubKeyHex');
  }

  @override
  Future<void> clearAllPathHistories() async {
    saved.removeWhere((key, value) => key.startsWith('$scope:'));
  }
}

ContactPathHistory _history(String key, int hop) => ContactPathHistory(
  contactPubKeyHex: key,
  recentPaths: [
    PathRecord(
      hopCount: 1,
      tripTimeMs: 1,
      timestamp: DateTime(2026),
      wasFloodDiscovery: true,
      pathBytes: [hop],
      successCount: 1,
      failureCount: 0,
    ),
  ],
);

Contact _contact(int hop) => Contact(
  publicKey: Uint8List(32),
  name: 'Test',
  type: 1,
  pathLength: 1,
  path: Uint8List.fromList([hop]),
  lastSeen: DateTime(2026),
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _Storage storage;
  late PathHistoryService service;
  setUp(() {
    storage = _Storage();
    service = PathHistoryService(storage);
  });
  tearDown(() => service.dispose());

  test(
    'an old load cannot populate the next radio or remove its pending load',
    () async {
      service.getRecentPaths('contact');
      await _settle();
      service.setDevicePublicKey('b');
      service.getRecentPaths('contact');
      await _settle();
      expect(storage.loads.map((load) => load.scope), ['a', 'b']);
      storage.loads[0].result.complete(_history('contact', 1));
      await _settle();
      expect(service.peekRecentPaths('contact'), isNull);
      service.getRecentPaths('contact');
      await _settle();
      expect(storage.loads, hasLength(2));
      storage.loads[1].result.complete(_history('contact', 2));
      await _settle();
      expect(service.peekRecentPaths('contact')!.single.pathBytes, [2]);
    },
  );

  test('an old pending path event cannot be added to the next radio', () async {
    final contact = _contact(1);
    service.handlePathUpdated(contact);
    await _settle();
    service.setDevicePublicKey('b');
    service.getRecentPaths(contact.publicKeyHex);
    await _settle();
    storage.loads[1].result.complete(_history(contact.publicKeyHex, 2));
    await _settle();
    storage.loads[0].result.complete(null);
    await _settle();
    expect(service.peekRecentPaths(contact.publicKeyHex)!.single.pathBytes, [2]);
  });

  test('clearing a contact invalidates an outstanding read', () async {
    service.getRecentPaths('contact');
    await _settle();
    await service.clearPathHistory('contact');
    storage.loads.single.result.complete(_history('contact', 1));
    await _settle();
    expect(service.peekRecentPaths('contact'), isNull);
  });

  for (final dispose in [false, true]) {
    test(
      '${dispose ? 'disposing' : 'clearing all'} prevents delayed load notifications',
      () async {
        var notifications = 0;
        service.addListener(() => notifications++);
        service.getRecentPaths('contact');
        await _settle();
        if (dispose) {
          service.dispose();
        } else {
          service.clearAllHistories();
        }
        final before = notifications;
        storage.loads.single.result.complete(_history('contact', 1));
        await _settle();
        expect(service.peekRecentPaths('contact'), isNull);
        expect(notifications, before);
      },
    );
  }

}
