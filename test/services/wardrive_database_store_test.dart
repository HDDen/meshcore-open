import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/wardrive_sample_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The database form of the wardrive store, and the move from preferences.
// The database needs a native sqlite3 the test host can load; when it
// cannot, every test here is skipped rather than failed.

MessageHistoryDatabase _memoryDatabase() =>
    MessageHistoryDatabase.withExecutor(NativeDatabase.memory());

Future<String?> _sqliteProblem() async {
  try {
    final database = _memoryDatabase();
    await database.customSelect('SELECT 1').get();
    await database.close();
    return null;
  } catch (error) {
    return 'sqlite3 is not available to this test host: $error';
  }
}

WardriveSample _sample(
  int n, {
  bool? pingSuccess = true,
  String publicKeyHex = 'AABBCCDD00112233',
}) {
  final at = DateTime.utc(2026, 9, 20, 12, 0, n);
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

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = await _sqliteProblem();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final tempDir = Directory.systemTemp.createTempSync('mco_wardrive_db_');
  const endpoint = 'https://example.test/api/samples';

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

  tearDown(() async {
    await MessageHistoryStorage.instance.resetForTesting();
    PrefsManager.reset();
  });

  Future<void> openStorage({MessageHistoryDatabase Function()? factory}) async {
    await MessageHistoryStorage.instance.resetForTesting();
    await MessageHistoryStorage.instance.initializeAndMigrate(
      databaseFactory: factory ?? _memoryDatabase,
    );
    expect(MessageHistoryStorage.instance.hasDatabase, isTrue);
  }

  group('database store', () {
    test('samples come back newest first by their own timestamp, one per id',
        () async {
      await openStorage();
      final store = WardriveSampleStore();
      expect(await store.add(_sample(1)), isTrue);
      expect(await store.add(_sample(3)), isTrue);
      expect(await store.add(_sample(2)), isTrue);
      expect(await store.add(_sample(2)), isFalse);

      expect(
        (await store.loadRecent()).map((s) => s.id),
        ['id_3', 'id_2', 'id_1'],
      );
      expect((await store.loadRecent(limit: 2)).map((s) => s.id), [
        'id_3',
        'id_2',
      ]);
      expect(await store.count(), 3);
      expect((await store.loadRecent()).first.toStorageJson(), _sample(3).toStorageJson());
      expect(
        PrefsManager.instance.containsKey('wardrive_samples_v1'),
        isFalse,
      );
    }, skip: skip);

    test('the cap keeps the newest samples', () async {
      await openStorage();
      final store = WardriveSampleStore();
      const cap = WardriveSampleStore.maxSamples;
      final payload = jsonEncode([
        for (var n = 1; n <= cap + 1; n++) _sample(n).toStorageJson(),
      ]);

      expect(await store.importJson(payload), cap + 1);

      expect(await store.count(), cap);
      expect((await store.loadRecent(limit: 1)).single.id, 'id_${cap + 1}');
      expect((await store.loadAllSamples()).last.id, 'id_2');
    }, skip: skip);

    test('an upload record dies with its sample', () async {
      await openStorage();
      final store = WardriveSampleStore();
      await store.add(_sample(1));
      await store.add(_sample(2));
      await store.markUploaded(endpoint, ['id_1', 'id_2']);
      expect(await store.pendingUpload(endpointUrl: endpoint), isEmpty);

      expect(await store.removeWhere((s) => s.tag == 1), 1);
      expect(await store.count(), 1);
      expect(await store.add(_sample(1)), isTrue);
      expect(
        (await store.pendingUpload(endpointUrl: endpoint)).map((s) => s.id),
        ['id_1'],
      );

      await store.clear();
      expect(await store.count(), 0);
      await store.add(_sample(2));
      expect(
        (await store.pendingUpload(endpointUrl: endpoint)).map((s) => s.id),
        ['id_2'],
      );
    }, skip: skip);

    test('pendingUpload leaves out what has no reading, what is ignored and '
        'what was sent to that site, newest first and limited', () async {
      await openStorage();
      final store = WardriveSampleStore();
      await store.add(_sample(1));
      await store.add(_sample(2, pingSuccess: null));
      await store.add(
        _sample(3, pingSuccess: false, publicKeyHex: 'EEFF001122334455'),
      );
      await store.add(_sample(4));
      await store.markUploaded(endpoint, ['id_4']);

      Future<List<String>> pending({
        String url = endpoint,
        bool includeUploaded = false,
        int? limit,
        Set<String> ignored = const {},
      }) async => (await store.pendingUpload(
        endpointUrl: url,
        includeUploaded: includeUploaded,
        limit: limit,
        ignoredRepeaterKeys: ignored,
      )).map((s) => s.id).toList();

      expect(await pending(), ['id_3', 'id_1']);
      expect(await pending(ignored: {'EEFF0011'}), ['id_1']);
      expect(await pending(includeUploaded: true), ['id_4', 'id_3', 'id_1']);
      expect(await pending(includeUploaded: true, limit: 1), ['id_4']);
      expect(await pending(url: 'https://other.test'), ['id_4', 'id_3', 'id_1']);
      // Marking twice is harmless.
      await store.markUploaded(endpoint, ['id_4', 'id_3']);
      expect(await pending(), ['id_1']);
    }, skip: skip);

    test('sessions keep the newest first, one per start time, capped',
        () async {
      await openStorage();
      final store = WardriveSampleStore();
      for (var n = 1; n <= 3; n++) {
        await store.addSession(_session(n));
      }
      await store.addSession(_session(2));

      expect((await store.loadSessions()).map((s) => s.startTime), [
        _session(3).startTime,
        _session(2).startTime,
        _session(1).startTime,
      ]);

      for (var n = 4; n <= WardriveSampleStore.maxSessions + 5; n++) {
        await store.addSession(_session(n));
      }
      final sessions = await store.loadSessions();
      expect(sessions.length, WardriveSampleStore.maxSessions);
      expect(sessions.first.startTime, _session(WardriveSampleStore.maxSessions + 5).startTime);
    }, skip: skip);

    test('export and import go through the database', () async {
      await openStorage();
      final store = WardriveSampleStore();
      await store.add(_sample(1));
      await store.addSession(_session(1));
      final exported = await store.exportJson(activeSession: _session(9));

      await store.clear();
      expect(await store.importJson(exported), 1);
      expect((await store.loadRecent()).single.toJson(), _sample(1).toJson());
      expect((await store.loadSessions()).map((s) => s.startTime), [
        _session(9).startTime,
        _session(1).startTime,
      ]);
      expect(await store.importJson(exported), 0);
    }, skip: skip);
  });

  group('move from preferences', () {
    test('the three keys move into the tables once; unreadable rows are '
        'skipped and records of missing samples dropped', () async {
      SharedPreferences.setMockInitialValues({
        'wardrive_samples_v1': [
          jsonEncode(_sample(1).toStorageJson()),
          'garbage',
          jsonEncode(_sample(2).toStorageJson()),
        ],
        'wardrive_sessions_v1': [jsonEncode(_session(1).toJson())],
        'wardrive_uploaded_samples_v1': jsonEncode({
          endpoint: ['id_1', 'gone'],
        }),
        'wardrive_ignored_repeaters_v1': ['FFEE'],
      });
      PrefsManager.reset();
      await PrefsManager.initialize();

      final file = File('${tempDir.path}${Platform.pathSeparator}move.sqlite');
      MessageHistoryDatabase fileDatabase() =>
          MessageHistoryDatabase.withExecutor(NativeDatabase(file));

      await openStorage(factory: fileDatabase);
      final store = WardriveSampleStore();
      expect((await store.loadRecent()).map((s) => s.id), ['id_2', 'id_1']);
      expect(
        (await store.loadSessions()).single.startTime,
        _session(1).startTime,
      );
      expect(
        (await store.pendingUpload(endpointUrl: endpoint)).map((s) => s.id),
        ['id_2'],
      );
      final prefs = PrefsManager.instance;
      expect(prefs.containsKey('wardrive_samples_v1'), isFalse);
      expect(prefs.containsKey('wardrive_sessions_v1'), isFalse);
      expect(prefs.containsKey('wardrive_uploaded_samples_v1'), isFalse);
      expect(prefs.getStringList('wardrive_ignored_repeaters_v1'), ['FFEE']);

      // Opened again: nothing left to move, the rows stay.
      await openStorage(factory: fileDatabase);
      expect(await WardriveSampleStore().count(), 2);
      expect(
        (await WardriveSampleStore().pendingUpload(endpointUrl: endpoint))
            .map((s) => s.id),
        ['id_2'],
      );
    }, skip: skip);

    test('nothing to move leaves the tables empty', () async {
      await openStorage();
      expect(await WardriveSampleStore().count(), 0);
      expect(await WardriveSampleStore().loadSessions(), isEmpty);
    }, skip: skip);
  });
}
