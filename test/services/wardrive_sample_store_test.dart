import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/wardrive_ignore_store.dart';
import 'package:meshcore_open/services/wardrive_sample_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Invariants of the wardrive store as it is kept in preferences: the order
// and cap of samples and sessions, the identity an import de-duplicates by,
// the export format shared with the standalone wardrive app, and the raw
// preference shapes, which are exactly what a migration to the database has
// to read. Pinned before the store moves.

WardriveSample _sample(
  int n, {
  bool? pingSuccess = true,
  String publicKeyHex = 'AABBCCDD00112233',
  DateTime? timestamp,
}) {
  final at = timestamp ?? DateTime.utc(2026, 9, 20, 12, 0, n);
  return WardriveSample(
    id: 'id_$n',
    timestamp: at,
    phoneLocationAt: at,
    latitude: 55.0 + n * 1e-4,
    longitude: 37.0,
    tag: n,
    nodeType: 2,
    publicKeyHex: publicKeyHex,
    path: publicKeyHex,
    geohash: 'ucfv0j8b',
    snr: 5.5,
    rssi: -90,
    pingSuccess: pingSuccess,
    responseTimeMs: 100,
    ductingRisk: null,
    source: null,
  );
}

WardriveSession _session(int n) => WardriveSession(
  startTime: DateTime.utc(2026, 9, 20, 10, n),
  endTime: DateTime.utc(2026, 9, 20, 11, n),
  distanceMeters: 0,
  sampleCount: n,
  pingCount: n,
  successCount: n,
  notes: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final tempDir = Directory.systemTemp.createTempSync('mco_wardrive_store_');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  group('samples', () {
    test('add keeps the newest first and the raw preference holds storage JSON',
        () async {
      final store = WardriveSampleStore();
      final first = _sample(1);
      final second = _sample(2, pingSuccess: false);
      await store.add(first);
      await store.add(second);

      expect(store.loadRecent().map((s) => s.id), ['id_2', 'id_1']);
      expect(store.count, 2);

      final raw = PrefsManager.instance.getStringList('wardrive_samples_v1')!;
      expect(raw.length, 2);
      expect(jsonDecode(raw.first), second.toStorageJson());
      expect(jsonDecode(raw.last), first.toStorageJson());
      // The storage shape carries what the shared export leaves out.
      expect(second.toStorageJson().keys, containsAll(['phoneLocationAt', 'tag', 'nodeType', 'publicKeyHex']));
      expect(second.toJson().keys, isNot(contains('publicKeyHex')));
    });

    test('the store keeps at most 3000 samples, dropping the oldest', () async {
      final store = WardriveSampleStore();
      for (var n = 1; n <= 3001; n++) {
        await store.add(_sample(n));
      }
      expect(store.count, 3000);
      expect(store.loadRecent(limit: 1).single.id, 'id_3001');
      expect(store.loadAllSamples().last.id, 'id_2');
    });

    test('loadRecent honours its limit and skips unreadable rows', () async {
      final store = WardriveSampleStore();
      await PrefsManager.instance.setStringList('wardrive_samples_v1', [
        jsonEncode(_sample(3).toStorageJson()),
        'not json',
        jsonEncode({'timestamp': 'not a date', 'lat': 1, 'lon': 2}),
        jsonEncode(_sample(1).toStorageJson()),
      ]);

      expect(store.loadRecent().map((s) => s.id), ['id_3', 'id_1']);
      expect(store.loadRecent(limit: 1).map((s) => s.id), ['id_3']);
    });

    test('removeWhere drops the matching samples and reports how many',
        () async {
      final store = WardriveSampleStore();
      for (var n = 1; n <= 3; n++) {
        await store.add(_sample(n));
      }

      expect(await store.removeWhere((s) => s.tag == 2), 1);
      expect(store.loadRecent().map((s) => s.id), ['id_3', 'id_1']);
      expect(await store.removeWhere((s) => s.tag == 9), 0);
      expect(store.count, 2);
    });

    test('clear forgets samples and sessions but not the ignore list',
        () async {
      final store = WardriveSampleStore();
      await store.add(_sample(1));
      await store.addSession(_session(1));
      await WardriveIgnoreStore().setIgnoredRepeater('AABBCCDD00112233', true);

      await store.clear();

      expect(store.count, 0);
      expect(store.loadRecent(), isEmpty);
      expect(store.loadSessions(), isEmpty);
      expect(WardriveIgnoreStore().loadIgnoredRepeaters(), {
        'AABBCCDD00112233',
      });
    });
  });

  group('sessions', () {
    test('keep the newest first, capped at 200, and the raw shape', () async {
      final store = WardriveSampleStore();
      for (var n = 0; n < 201; n++) {
        await store.addSession(_session(n));
      }
      final sessions = store.loadSessions();
      expect(sessions.length, 200);
      expect(sessions.first.startTime, _session(200).startTime);
      expect(sessions.last.startTime, _session(1).startTime);

      final raw = PrefsManager.instance.getStringList('wardrive_sessions_v1')!;
      expect(jsonDecode(raw.first), _session(200).toJson());
    });
  });

  group('import and export', () {
    test('importJson adds only unknown ids, newest first, and merges sessions '
        'by start time', () async {
      final store = WardriveSampleStore();
      await store.add(_sample(1));
      await store.addSession(_session(1));

      final payload = jsonEncode({
        '_format': 'meshcore_wardrive_data',
        '_version': 1,
        'samples': [
          _sample(1).toJson(),
          _sample(5).toJson(),
          _sample(6).toJson(),
        ],
        'sessions': [_session(1).toJson(), _session(2).toJson()],
      });

      expect(await store.importJson(payload), 2);
      expect(store.loadRecent().map((s) => s.id), ['id_5', 'id_6', 'id_1']);
      expect(
        store.loadSessions().map((s) => s.startTime),
        [_session(2).startTime, _session(1).startTime],
      );

      expect(await store.importJson(payload), 0);
      expect(store.count, 3);
      expect(store.loadSessions().length, 2);
    });

    test('importJson takes a bare list and refuses anything else', () async {
      final store = WardriveSampleStore();
      expect(await store.importJson(jsonEncode([_sample(7).toJson()])), 1);
      expect(store.loadRecent().single.id, 'id_7');
      await expectLater(
        () => store.importJson(jsonEncode({'samples': 'nope'})),
        throwsFormatException,
      );
    });

    test('exportJson has the shared format, filters ignored keys and puts the '
        'active session first', () async {
      final store = WardriveSampleStore();
      await store.add(_sample(1, publicKeyHex: 'AABBCCDD00112233'));
      await store.add(_sample(2, publicKeyHex: 'EEFF001122334455'));
      await store.addSession(_session(1));

      final decoded =
          jsonDecode(
                store.exportJson(
                  activeSession: _session(9),
                  ignoredRepeaterKeys: {'AABBCCDD'},
                ),
              )
              as Map<String, dynamic>;

      expect(decoded['_format'], 'meshcore_wardrive_data');
      expect(decoded['_version'], 1);
      final samples = decoded['samples'] as List;
      expect(samples.map((s) => s['id']), ['id_2']);
      expect(samples.single, _sample(2, publicKeyHex: 'EEFF001122334455').toJson());
      final sessions = decoded['sessions'] as List;
      expect(
        sessions.map((s) => s['startTime']),
        [_session(9).startTime.toIso8601String(), _session(1).startTime.toIso8601String()],
      );

      // An active session already stored is not listed twice.
      final again = jsonDecode(store.exportJson(activeSession: _session(1)))
          as Map<String, dynamic>;
      expect((again['sessions'] as List).length, 1);
    });

    test('a sample survives the shared export shape, tag and type excepted',
        () {
      final original = _sample(4);
      final restored = WardriveSample.fromJson(original.toJson())!;

      expect(restored.id, original.id);
      expect(restored.timestamp, original.timestamp);
      expect(restored.latitude, original.latitude);
      expect(restored.longitude, original.longitude);
      expect(restored.path, original.path);
      expect(restored.publicKeyHex, original.path);
      expect(restored.geohash, original.geohash);
      expect(restored.snr, original.snr);
      expect(restored.rssi, original.rssi);
      expect(restored.pingSuccess, original.pingSuccess);
      expect(restored.responseTimeMs, original.responseTimeMs);
      // Not part of the shared shape.
      expect(restored.tag, 0);
      expect(restored.nodeType, 0);
      expect(restored.phoneLocationAt, isNull);

      final stored = WardriveSample.fromJson(original.toStorageJson())!;
      expect(stored.tag, original.tag);
      expect(stored.nodeType, original.nodeType);
      expect(stored.phoneLocationAt, original.phoneLocationAt);
    });

    test('fromJson reads the legacy open-wardrive shape and derives an id',
        () {
      final legacy = WardriveSample.fromJson({
        'latitude': 55.75,
        'longitude': 37.61,
        'timestamp': '2026-09-20T12:00:00.000Z',
        'publicKeyHex': 'aabbccdd00112233',
      })!;
      expect(legacy.pingSuccess, isTrue);
      expect(legacy.path, 'aabbccdd00112233');
      expect(legacy.geohash.length, 8);
      expect(
        legacy.id,
        '${DateTime.utc(2026, 9, 20, 12).millisecondsSinceEpoch}_00000000_${legacy.geohash}',
      );

      final modern = WardriveSample.fromJson({
        'lat': 55.75,
        'lon': 37.61,
        'timestamp': '2026-09-20T12:00:00.000Z',
        'path': 'AABB',
      })!;
      expect(modern.pingSuccess, isNull);

      expect(
        WardriveSample.fromJson({'lat': 1, 'lon': 2, 'timestamp': 'nope'}),
        isNull,
      );
    });

    test('discovery samples get the id the shared app derives', () {
      final at = DateTime.utc(2026, 9, 20, 12);
      final hit = WardriveSample.fromDiscovery(
        timestamp: at,
        phoneLocationAt: at,
        latitude: 55.75,
        longitude: 37.61,
        tag: 0xABCD,
        nodeType: 2,
        publicKeyHex: 'aabbccdd00112233',
        snr: 4,
        rssi: -100,
        responseTimeMs: 250,
      );
      expect(hit.id, '${at.millisecondsSinceEpoch}_0000abcd_${hit.geohash}');
      expect(hit.path, 'AABBCCDD00112233');
      expect(hit.pingSuccess, isTrue);

      final miss = WardriveSample.fromDiscoveryFailure(
        timestamp: at,
        phoneLocationAt: at,
        latitude: 55.75,
        longitude: 37.61,
        tag: 0xABCD,
      );
      expect(miss.id, hit.id);
      expect(miss.pingSuccess, isFalse);
      expect(miss.publicKeyHex, isEmpty);
      expect(miss.path, isNull);
    });
  });

  group('ignore list', () {
    test('matches by prefix from eight characters and stores sorted keys',
        () async {
      expect(WardriveIgnoreStore.keysMatch('AABBCCDDEE', 'aabbccddee0011'), isTrue);
      expect(WardriveIgnoreStore.keysMatch('AABBCC', 'aabbccddee0011'), isFalse);
      expect(WardriveIgnoreStore.keysMatch('AABBCC', 'aabbcc'), isTrue);
      expect(WardriveIgnoreStore.keysMatch('', 'aabbcc'), isFalse);

      final store = WardriveIgnoreStore();
      await store.setIgnoredRepeater('ffee', true);
      await store.setIgnoredRepeater(' aabb ', true);
      expect(
        PrefsManager.instance.getStringList('wardrive_ignored_repeaters_v1'),
        ['AABB', 'FFEE'],
      );
      await store.setIgnoredRepeater('AABB', false);
      expect(store.loadIgnoredRepeaters(), {'FFEE'});
      expect(
        WardriveIgnoreStore.containsMatchingKey({'FFEE0011'}, 'ffee00112233'),
        isTrue,
      );
    });
  });
}
