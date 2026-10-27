import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/flutter_foreground_task_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/tcp_wifi_power_binding.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/background_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ForegroundProbe extends FlutterForegroundTaskPlatform {
  int runningChecks = 0;

  @override
  Future<bool> get isRunningService async {
    runningChecks++;
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(seconds: 10));
  const wifi = MethodChannel('mco_advanced/tcp_wifi_lock');
  const cpu = MethodChannel('mco_advanced/cpu_policy');
  const engine = MethodChannel('mco_advanced/engine_lifecycle');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FlutterForegroundTaskPlatform originalPlatform;
  late _ForegroundProbe foreground;
  late BackgroundService background;
  late AppSettingsService settings;
  late TcpWifiPowerBinding binding;
  late List<bool> calls;
  late List<MethodCall> unrelated;
  late List<Future<void>> updates;

  Future<void> settlePolicy() async {
    await Future.wait(updates);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    FlutterForegroundTask.resetStatic();
    originalPlatform = FlutterForegroundTaskPlatform.instance;
    foreground = _ForegroundProbe();
    FlutterForegroundTaskPlatform.instance = foreground;
    calls = [];
    unrelated = [];
    updates = [];
    messenger.setMockMethodCallHandler(wifi, (call) async {
      calls.add((call.arguments as Map)['enabled'] as bool);
      return null;
    });
    for (final channel in [cpu, engine]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        unrelated.add(call);
        return null;
      });
    }
    background = BackgroundService.forTest(isAndroid: true);
    settings = AppSettingsService();
    binding = TcpWifiPowerBinding(
      settings: settings,
      apply: (value) { updates.add(background.setTcpWifiPowerSaving(value)); },
    );
  });

  tearDown(() async {
    binding.dispose();
    settings.dispose();
    await settlePolicy();
    for (final channel in [wifi, cpu, engine]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    FlutterForegroundTask.resetStatic();
    FlutterForegroundTaskPlatform.instance = originalPlatform;
    PrefsManager.reset();
    expect(unrelated, isEmpty);
    expect(foreground.runningChecks, 0);
  });

  test('custom applies immediately; Off restores only the still-active demand', () async {
    await settlePolicy();
    expect(calls, isEmpty);
    await background.setTcpWifiLock(true);
    await settings.setReleaseTcpWifiLock(true);
    await settlePolicy();
    expect(calls, [true]); // Off хранит свой выбор, но не применяет его.

    await settings.setPowerSavingProfile(PowerSavingProfile.custom);
    await settlePolicy();
    expect(calls, [true, false]);
    for (final profile in [PowerSavingProfile.disabled, PowerSavingProfile.balanced,
      PowerSavingProfile.economical, PowerSavingProfile.maximum]) {
      await settings.setPowerSavingProfile(profile);
      await settlePolicy();
      expect(calls.last, isTrue);
      expect(settings.settings.powerSaving.custom.releaseTcpWifiLock, isTrue);
    }
    await settings.setPowerSavingProfile(PowerSavingProfile.custom);
    await settlePolicy();
    expect(calls.last, isFalse);
    await background.setTcpWifiLock(false);
    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    await settlePolicy();
    expect(calls.last, isFalse);
    expect(settings.settings.backgroundTcpEnabled, isTrue);
  }, timeout: timeout);

  test('cold start and restart preserve custom without an initial acquire', () async {
    await settings.setReleaseTcpWifiLock(true);
    await settings.setPowerSavingProfile(PowerSavingProfile.custom);
    await settlePolicy();
    final reloaded = AppSettingsService();
    addTearDown(reloaded.dispose);
    await reloaded.loadSettings();
    expect(reloaded.settings.powerSaving.custom.releaseTcpWifiLock, isTrue);
    expect(reloaded.settings.powerSaving.profile, PowerSavingProfile.custom);

    final coldBackground = BackgroundService.forTest(isAndroid: true);
    calls.clear();
    // Тот же порядок, что в main: seed до первого транспортного запроса.
    await coldBackground.setTcpWifiPowerSaving(
      reloaded.settings.powerSaving.effective.releaseTcpWifiLock,
    );
    final coldUpdates = <Future<void>>[];
    final coldBinding = TcpWifiPowerBinding(settings: reloaded, apply: (value) {
      coldUpdates.add(coldBackground.setTcpWifiPowerSaving(value));
    });
    try {
      await Future.wait(coldUpdates);
      await coldBackground.setTcpWifiLock(true);
      expect(calls, [false, false]);
      await reloaded.setPowerSavingProfile(PowerSavingProfile.disabled);
      await Future.wait(coldUpdates);
      expect(calls.last, isTrue);
    } finally {
      coldBinding.dispose();
      await coldBackground.setTcpWifiLock(false);
    }
  }, timeout: timeout);

  test('unrelated settings and a disposed binding do not reapply policy', () async {
    await settings.setPowerSavingProfile(PowerSavingProfile.custom);
    await settings.setReleaseTcpWifiLock(true);
    await settlePolicy();
    final count = calls.length;
    await settings.setBatteryPollingIntervalSeconds(300);
    await settlePolicy();
    expect(calls, hasLength(count));
    binding.dispose();
    await settings.setReleaseTcpWifiLock(false);
    await settlePolicy();
    expect(calls, hasLength(count));
  }, timeout: timeout);

  test('a failed release is nonfatal and a later original policy still applies', () async {
    messenger.setMockMethodCallHandler(wifi, (call) async {
      final enabled = (call.arguments as Map)['enabled'] as bool;
      calls.add(enabled);
      if (!enabled) {
        throw PlatformException(code: 'synthetic_release_failure');
      }
      return null;
    });
    await background.setTcpWifiLock(true);
    await settings.setReleaseTcpWifiLock(true);
    await settings.setPowerSavingProfile(PowerSavingProfile.custom);
    await settlePolicy();
    await settings.setPowerSavingProfile(PowerSavingProfile.disabled);
    await settlePolicy();
    expect(calls, [true, false, true]);
  }, timeout: timeout);

  test('late native acquire cannot override profile and transport release', () async {
    final entered = Completer<void>();
    final reply = Completer<void>();
    addTearDown(() {
      if (!reply.isCompleted) {
        reply.complete();
      }
    });
    var held = false;
    messenger.setMockMethodCallHandler(wifi, (call) async {
      final enabled = (call.arguments as Map)['enabled'] as bool;
      calls.add(enabled);
      if (enabled) {
        entered.complete();
        await reply.future;
      }
      held = enabled;
      return null;
    });
    final acquiring = background.setTcpWifiLock(true);
    await entered.future;
    await settings.setReleaseTcpWifiLock(true);
    await settings.setPowerSavingProfile(PowerSavingProfile.custom);
    final disconnecting = background.setTcpWifiLock(false);
    try {
      expect(calls, [true]);
      reply.complete();
      await acquiring;
      await settlePolicy();
      await disconnecting;
      expect(calls, [true, false, false]);
      expect(held, isFalse);
    } finally {
      if (!reply.isCompleted) {
        reply.complete();
      }
      await acquiring;
      await disconnecting;
    }
  }, timeout: timeout);

  test('the new preference remains inert outside Android', () async {
    final otherPlatform = BackgroundService.forTest(isAndroid: false);
    await otherPlatform.setTcpWifiLock(true);
    await otherPlatform.setTcpWifiPowerSaving(true);
    await otherPlatform.setTcpWifiPowerSaving(false);
    await otherPlatform.setTcpWifiLock(false);
    expect(calls, isEmpty);
  }, timeout: timeout);
}
