import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ble_plugin_log_power_settings.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _LogPlatform extends FlutterBluePlusPlatform {
  final requests = <LogLevel>[];
  Object? nextError;

  @override
  Future<bool> setLogLevel(BmSetLogLevelRequest request) {
    requests.add(request.logLevel);
    final error = nextError;
    nextError = null;
    return error == null ? Future<bool>.value(true) : Future<bool>.error(error);
  }
}

AppSettingsService _settings() {
  final settings = AppSettingsService();
  addTearDown(settings.dispose);
  return settings;
}

BlePluginLogPowerSettings _binding(
  AppSettingsService settings, {
  Future<void> Function(LogLevel)? applyLevel,
  bool supported = true,
  void Function(Object, StackTrace)? onError,
}) {
  final binding = BlePluginLogPowerSettings(
    settings: settings,
    applyLevel: applyLevel,
    supported: supported,
    onError: onError,
  );
  addTearDown(binding.dispose);
  return binding;
}

Completer<void> _gate() {
  final gate = Completer<void>();
  addTearDown(() {
    if (!gate.isCompleted) {
      gate.complete();
    }
  });
  return gate;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = _LogPlatform();
  FlutterBluePlusPlatform? originalPlatform;
  late LogLevel initialLevel;

  setUpAll(() {
    initialLevel = FlutterBluePlus.logLevel;
    try {
      originalPlatform = FlutterBluePlusPlatform.instance;
    } on UnsupportedError {
      // Реальный Bluetooth для этого файла не нужен.
    }
    FlutterBluePlusPlatform.instance = platform;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    platform.nextError = null;
    await FlutterBluePlus.setLogLevel(LogLevel.debug);
    platform.requests.clear();
  });
  tearDown(PrefsManager.reset);
  tearDownAll(() async {
    await FlutterBluePlus.setLogLevel(initialLevel);
    final original = originalPlatform;
    if (original != null) {
      FlutterBluePlusPlatform.instance = original;
    }
  });

  test('default profile adds no Bluetooth calls for startup or custom edits',
      () async {
    final settings = _settings();
    final binding = _binding(settings);
    await binding.pendingApplicationForTest;
    await settings.setReduceBlePluginLogs(true);
    await settings.setGpsPollingIntervalSeconds(180);
    await settings.setDeferBleLogDescriptions(true);
    await binding.pendingApplicationForTest;
    expect(platform.requests, isEmpty);
    expect(FlutterBluePlus.logLevel, LogLevel.debug);
  });

  test('profiles use the public setter and preserve independent custom choices',
      () async {
    final settings = _settings();
    final binding = _binding(settings);
    for (final profile in [
      PowerSavingProfile.balanced,
      PowerSavingProfile.economical,
      PowerSavingProfile.maximum,
    ]) {
      await settings.setPowerSavingProfile(profile);
      await binding.pendingApplicationForTest;
      expect(FlutterBluePlus.logLevel, LogLevel.warning);
      expect(settings.settings.powerSaving.custom.reduceBlePluginLogs, isFalse);
    }
    expect(platform.requests, [LogLevel.warning]);
    await settings.setPowerSavingProfile(PowerSavingProfile.custom);
    await binding.pendingApplicationForTest;
    expect(FlutterBluePlus.logLevel, LogLevel.debug);
    await settings.setReduceBlePluginLogs(true);
    await binding.pendingApplicationForTest;
    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    await binding.pendingApplicationForTest;
    await settings.setPowerSavingProfile(PowerSavingProfile.custom);
    await binding.pendingApplicationForTest;
    await settings.setReduceBlePluginLogs(false);
    await binding.pendingApplicationForTest;
    expect(platform.requests, [
      LogLevel.warning, LogLevel.debug, LogLevel.warning,
      LogLevel.debug, LogLevel.warning, LogLevel.debug,
    ]);
    expect(settings.settings.powerSaving.custom.deferBleLogDescriptions, isFalse);
  });

  test('rapid profile changes apply the latest value after the in-flight call',
      () async {
    final settings = _settings();
    await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
    final gate = _gate();
    final calls = <LogLevel>[];
    final binding = _binding(settings, applyLevel: (level) {
      calls.add(level);
      return calls.length == 1 ? gate.future : Future<void>.value();
    });
    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    await settings.setPowerSavingProfile(PowerSavingProfile.maximum);
    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    expect(calls, [LogLevel.warning]);
    gate.complete();
    await binding.pendingApplicationForTest;
    expect(calls, [LogLevel.warning, LogLevel.debug]);
  });

  test('a return to the in-flight value skips obsolete intermediate changes',
      () async {
    final settings = _settings();
    await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
    final gate = _gate();
    final calls = <LogLevel>[];
    final binding = _binding(settings, applyLevel: (level) {
      calls.add(level);
      return gate.future;
    });
    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    await settings.setPowerSavingProfile(PowerSavingProfile.maximum);
    gate.complete();
    await binding.pendingApplicationForTest;
    expect(calls, [LogLevel.warning]);
  });

  test('failure is reported once and a changed getter does not prevent recovery',
      () async {
    final settings = _settings();
    await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
    final failure = PlatformException(code: 'synthetic-log-failure');
    platform.nextError = failure;
    final errors = <Object>[];
    final binding = _binding(settings, onError: (error, _) => errors.add(error));
    await binding.pendingApplicationForTest;
    expect(errors, [same(failure)]);
    expect(FlutterBluePlus.logLevel, LogLevel.warning);
    await settings.setGpsPollingIntervalSeconds(180);
    await settings.setPowerSavingProfile(PowerSavingProfile.economical);
    await binding.pendingApplicationForTest;
    expect(platform.requests, [LogLevel.warning]);
    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    await binding.pendingApplicationForTest;
    await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
    await binding.pendingApplicationForTest;
    expect(platform.requests, [LogLevel.warning, LogLevel.debug, LogLevel.warning]);
    expect(errors, hasLength(1));
  });

  test('failure of an old request still applies the newly selected profile',
      () async {
    final settings = _settings();
    await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
    final gate = _gate();
    final calls = <LogLevel>[];
    final errors = <Object>[];
    final binding = _binding(settings, applyLevel: (level) {
      calls.add(level);
      return calls.length == 1 ? gate.future : Future<void>.value();
    }, onError: (error, _) => errors.add(error));
    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    gate.completeError(StateError('synthetic failure'));
    await binding.pendingApplicationForTest;
    expect(calls, [LogLevel.warning, LogLevel.debug]);
    expect(errors, hasLength(1));
  });

  test('dispose detaches settings and suppresses queued calls and late errors',
      () async {
    final settings = _settings();
    await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
    final gate = _gate();
    final calls = <LogLevel>[];
    final errors = <Object>[];
    final binding = _binding(settings, applyLevel: (level) {
      calls.add(level);
      return gate.future;
    }, onError: (error, _) => errors.add(error));
    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    binding.dispose();
    binding.dispose();
    gate.completeError(StateError('synthetic late failure'));
    await binding.pendingApplicationForTest;
    await settings.setPowerSavingProfile(PowerSavingProfile.maximum);
    expect(calls, [LogLevel.warning]);
    expect(errors, isEmpty);
  });

  test('unsupported platforms retain settings without invoking Bluetooth',
      () async {
    final settings = _settings();
    await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
    final binding = _binding(settings, supported: false);
    await settings.setReduceBlePluginLogs(true);
    await settings.setPowerSavingProfile(PowerSavingProfile.custom);
    await binding.pendingApplicationForTest;
    expect(settings.settings.powerSaving.effective.reduceBlePluginLogs, isTrue);
    expect(platform.requests, isEmpty);
    expect(FlutterBluePlus.logLevel, LogLevel.debug);
  });

  test('a new binding retries warning even if a failed setter changed the getter',
      () async {
    final settings = _settings();
    await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
    platform.nextError = PlatformException(code: 'synthetic-log-failure');
    final errors = <Object>[];
    final first = _binding(settings, onError: (error, _) => errors.add(error));
    await first.pendingApplicationForTest;
    expect(FlutterBluePlus.logLevel, LogLevel.warning);
    first.dispose();
    final second = _binding(settings);
    await second.pendingApplicationForTest;
    expect(errors, hasLength(1));
    expect(platform.requests, [LogLevel.warning, LogLevel.warning]);
  });

  test('a new default binding restores a level left by the previous binding',
      () async {
    final settings = _settings();
    await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
    final first = _binding(settings);
    await first.pendingApplicationForTest;
    first.dispose();
    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    final second = _binding(settings);
    await second.pendingApplicationForTest;
    expect(platform.requests, [LogLevel.warning, LogLevel.debug]);
    expect(FlutterBluePlus.logLevel, LogLevel.debug);
  });
}
