import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/delivery_observation.dart';
import 'package:meshcore_open/models/path_history.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What StorageService promises about path histories, delivery observations
// and the app-wide maps it keeps, pinned on their preference form before
// they move into the database: the contract the move has to keep, whatever
// the backend.

const nodeA = '7020f1bd19aabbccddeeff00112233445566778899aabbccddeeff0011223344';
const nodeB = 'afdad95d3a00112233445566778899aabbccddeeff00112233445566778899aa';
const contact1 =
    'b4004fff7b835c81b74e1e55a6adadff317a7cff5ff06a8adb4ca6cd71667e0c';
const contact2 =
    'da98e0127037b4db4264497a76eb997351b0c58c2158c1e22e2f7d4093865d39';

PathRecord record(int n, {bool flood = false, DateTime? at}) => PathRecord(
  hopCount: n,
  tripTimeMs: 1000 * n + 7,
  timestamp: at,
  wasFloodDiscovery: flood,
  pathBytes: List<int>.generate(n, (i) => 0x10 * n + i),
  successCount: n,
  failureCount: n ~/ 2,
  routeWeight: 1.0 + n / 10,
);

ContactPathHistory history(String contact, List<PathRecord> records) =>
    ContactPathHistory(contactPubKeyHex: contact, recentPaths: records);

DeliveryObservation observation(int n, {bool flood = false}) =>
    DeliveryObservation(
      contactKey: 'contact_$n',
      pathLength: n,
      messageBytes: 20 * n,
      secondsSinceLastRx: 60 * n,
      isFlood: flood,
      deliveryMs: 1500 + n,
      timestamp: DateTime.utc(2026, 9, 1, 10, n),
    );

