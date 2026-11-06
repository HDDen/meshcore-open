import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/delivery_observation.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/services/timeout_prediction_service.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

import '../support/history_test_environment.dart';

const _commonKeys = [
  'contact_key',
  'path_length',
  'message_bytes',
  'is_flood',
  'delivery_ms',
  'timestamp',
];

// Fixed, full-rank synthetic data for the current and reduced feature sets.
// Old rows may contain the optional RX field or predate it entirely.
List<Map<String, dynamic>> _legacyCorpus() {
  final rows = <Map<String, dynamic>>[];
  void add(int hops, int bytes, {bool flood = false}) {
    final index = rows.length;
    rows.add({
      'contact_key': 'synthetic_${index % 3}',
      'path_length': hops,
      'message_bytes': bytes,
      if (index.isEven) 'seconds_since_last_rx': (index * 7) % 13,
      'is_flood': flood,
      'delivery_ms': 1800 + hops * 850 + bytes * 11 + (flood ? 2500 : 0),
      'timestamp': DateTime.utc(2026, 1, 2, 0, 0, index).toIso8601String(),
    });
  }

  for (final hops in [0, 2, 4]) {
    for (final bytes in [20, 50, 80]) {
      add(hops, bytes);
    }
  }
  for (final bytes in [20, 50, 80]) {
    add(0, bytes, flood: true);
  }
  return rows;
}

void _expectCommonFields(
  DeliveryObservation observation,
  Map<String, dynamic> source,
) {
  final serialized = observation.toJson();
  for (final key in _commonKeys) {
    expect(serialized[key], source[key], reason: 'Preserve $key');
  }
  expect(
    observation.timestamp.isAtSameMomentAs(DateTime.parse(source['timestamp'] as String)),
    isTrue,
  );
}

Future<TimeoutPredictionService> _loadModel(StorageService storage) async {
  final model = TimeoutPredictionService(storage);
  addTearDown(model.dispose);
  await model.initialize();
  return model;
}

// Only persistence is synthetic here; fitting and prediction use the real model.
class _ObservationStorage extends StorageService {
  _ObservationStorage(this.rows);

  final List<DeliveryObservation> rows;
  List<Map<String, dynamic>>? saved;

  @override
  Future<List<DeliveryObservation>> loadDeliveryObservations() async =>
      List<DeliveryObservation>.of(rows);

