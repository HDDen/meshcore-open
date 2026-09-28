import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mco_service/mco_service.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/storage/contact_location_estimate_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What the store of estimated node positions promises, pinned before the
// connector stops clearing every located contact on every save. The map
// computes an estimate for a node without coordinates and stores it; a node
// with coordinates stores its real position and never an estimate; clearing
// an estimate keeps the row, its name and its real position, and touches no
// other row. The table lives in the application database, so the tests open
// one in memory and skip on a host without a native sqlite3. The last test
// is the change: a clear of a key that holds no estimate leaves its row as
// it was, its `updated_at_ms` included.

const int _epochMs = 1700000000000;

List<int> _key(int first) =>
    List<int>.generate(32, (i) => i == 0 ? first : (i * 7 + first) & 0xFF);

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

McoContactLocationCandidate _candidate(
  List<int> key,
  String name, {
  double? latitude,
  double? longitude,
}) => McoContactLocationCandidate(
  publicKey: key,
  name: name,
  contactType: advTypeRepeater,
  pathBytes: const [],
  lastSeen: DateTime.fromMillisecondsSinceEpoch(_epochMs),
  latitude: latitude,
  longitude: longitude,
);

McoEstimatedContactLocation _estimate(List<int> key, String name) =>
    McoEstimatedContactLocation(
      publicKeyHex: _hex(key),
      name: name,
      contactType: advTypeRepeater,
      latitude: 55.7,
      longitude: 37.6,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(_epochMs),
      anchorPublicKeys: [_key(9)],
      anchorLatitudes: const [55.8],
      anchorLongitudes: const [37.5],
      highConfidence: true,
    );

Future<String?> _sqliteProblem() async {
  try {
    final database = MessageHistoryDatabase.withExecutor(
      NativeDatabase.memory(),
    );
    await database.customSelect('SELECT 1').get();
    await database.close();
    return null;
  } catch (error) {
    return 'sqlite3 is not available to this test host: $error';
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = await _sqliteProblem();
  final store = ContactLocationEstimateStore();
  final alice = _key(2);
  final bob = _key(3);

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await MessageHistoryStorage.instance.resetForTesting();
    await MessageHistoryStorage.instance.initializeAndMigrate(
      databaseFactory: () =>
          MessageHistoryDatabase.withExecutor(NativeDatabase.memory()),
    );
  });

  tearDown(() async {
    await MessageHistoryStorage.instance.resetForTesting();
    PrefsManager.reset();
  });

  /// Stores an estimate for [key], a node the map found no coordinates for.
  Future<void> plant(List<int> key, String name) => store.saveContactLocations(
    candidates: [_candidate(key, name)],
    estimates: [_estimate(key, name)],
    clearEstimateKeys: const [],
  );

  Future<List<ContactLocationCacheRecord>> rows() =>
      MessageHistoryStorage.instance.loadContactLocationCache();

  group('what the map stores', () {
    test('an estimate of a node without coordinates is read back whole',
        () async {
      await plant(alice, 'Alice');

      final estimate = (await store.loadEstimates()).single;
      expect(estimate.publicKeyHex, _hex(alice));
      expect(estimate.name, 'Alice');
      expect(estimate.contactType, advTypeRepeater);
      expect(estimate.latitude, 55.7);
      expect(estimate.longitude, 37.6);
      expect(estimate.updatedAt.millisecondsSinceEpoch, _epochMs);
      expect(estimate.anchorPublicKeys, [_key(9)]);
      expect(estimate.anchorLatitudes, [55.8]);
      expect(estimate.anchorLongitudes, [37.5]);
      expect(estimate.highConfidence, isTrue);
      expect(estimate.isPrefixOnly, isFalse);
    });

    test('a node with coordinates keeps its real position and no estimate',
        () async {
      await store.saveContactLocations(
        candidates: [_candidate(bob, 'Bob', latitude: 55.1, longitude: 37.1)],
        estimates: [_estimate(bob, 'Bob')],
        clearEstimateKeys: const [],
      );

      expect(await store.loadEstimates(), isEmpty);
      final row = (await rows()).single;
      expect(row.publicKeyHex, _hex(bob));
      expect(row.realLatitude, 55.1);
      expect(row.realLongitude, 37.1);
      expect(row.estimatedLatitude, isNull);
      expect(row.estimatedLongitude, isNull);
      expect(row.highConfidence, isFalse);
    });

    test('coordinates that arrive for an estimated node replace the estimate '
        'with the real position', () async {
      await plant(alice, 'Alice');

      await store.saveContactLocations(
        candidates: [
          _candidate(alice, 'Alice', latitude: 55.2, longitude: 37.2),
        ],
        estimates: const [],
        clearEstimateKeys: const [],
      );

      expect(await store.loadEstimates(), isEmpty);
      final row = (await rows()).single;
      expect(row.realLatitude, 55.2);
      expect(row.estimatedLatitude, isNull);
      expect(row.anchorPublicKeysJson, '[]');
    });
  }, skip: skip);

  group('clearing', () {
    test('clearing an estimate keeps the row and drops the anchors', () async {
      await plant(alice, 'Alice');

      await store.clearEstimatesForKeys([_hex(alice)]);

      expect(await store.loadEstimates(), isEmpty);
      final row = (await rows()).single;
      expect(row.publicKeyHex, _hex(alice));
      expect(row.name, 'Alice');
      expect(row.estimatedLatitude, isNull);
      expect(row.estimatedLongitude, isNull);
      expect(row.anchorPublicKeysJson, '[]');
      expect(row.anchorLatitudesJson, '[]');
      expect(row.anchorLongitudesJson, '[]');
      expect(row.highConfidence, isFalse);
    });

    test('keys are matched without regard to case', () async {
      await plant(alice, 'Alice');

      await store.clearEstimatesForKeys([_hex(alice).toUpperCase()]);

      expect(await store.loadEstimates(), isEmpty);
    });

    test('clearing touches only the keys named', () async {
      await plant(alice, 'Alice');
      await plant(bob, 'Bob');

      await store.clearEstimatesForKeys([_hex(bob), _hex(_key(4)), '']);

      final kept = (await store.loadEstimates()).single;
      expect(kept.publicKeyHex, _hex(alice));
      expect(kept.latitude, 55.7);
      expect(await rows(), hasLength(2));
    });

    test('clearing nothing is a no-op', () async {
      await plant(alice, 'Alice');

      await store.clearEstimatesForKeys(const []);

      expect(await store.loadEstimates(), hasLength(1));
    });

    test('clearing a key whose estimate is already gone leaves its row '
        'untouched', () async {
      // A located node's row carries the moment of the estimate it was
      // handed, and no estimate.
      await store.saveContactLocations(
        candidates: [_candidate(bob, 'Bob', latitude: 55.1, longitude: 37.1)],
        estimates: [_estimate(bob, 'Bob')],
        clearEstimateKeys: const [],
      );
      await plant(alice, 'Alice');

      await store.clearEstimatesForKeys([_hex(alice), _hex(bob)]);

      final byKey = {
        for (final row in await rows()) row.publicKeyHex: row,
      };
      expect(byKey[_hex(bob)]!.updatedAtMs, _epochMs);
      expect(byKey[_hex(bob)]!.realLatitude, 55.1);
      expect(byKey[_hex(alice)]!.estimatedLatitude, isNull);
      expect(
        byKey[_hex(alice)]!.updatedAtMs,
        greaterThan(_epochMs),
        reason: 'a dropped estimate stamps its row with the moment',
      );
    });
  }, skip: skip);
}