Future<void> initPrefs([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  PrefsManager.reset();
  await PrefsManager.initialize();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => initPrefs());
  tearDown(PrefsManager.reset);

  StorageService forNode(String node) =>
      StorageService()..setPublicKeyHex = node;

  group('path history', () {
    test('a saved history is read back with every record field', () async {
      final storage = forNode(nodeA);
      final saved = history(contact1, [
        record(0, at: DateTime.utc(2026, 9, 1, 12)),
        record(2, flood: true, at: DateTime(2026, 9, 2, 8, 30, 15, 250)),
        record(3),
      ]);

      await storage.savePathHistory(contact1, saved);

      final loaded = await storage.loadPathHistory(contact1);
      expect(loaded, isNotNull);
      expect(loaded!.contactPubKeyHex, contact1);
      expect(loaded.toJson(), saved.toJson());
      expect(loaded.recentPaths.map((r) => r.hopCount), [0, 2, 3]);
      expect(loaded.mostRecent!.hopCount, 0);
      expect(loaded.fastest!.hopCount, 0);
    });

    test('a history is kept per node', () async {
      final a = forNode(nodeA);
      final b = forNode(nodeB);
      await a.savePathHistory(contact1, history(contact1, [record(1)]));

      expect(await b.loadPathHistory(contact1), isNull);

      await b.savePathHistory(contact1, history(contact1, [record(2)]));
      expect(
        (await a.loadPathHistory(contact1))!.recentPaths.single.hopCount,
        1,
      );
      expect(
        (await b.loadPathHistory(contact1))!.recentPaths.single.hopCount,
        2,
      );
    });

    test('a history stored before scoping serves every node until it saves '
        'its own', () async {
      await initPrefs({
        'path_history_$contact1': jsonEncode(
          history(contact1, [record(1)]).toJson(),
        ),
      });
      final a = forNode(nodeA);
      final b = forNode(nodeB);

      expect(
        (await a.loadPathHistory(contact1))!.recentPaths.single.hopCount,
        1,
      );
      expect(
        (await b.loadPathHistory(contact1))!.recentPaths.single.hopCount,
        1,
      );

      await a.savePathHistory(contact1, history(contact1, [record(2)]));

      expect(
        (await a.loadPathHistory(contact1))!.recentPaths.single.hopCount,
        2,
      );
      expect(
        (await b.loadPathHistory(contact1))!.recentPaths.single.hopCount,
        1,
      );
    });

    test('a store without a node writes the shared form', () async {
      final shared = StorageService();
      await shared.savePathHistory(contact1, history(contact1, [record(1)]));

      expect(
        (await shared.loadPathHistory(contact1))!.recentPaths.single.hopCount,
        1,
      );
      expect(
        (await forNode(nodeA).loadPathHistory(contact1))!
            .recentPaths
            .single
            .hopCount,
        1,
      );
    });

    test('clearing a contact removes its history in both forms', () async {
      await initPrefs({
        'path_history_$contact1': jsonEncode(
          history(contact1, [record(1)]).toJson(),
        ),
      });
      final a = forNode(nodeA);
      await a.savePathHistory(contact1, history(contact1, [record(2)]));
      await a.savePathHistory(contact2, history(contact2, [record(3)]));

      await a.clearPathHistory(contact1);

      expect(await a.loadPathHistory(contact1), isNull);
      expect(await forNode(nodeB).loadPathHistory(contact1), isNull);
      expect(
        (await a.loadPathHistory(contact2))!.recentPaths.single.hopCount,
        3,
      );
    });

    test('clearing all removes the histories of every node', () async {
      await initPrefs({
        'path_history_$contact1': jsonEncode(
          history(contact1, [record(1)]).toJson(),
        ),
      });
      final a = forNode(nodeA);
      final b = forNode(nodeB);
      await a.savePathHistory(contact2, history(contact2, [record(2)]));
      await b.savePathHistory(contact2, history(contact2, [record(3)]));

      await a.clearAllPathHistories();

      expect(await a.loadPathHistory(contact1), isNull);
      expect(await a.loadPathHistory(contact2), isNull);
      expect(await b.loadPathHistory(contact1), isNull);
      expect(await b.loadPathHistory(contact2), isNull);
    });

    test('an unreadable history reads as none', () async {
      await initPrefs({
        'path_history_7020f1bd19_$contact1': 'not json',
        'path_history_$contact2': '[1, 2, 3]',
      });
      expect(await forNode(nodeA).loadPathHistory(contact1), isNull);
      expect(await forNode(nodeA).loadPathHistory(contact2), isNull);
    });
  });

  group('delivery observations', () {
    test('observations are read back in order with their fields', () async {
      final saved = [
        observation(1),
        observation(2, flood: true),
        observation(3),
      ];
      await StorageService().saveDeliveryObservations(saved);

      final loaded = await StorageService().loadDeliveryObservations();
      expect(
        loaded.map((o) => o.toJson()).toList(),
        saved.map((o) => o.toJson()).toList(),
      );
    });

    test('they are shared by every node', () async {
      await forNode(nodeA).saveDeliveryObservations([observation(1)]);
      expect(await forNode(nodeB).loadDeliveryObservations(), hasLength(1));
    });

    test('nothing stored reads as an empty list, and clearing empties it',
        () async {
      final storage = StorageService();
      expect(await storage.loadDeliveryObservations(), isEmpty);
      await storage.saveDeliveryObservations([observation(1)]);
      await storage.clearDeliveryObservations();
      expect(await storage.loadDeliveryObservations(), isEmpty);
    });

    test('a save replaces the previous list', () async {
      final storage = StorageService();
      await storage.saveDeliveryObservations([observation(1), observation(2)]);
      await storage.saveDeliveryObservations([observation(3)]);
      expect(
        (await storage.loadDeliveryObservations()).map((o) => o.contactKey),
        ['contact_3'],
      );
    });
  });

  group('repeater passwords and login settings', () {
    test('a password is saved, found and removed; clearing removes all',
        () async {
      final storage = StorageService();
      await storage.saveRepeaterPassword('aa11', 'one');
      await storage.saveRepeaterPassword('bb22', 'two');

      expect(await storage.getRepeaterPassword('aa11'), 'one');
      expect(await storage.loadRepeaterPasswords(), {
        'aa11': 'one',
        'bb22': 'two',
      });

      await storage.saveRepeaterPassword('aa11', 'changed');
      expect(await storage.getRepeaterPassword('aa11'), 'changed');

      await storage.removeRepeaterPassword('aa11');
      expect(await storage.getRepeaterPassword('aa11'), isNull);
      expect(await storage.loadRepeaterPasswords(), {'bb22': 'two'});

      await storage.clearAllRepeaterPasswords();
      expect(await storage.loadRepeaterPasswords(), isEmpty);
    });

    test('passwords are shared by every node', () async {
      await forNode(nodeA).saveRepeaterPassword('aa11', 'one');
      expect(await forNode(nodeB).getRepeaterPassword('aa11'), 'one');
    });

    test('auto clock sync after login is remembered per repeater', () async {
      final storage = StorageService();
      expect(
        await storage.getRepeaterAutoClockSyncAfterLoginEnabled('aa11'),
        isFalse,
      );
      await storage.setRepeaterAutoClockSyncAfterLoginEnabled('aa11', true);
      await storage.setRepeaterAutoClockSyncAfterLoginEnabled('bb22', false);

      expect(
        await storage.getRepeaterAutoClockSyncAfterLoginEnabled('aa11'),
        isTrue,
      );
      expect(
        await storage.getRepeaterAutoClockSyncAfterLoginEnabled('bb22'),
        isFalse,
      );
      expect(
        await forNode(nodeB).getRepeaterAutoClockSyncAfterLoginEnabled('aa11'),
        isTrue,
      );
    });
  });
}
