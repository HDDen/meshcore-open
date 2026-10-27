import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/delivery_observation_power_binding.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('Synthetic preferences without a directory');
  }
}

List<String> _values(int offset, [int length = 16]) =>
    List.generate(length, (i) => jsonEncode({'sequence': i + offset}));

Future<String?> _sqliteProblem() async {
  final database = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
  try {
    await database.customSelect('SELECT 1').get();
    return null;
  } catch (error) {
    return 'sqlite3 is not available to this test host: $error';
  } finally {
    try {
      await database.close();
    } catch (_) {
      // Executor мог не открыться на машине без SQLite.
    }
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sqliteProblem = await _sqliteProblem();
  const timeout = Timeout(Duration(seconds: 30));
  final storage = MessageHistoryStorage.instance;
  late MessageHistoryDatabase database;
  late AppSettingsService settings;
  late DeliveryObservationPowerBinding binding;
  late PathProviderPlatform originalPaths;

  setUpAll(() {
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
  });
  tearDownAll(() { PathProviderPlatform.instance = originalPaths; });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await storage.resetForTesting();
    database = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
    await storage.initializeAndMigrate(databaseFactory: () => database);
    settings = AppSettingsService();
    binding = DeliveryObservationPowerBinding(
      settings: settings, apply: storage.setReduceDeliveryObservationWrites,
    );
  });
  tearDown(() async {
    binding.dispose();
    settings.dispose();
    await storage.resetForTesting();
    PrefsManager.reset();
  });

  Future<int> changes() async {
    final row = await database.customSelect('SELECT total_changes() AS n').getSingle();
    return row.read<int>('n');
  }

  for (final enabled in [false, true]) {
    for (final length in [16, 100]) {
      for (final sliding in [false, true]) {
        test('SQLite row changes enabled=$enabled size=$length sliding=$sliding', () async {
          await settings.setReduceDeliveryObservationWrites(enabled);
          await settings.setPowerSavingProfile(PowerSavingProfile.custom);
          await storage.replaceDeliveryObservations(_values(0, length));
          final before = await changes();
          for (var i = 0; i < 8; i++) {
            final next = _values(sliding ? i + 1 : 0, length);
            await storage.replaceDeliveryObservations(next);
            expect(await storage.loadDeliveryObservations(), next);
          }
          final rows = await changes() - before;
          expect(rows, enabled ? (sliding ? 16 : 0) : 8 * length * 2);
          debugPrint('[DeliveryObservationSQLite] enabled=$enabled size=$length '
              'sliding=$sliding saves=8 changedRows=$rows; not energy or commits');
        }, skip: sqliteProblem, timeout: timeout);
      }
    }
  }

  test('only expired rows are removed and retained ids/order/duplicates survive', () async {
    await database.replaceDeliveryObservations(['A', 'B', 'B', 'C']);
    final before = await database.customSelect(
      'SELECT id FROM delivery_observations ORDER BY id',
    ).get();
    await database.writeNodeState(nodeKey: 'sentinel', name: 'keep', value: 'unchanged');
    await database.replaceDeliveryObservations(['B', 'B', 'C', 'D'], reduceWrites: true);
    final after = await database.customSelect(
      'SELECT id FROM delivery_observations ORDER BY id',
    ).get();
    expect(after.take(3).map((r) => r.read<int>('id')),
        before.skip(1).map((r) => r.read<int>('id')));
    expect(await database.readDeliveryObservations(), ['B', 'B', 'C', 'D']);
    expect(await database.readNodeState('sentinel', 'keep'), 'unchanged');
    await database.replaceDeliveryObservations([], reduceWrites: true);
    expect(await database.readDeliveryObservations(), isEmpty);
  }, skip: sqliteProblem, timeout: timeout);

  for (final enabled in [false, true]) {
    test('insert failure rolls back deletions and earlier inserts, enabled=$enabled', () async {
      await database.replaceDeliveryObservations(['A', 'B']);
      await database.customStatement('''
CREATE TEMP TRIGGER reject_observation BEFORE INSERT ON delivery_observations
WHEN NEW.observation_json = 'reject'
BEGIN SELECT RAISE(ABORT, 'synthetic_observation_reject'); END
''');
      await expectLater(
        database.replaceDeliveryObservations(['B', 'ok', 'reject'], reduceWrites: enabled),
        throwsA(predicate<Object>((error) => error.toString().contains('synthetic_observation_reject'))),
      );
      expect(await database.readDeliveryObservations(), ['A', 'B']);
      await database.customStatement('DROP TRIGGER reject_observation');
      await database.replaceDeliveryObservations(['B', 'C'], reduceWrites: enabled);
      expect(await database.readDeliveryObservations(), ['B', 'C']);
    }, skip: sqliteProblem, timeout: timeout);
  }

  test('delete failure keeps the previous snapshot and does not poison the queue', () async {
    await database.replaceDeliveryObservations(['A', 'B']);
    await database.customStatement('''
CREATE TEMP TRIGGER reject_observation_delete BEFORE DELETE ON delivery_observations
BEGIN SELECT RAISE(ABORT, 'synthetic_observation_delete_reject'); END
''');
    await expectLater(
      database.replaceDeliveryObservations([], reduceWrites: true),
      throwsA(predicate<Object>((error) => error.toString().contains('synthetic_observation_delete_reject'))),
    );
    expect(await database.readDeliveryObservations(), ['A', 'B']);
    await database.customStatement('DROP TRIGGER reject_observation_delete');
    await database.replaceDeliveryObservations([], reduceWrites: true);
    expect(await database.readDeliveryObservations(), isEmpty);
  }, skip: sqliteProblem, timeout: timeout);

  test('interleaved Off/On writes keep call order and snapshot mutable input', () async {
    final mutable = ['B', 'C'];
    final first = database.replaceDeliveryObservations(['A', 'B'], reduceWrites: true);
    final second = database.replaceDeliveryObservations(mutable);
    mutable[0] = 'tampered';
    await Future.wait([first, second]);
    expect(await database.readDeliveryObservations(), ['B', 'C']);
    await Future.wait([
      database.replaceDeliveryObservations(['C', 'D'], reduceWrites: true),
      database.replaceDeliveryObservations(['D', 'E']),
      database.replaceDeliveryObservations(['E', 'F'], reduceWrites: true),
    ]);
    expect(await database.readDeliveryObservations(), ['E', 'F']);
  }, skip: sqliteProblem, timeout: timeout);

  test('an external change is read from SQLite instead of a remembered successful plan', () async {
    await database.replaceDeliveryObservations(['A', 'B'], reduceWrites: true);
    await database.customStatement("UPDATE delivery_observations SET observation_json = 'external'");
    await database.replaceDeliveryObservations(['A', 'B'], reduceWrites: true);
    expect(await database.readDeliveryObservations(), ['A', 'B']);
  }, skip: sqliteProblem, timeout: timeout);

  test('custom/Off apply without writing immediately and persist through reload', () async {
    await storage.replaceDeliveryObservations(_values(0));
    final before = await changes();
    await settings.setReduceDeliveryObservationWrites(true);
    await settings.setPowerSavingProfile(PowerSavingProfile.custom);
    expect(await changes(), before);
    await storage.replaceDeliveryObservations(_values(0));
    expect(await changes(), before);
    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    await storage.replaceDeliveryObservations(_values(0));
    expect(await changes() - before, 32);
    expect(settings.settings.powerSaving.custom.reduceDeliveryObservationWrites, isTrue);
    final reloaded = AppSettingsService();
    try {
      await reloaded.loadSettings();
      expect(reloaded.settings.powerSaving.custom.reduceDeliveryObservationWrites, isTrue);
    } finally {
      reloaded.dispose();
    }
    await settings.setPowerSavingProfile(PowerSavingProfile.custom);
    final count = await changes();
    await storage.replaceDeliveryObservations(_values(0));
    expect(await changes(), count);
  }, skip: sqliteProblem, timeout: timeout);

  test('unrelated settings and disposed binding do not alter the active policy', () async {
    await settings.setPowerSavingProfile(PowerSavingProfile.custom);
    await settings.setReduceDeliveryObservationWrites(true);
    final values = <bool>[];
    final observer = DeliveryObservationPowerBinding(settings: settings, apply: values.add);
    try {
      await settings.setBatteryPollingIntervalSeconds(300);
      expect(values, [true]);
    } finally {
      observer.dispose();
    }
    binding.dispose();
    await settings.setReduceDeliveryObservationWrites(false);
    await storage.replaceDeliveryObservations(_values(0));
    final before = await changes();
    await storage.replaceDeliveryObservations(_values(0));
    expect(await changes(), before);
  }, skip: sqliteProblem, timeout: timeout);

  test('an awaited commit survives reopening the file and a fresh planner', () async {
    await storage.resetForTesting();
    final directory = await Directory.systemTemp.createTemp('mco_delivery_observation_');
    final file = File('${directory.path}${Platform.pathSeparator}observations.sqlite');
    MessageHistoryDatabase open() => MessageHistoryDatabase.withExecutor(
      NativeDatabase(file, setup: MessageHistoryDatabase.setupConnection),
    );
    try {
      final first = open();
      try {
        await first.replaceDeliveryObservations(['A', 'B'], reduceWrites: true);
      } finally {
        await first.close();
      }
      final second = open();
      try {
        expect(await second.readDeliveryObservations(), ['A', 'B']);
        await second.replaceDeliveryObservations(['B', 'C'], reduceWrites: true);
        expect(await second.readDeliveryObservations(), ['B', 'C']);
        final pragma = await second.customSelect('PRAGMA synchronous').getSingle();
        expect(pragma.data.values.single, 2, reason: 'FULL');
      } finally {
        await second.close();
      }
    } finally {
      // Только известные файлы собственного временного каталога, без recursive.
      for (final suffix in ['', '-wal', '-shm']) {
        final artifact = File('${file.path}$suffix');
        if (await artifact.exists()) {
          await artifact.delete();
        }
      }
      await directory.delete();
    }
  }, skip: sqliteProblem, timeout: timeout);
}
