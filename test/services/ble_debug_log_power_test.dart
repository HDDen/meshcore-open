import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/widgets.dart' show Builder, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/ble_log_power_settings.dart';
import 'package:meshcore_open/helpers/deferred_log_description.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/ble_debug_log_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

BleDebugLogService _log({bool deferred = false}) {
  final log = BleDebugLogService()..setDeferDescriptions(deferred);
  addTearDown(log.dispose);
  return log;
}

void _append(BleDebugLogService log, [int sequence = 1]) {
  log.logFrame(Uint8List.fromList([
    pushCodeLogRxData, 40, 176, sequence & 255, (sequence >> 8) & 255,
  ]), outgoing: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  test('description caches the first result including an empty string', () {
    for (final text in ['sample', '']) {
      var calls = 0;
      final description = DeferredLogDescription.lazy(() {
        calls++;
        return text;
      });
      expect(description.isResolved, isFalse);
      expect(calls, 0);
      expect(description.value, text);
      expect(description.isResolved, isTrue);
      expect(description.value, text);
      expect(calls, 1);
    }
    final eager = DeferredLogDescription.eager('provided');
    expect(eager.isResolved, isTrue);
    expect(eager.value, 'provided');
  });

  test('deferred entry captures bytes immediately and resolves only its description', () {
    final log = _log(deferred: true);
    final input = Uint8List.fromList([respCodeBattAndStorage, 0x68, 0x10]);
    log.logFrame(input, outgoing: false, note: 'snapshot');
    final entry = log.entries.single;
    final timestamp = entry.timestamp;
    input.fillRange(0, input.length, 0);
    expect(entry.descriptionResolvedForTest, isFalse);
    expect(entry.payload, [respCodeBattAndStorage, 0x68, 0x10]);
    expect(entry.hexPreview, '0c 68 10');
    expect(entry.descriptionResolvedForTest, isFalse);
    expect(() => entry.payload[0] = 0, throwsUnsupportedError);
    expect(entry.description, 'RX RESP_CODE_BATT_AND_STORAGE • 4200mV • snapshot');
    expect(entry.descriptionResolvedForTest, isTrue);
    expect(entry.timestamp, same(timestamp));
    expect(entry.description, 'RX RESP_CODE_BATT_AND_STORAGE • 4200mV • snapshot');
  });

  test('private response is sanitized before any deferred formatting', () {
    final log = _log(deferred: true);
    // Только искусственные одинаковые байты, не реальный ключ.
    final input = Uint8List.fromList([respCodePrivateKey, ...List<int>.filled(64, 0xa5)]);
    log.logFrame(input, outgoing: false, note: 'must be replaced');
    final entry = log.entries.single;
    expect(entry.descriptionResolvedForTest, isFalse);
    expect(entry.payload, [respCodePrivateKey]);
    expect(entry.hexPreview, '0e');
    expect(entry.descriptionResolvedForTest, isFalse);
    expect(log.rawLogRxEntries, isEmpty);
    expect(input, hasLength(65));
    expect(input.skip(1), everyElement(0xa5));
    expect(entry.description, 'RX RESP_CODE_PRIVATE_KEY • payload withheld');
  });

  test('deferred and eager entries produce the same diagnostic corpus', () {
    final eager = _log();
    final deferred = _log(deferred: true);
    for (final log in [eager, deferred]) {
      log.logFrame(Uint8List.fromList([cmdReboot]), outgoing: true);
      log.logFrame(Uint8List.fromList([respCodeSignStart, 0, 0, 16, 0, 0]), outgoing: false);
      log.logFrame(Uint8List.fromList([cmdGetBattAndStorage]), outgoing: true);
      log.logFrame(Uint8List.fromList([respCodeSignature, 1, 2, 3]), outgoing: false);
      log.logFrame(Uint8List.fromList([cmdSignData, 1, 2, 3]), outgoing: true);
      log.logFrame(Uint8List.fromList([respCodeSent]), outgoing: false);
      log.logFrame(Uint8List.fromList([respCodeBattAndStorage, 0x68, 0x10]), outgoing: false);
      log.logFrame(Uint8List.fromList([254, ...List<int>.filled(70, 0xa5)]),
          outgoing: false, note: 'unknown');
      log.logFrame(Uint8List.fromList([respCodePrivateKey, 0xa5]), outgoing: false);
      _append(log, 513);
    }
    expect(eager.entries.every((e) => e.descriptionResolvedForTest), isTrue);
    expect(deferred.entries.every((e) => !e.descriptionResolvedForTest), isTrue);
    expect(deferred.entries.map((e) => [e.outgoing, e.payload.toList(), e.hexPreview]).toList(),
        eager.entries.map((e) => [e.outgoing, e.payload.toList(), e.hexPreview]).toList());
    expect(deferred.entries.every((e) => !e.descriptionResolvedForTest), isTrue);
    expect(deferred.entries.map((e) => e.description).toList(),
        eager.entries.map((e) => e.description).toList());
    expect(deferred.rawLogRxEntries.single.payload, eager.rawLogRxEntries.single.payload);
  });

  test('live mode changes affect only new entries and clear does not format old ones', () {
    final log = _log();
    _append(log);
    final original = log.entries.single;
    expect(original.descriptionResolvedForTest, isTrue);
    log.setDeferDescriptions(true);
    _append(log, 2);
    final lazy = log.entries.last;
    log.setDeferDescriptions(false);
    _append(log, 3);
    expect(log.entries.last.descriptionResolvedForTest, isTrue);
    expect(lazy.descriptionResolvedForTest, isFalse);
    expect(original.descriptionResolvedForTest, isTrue);
    log.clear();
    expect(log.entries, isEmpty);
    expect(log.rawLogRxEntries, isEmpty);
    expect(lazy.descriptionResolvedForTest, isFalse);
    expect(lazy.description, 'RX PUSH_CODE_LOG_RX_DATA');
  });

  test('discarded and retained deferred entries remain unresolved until read', () {
    final log = _log(deferred: true);
    _append(log, 0);
    final first = log.entries.single;
    for (var i = 1; i < 503; i++) {
      _append(log, i);
    }
    expect(log.entries, hasLength(500));
    expect(log.rawLogRxEntries, hasLength(500));
    expect(log.entries.first.payload.sublist(3), [3, 0]);
    expect(log.rawLogRxEntries.first.payload, [3, 0]);
    expect(log.entries.every((e) => !e.descriptionResolvedForTest), isTrue);
    expect(first.descriptionResolvedForTest, isFalse);
    log.clear();
    expect(first.descriptionResolvedForTest, isFalse);
    expect(first.description, 'RX PUSH_CODE_LOG_RX_DATA');
  });

  testWidgets('deferred formatting preserves build-safe notifications and does not notify on read',
      (tester) async {
    final log = _log(deferred: true);
    final phases = <SchedulerPhase>[];
    log.addListener(() => phases.add(SchedulerBinding.instance.schedulerPhase));
    await tester.pumpWidget(Builder(builder: (_) {
      _append(log);
      _append(log, 2);
      expect(phases, isEmpty);
      expect(log.entries.every((e) => !e.descriptionResolvedForTest), isTrue);
      expect(log.entries.first.description, 'RX PUSH_CODE_LOG_RX_DATA');
      expect(phases, isEmpty);
      return const SizedBox.shrink();
    }));
    expect(phases, [SchedulerPhase.postFrameCallbacks]);
    expect(log.entries.last.description, 'RX PUSH_CODE_LOG_RX_DATA');
    expect(phases, [SchedulerPhase.postFrameCallbacks]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('settings binding applies each profile without changing the saved custom flag', () async {
    final log = _log();
    final settings = AppSettingsService();
    addTearDown(settings.dispose);
    await settings.setDeferBleLogDescriptions(true);
    final binding = BleLogPowerSettings(log: log, settings: settings);
    addTearDown(binding.dispose);
    for (final profile in PowerSavingProfile.values) {
      await settings.setPowerSavingProfile(profile);
      _append(log);
      expect(log.entries.last.descriptionResolvedForTest,
          profile == PowerSavingProfile.disabled);
      expect(settings.settings.powerSaving.custom.deferBleLogDescriptions, isTrue);
    }
    await settings.setDeferBleLogDescriptions(false);
    _append(log);
    expect(log.entries.last.descriptionResolvedForTest, isTrue);
    await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
    _append(log);
    expect(log.entries.last.descriptionResolvedForTest, isFalse);
    expect(settings.settings.powerSaving.custom.deferBleLogDescriptions, isFalse);
  });

  test('binding updates new entries live and detaches without clearing the journal', () async {
    final log = _log();
    final settings = AppSettingsService();
    addTearDown(settings.dispose);
    final binding = BleLogPowerSettings(log: log, settings: settings);
    addTearDown(binding.dispose);
    await settings.setDeferBleLogDescriptions(true);
    _append(log);
    expect(log.entries.last.descriptionResolvedForTest, isTrue);
    await settings.setPowerSavingProfile(PowerSavingProfile.custom);
    _append(log, 2);
    final lazy = log.entries.last;
    expect(lazy.descriptionResolvedForTest, isFalse);
    await settings.setGpsPollingIntervalSeconds(180);
    expect(lazy.descriptionResolvedForTest, isFalse);
    binding.dispose();
    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    _append(log, 3);
    expect(log.entries.last.descriptionResolvedForTest, isFalse);
    expect(log.entries, hasLength(3));
    expect(log.rawLogRxEntries, hasLength(3));
    expect(lazy.description, 'RX PUSH_CODE_LOG_RX_DATA');
  });
}