  @override
  Future<void> saveDeliveryObservations(List<DeliveryObservation> observations) async {
    saved = observations.map((observation) => observation.toJson()).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final environment = HistoryTestEnvironment();
  final history = MessageHistoryStorage.instance;
  late bool previousSuspended;

  setUp(() async {
    previousSuspended = TimeoutPredictionService.recordingSuspended;
    TimeoutPredictionService.recordingSuspended = false;
    await environment.setUp();
  });
  tearDown(() async {
    TimeoutPredictionService.recordingSuspended = previousSuspended;
    await environment.tearDown();
  });

  test('U12b baseline: legacy JSON preserves common fields with optional RX data', () {
    for (final row in _legacyCorpus()) {
      final decoded = DeliveryObservation.fromJson(row);
      _expectCommonFields(decoded, row);
    }
    final beforeFloodField = Map<String, dynamic>.from(_legacyCorpus().first)
      ..remove('is_flood')
      ..remove('seconds_since_last_rx');
    expect(DeliveryObservation.fromJson(beforeFloodField).isFlood, isFalse);
  });

  test('U12b baseline: SQL startup trains on legacy rows without rewriting them', () async {
    final encoded = _legacyCorpus().map(jsonEncode).toList();
    await history.replaceDeliveryObservations(encoded);
    final model = await _loadModel(StorageService());
    expect(model.observationCount, encoded.length);
    expect(model.hasModel, isTrue);
    final direct0 = model.predictTimeout(pathLength: 0, messageBytes: 50);
    final direct4 = model.predictTimeout(pathLength: 4, messageBytes: 50);
    final flood = model.predictTimeout(pathLength: -1, messageBytes: 50);
    expect(direct0, isNotNull);
    expect(direct4, isNotNull);
    expect(flood, isNotNull);
    expect(direct0!, greaterThan(0));
    expect(direct4!, greaterThan(direct0));
    expect(flood!, greaterThan(0));
    expect(await history.loadDeliveryObservations(), encoded);
  });

  test('U12b baseline: insufficient stored samples retain the timeout fallback', () async {
    final encoded = _legacyCorpus()
        .take(TimeoutPredictionService.minObservations - 1)
        .map(jsonEncode)
        .toList();
    await history.replaceDeliveryObservations(encoded);
    final model = await _loadModel(StorageService());
    expect(model.observationCount, encoded.length);
    expect(model.hasModel, isFalse);
    expect(model.predictTimeout(pathLength: 2, messageBytes: 50), isNull);
    expect(await history.loadDeliveryObservations(), encoded);
  });

  test('U12b baseline: preferences fallback reads legacy rows without migration', () async {
    // Exercise the existing non-SQL branch, with the same synthetic prefs.
    await history.resetForTesting();
    final rows = _legacyCorpus();
    final encoded = jsonEncode(rows);
    await PrefsManager.instance.setString('delivery_observations', encoded);
    final model = await _loadModel(StorageService());
    expect(history.hasDatabase, isFalse);
    expect(model.observationCount, rows.length);
    expect(model.hasModel, isTrue);
    expect(PrefsManager.instance.getString('delivery_observations'), encoded);
  });

  test('U12b baseline: malformed rows do not erase valid SQL observations', () async {
    final valid = _legacyCorpus();
    final encoded = [
      jsonEncode(valid.first),
      'not json',
      jsonEncode({'contact_key': 'broken'}),
      ...valid.skip(1).map(jsonEncode),
    ];
    await history.replaceDeliveryObservations(encoded);
    final storage = StorageService();
    final loaded = await storage.loadDeliveryObservations();
    expect(loaded, hasLength(valid.length));
    for (var i = 0; i < valid.length; i++) {
      _expectCommonFields(loaded[i], valid[i]);
    }
    final model = await _loadModel(storage);
    expect(model.observationCount, valid.length);
    expect(model.hasModel, isTrue);
    expect(await history.loadDeliveryObservations(), encoded);
  });

  for (final reducedWrites in [false, true]) {
    test('U12b baseline: legacy samples round-trip with reduced writes=$reducedWrites', () async {
      history.setReduceDeliveryObservationWrites(reducedWrites);
      final rows = _legacyCorpus();
      await history.replaceDeliveryObservations(rows.map(jsonEncode).toList());
      final storage = StorageService();
      final loaded = await storage.loadDeliveryObservations();
      await storage.saveDeliveryObservations(loaded);
      final reopened = await StorageService().loadDeliveryObservations();
      expect(reopened, hasLength(rows.length));
      for (var i = 0; i < rows.length; i++) {
        _expectCommonFields(reopened[i], rows[i]);
      }
    });
  }

  test('U12b baseline: suspended recording preserves training data and SQL rows', () async {
    final encoded = _legacyCorpus().map(jsonEncode).toList();
    await history.replaceDeliveryObservations(encoded);
    final model = await _loadModel(StorageService());
    TimeoutPredictionService.recordingSuspended = true;
    model.recordObservation(
      contactKey: 'review-only',
      pathLength: 3,
      messageBytes: 90,
      tripTimeMs: 123,
    );
    expect(model.observationCount, encoded.length);
    expect(await history.loadDeliveryObservations(), encoded);
  });

  test('U12b: legacy RX metadata is ignored rather than required or re-emitted', () {
    for (final oldValue in [0, 600, 'obsolete metadata']) {
      final row = Map<String, dynamic>.from(_legacyCorpus().first)
        ..['seconds_since_last_rx'] = oldValue;
      final decoded = DeliveryObservation.fromJson(row);
      _expectCommonFields(decoded, row);
      expect(decoded.toJson().containsKey('seconds_since_last_rx'), isFalse);
    }
  });

  test('U12b: legacy RX values cannot change the learned timeout', () async {
    // Make the old RX feature strongly correlated with RTT, independently of
    // bytes. The old model would predict at RX=0 even for that legacy corpus.
    final rows = List<Map<String, dynamic>>.generate(20, (i) {
      final bytes = 20 + i * 2;
      final rx = i.isOdd ? 60 : 0;
      return {
        'contact_key': 'synthetic',
        'path_length': 2,
        'message_bytes': bytes,
        'seconds_since_last_rx': rx,
        'is_flood': false,
        'delivery_ms': 1000 + bytes * 5 + rx * 20,
        'timestamp': DateTime.utc(2026, 1, 2, 0, 0, i).toIso8601String(),
      };
    });
    final withoutRx = rows.map((row) => Map<String, dynamic>.from(row)
      ..remove('seconds_since_last_rx')).toList();
    final legacyModel = await _loadModel(_ObservationStorage(
      rows.map(DeliveryObservation.fromJson).toList(),
    ));
    final plainModel = await _loadModel(_ObservationStorage(
      withoutRx.map(DeliveryObservation.fromJson).toList(),
    ));
    expect(legacyModel.hasModel, isTrue);
    expect(plainModel.hasModel, isTrue);
    for (final bytes in [20, 40, 58]) {
      final legacy = legacyModel.predictTimeout(pathLength: 2, messageBytes: bytes);
      final plain = plainModel.predictTimeout(pathLength: 2, messageBytes: bytes);
      expect(legacy, isNotNull);
      expect(plain, isNotNull);
      expect(legacy!, closeTo(plain!, 1));
    }
  });

  test('U12b: new recorded observations persist without an RX field', () {
    final storage = _ObservationStorage([]);
    final model = TimeoutPredictionService(storage);
    try {
      model.recordObservation(
        contactKey: 'new-delivery',
        pathLength: -1,
        messageBytes: 42,
        tripTimeMs: 700,
      );
      expect(model.observationCount, 1);
    } finally {
      // Dispose flushes the existing debounced save and cancels its timer.
      model.dispose();
    }
    final row = storage.saved!.single;
    expect(row['contact_key'], 'new-delivery');
    expect(row['path_length'], 0);
    expect(row['is_flood'], isTrue);
    expect(row['message_bytes'], 42);
    expect(row['delivery_ms'], 700);
    expect(row.containsKey('seconds_since_last_rx'), isFalse);
  });
}
