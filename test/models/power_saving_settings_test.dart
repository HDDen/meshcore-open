import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';

void main() {
  test('default profile freezes original values independently of custom options', () {
    const settings = PowerSavingSettings(custom: PowerSavingOptions(
      hiddenRadioStatsIntervalSeconds: 30,
      pauseHiddenRadioIndicator: true,
      pauseIdleImageCleanup: true,
      pauseHiddenGifs: true,
      deferBleLogDescriptions: true,
      reduceBlePluginLogs: true,
      uiNotificationIntervalMilliseconds: 750,
      batteryIntervalSeconds: 300,
      gpsIntervalSeconds: 180,
    ));
    expect(settings.profile, PowerSavingProfile.disabled);
    expect(settings.effective.toJson(), {
      'hidden_radio_stats_interval_seconds': 1,
      'pause_hidden_radio_indicator': false,
      'pause_idle_image_cleanup': false,
      'pause_hidden_gifs': false,
      'defer_ble_log_descriptions': false,
      'reduce_ble_plugin_logs': false,
      'ui_notification_interval_milliseconds': 50,
      'battery_interval_seconds': 120,
      'gps_interval_seconds': 60,
    });
  });

  test('plugin log flag preserves defaults, JSON and independent custom values', () {
    for (final raw in [null, false, 0, 1, 'true', true]) {
      final options = PowerSavingOptions.fromJson({
        'reduce_ble_plugin_logs': raw,
      });
      expect(options.reduceBlePluginLogs, raw == true);
      expect(options.copyWith(deferBleLogDescriptions: true).reduceBlePluginLogs,
          raw == true);
      expect(PowerSavingOptions.fromJson(options.toJson()).reduceBlePluginLogs,
          raw == true);
    }
    expect(PowerSavingOptions.fromJson({}).reduceBlePluginLogs, isFalse);
    final changed = const PowerSavingOptions(deferBleLogDescriptions: true)
        .copyWith(reduceBlePluginLogs: true);
    expect(changed.reduceBlePluginLogs, isTrue);
    expect(changed.deferBleLogDescriptions, isTrue);
    for (final profile in PowerSavingProfile.values) {
      final settings = PowerSavingSettings(profile: profile);
      expect(settings.custom.reduceBlePluginLogs, isFalse);
      expect(settings.effective.reduceBlePluginLogs,
          profile != PowerSavingProfile.disabled && profile != PowerSavingProfile.custom);
    }
    final unknown = PowerSavingSettings.fromJson({
      'profile': 'future',
      'custom': {'reduce_ble_plugin_logs': true},
    });
    expect(unknown.profile, PowerSavingProfile.disabled);
    expect(unknown.effective.reduceBlePluginLogs, isFalse);
    expect(unknown.custom.reduceBlePluginLogs, isTrue);
  });

  test('log description flag requires a boolean and presets preserve custom data', () {
    for (final raw in [null, false, 0, 1, 'true', true]) {
      final options = PowerSavingOptions.fromJson({'defer_ble_log_descriptions': raw});
      expect(options.deferBleLogDescriptions, raw == true);
      expect(options.copyWith(gpsIntervalSeconds: 180).deferBleLogDescriptions, raw == true);
      expect(PowerSavingOptions.fromJson(options.toJson()).deferBleLogDescriptions, raw == true);
    }
    expect(PowerSavingOptions.fromJson({}).deferBleLogDescriptions, isFalse);
    for (final profile in PowerSavingProfile.values) {
      final settings = PowerSavingSettings(profile: profile);
      expect(settings.custom.deferBleLogDescriptions, isFalse);
      expect(settings.effective.deferBleLogDescriptions,
          profile != PowerSavingProfile.disabled && profile != PowerSavingProfile.custom);
    }
    expect(const PowerSavingOptions().copyWith(deferBleLogDescriptions: true)
        .toJson()['defer_ble_log_descriptions'], isTrue);
  });

  test('UI interval defaults, steps, JSON and presets preserve custom values', () {
    for (final raw in [null, false, '500', 250.0, <String, Object>{}]) {
      expect(PowerSavingOptions.fromJson({
        'ui_notification_interval_milliseconds': raw,
      }).uiNotificationIntervalMilliseconds, 50);
    }
    const normalized = <int, int>{
      -1: 50, 0: 50, 49: 50, 50: 50, 99: 50, 100: 100,
      251: 250, 999: 950, 1000: 1000, 5000: 1000,
    };
    for (final entry in normalized.entries) {
      final options = PowerSavingOptions.fromJson({
        'ui_notification_interval_milliseconds': entry.key,
      });
      expect(options.uiNotificationIntervalMilliseconds, entry.value);
      expect(const PowerSavingOptions().copyWith(
        uiNotificationIntervalMilliseconds: entry.key,
      ).uiNotificationIntervalMilliseconds, entry.value);
      expect(PowerSavingOptions.fromJson(options.toJson())
          .uiNotificationIntervalMilliseconds, entry.value);
    }
    expect(PowerSavingOptions.fromJson({}).uiNotificationIntervalMilliseconds, 50);
    const original = PowerSavingSettings(
      custom: PowerSavingOptions(uiNotificationIntervalMilliseconds: 750),
    );
    const intervals = {
      PowerSavingProfile.disabled: 50,
      PowerSavingProfile.balanced: 100,
      PowerSavingProfile.economical: 250,
      PowerSavingProfile.maximum: 500,
      PowerSavingProfile.custom: 750,
    };
    for (final entry in intervals.entries) {
      final restored = PowerSavingSettings.fromJson(jsonDecode(jsonEncode(
        original.copyWith(profile: entry.key).toJson(),
      )));
      expect(restored.effective.uiNotificationIntervalMilliseconds, entry.value);
      expect(restored.custom.uiNotificationIntervalMilliseconds, 750);
    }
  });

  test('off and the custom minimum preserve the original one-second cadence', () {
    expect(AppSettings().powerSaving.profile, PowerSavingProfile.disabled);
    expect(AppSettings.fromJson({}).powerSaving.profile,
        PowerSavingProfile.disabled);
    for (final profile in [PowerSavingProfile.disabled, PowerSavingProfile.custom]) {
      expect(PowerSavingSettings(profile: profile).effective
          .hiddenRadioStatsIntervalSeconds, 1);
      expect(PowerSavingSettings(profile: profile).effective
          .pauseHiddenRadioIndicator, isFalse);
      expect(PowerSavingSettings(profile: profile).effective
          .pauseIdleImageCleanup, isFalse);
      expect(PowerSavingSettings(profile: profile).effective.pauseHiddenGifs, isFalse);
      expect(PowerSavingSettings(profile: profile).effective.deferBleLogDescriptions, isFalse);
      expect(PowerSavingSettings(profile: profile).effective
          .batteryIntervalSeconds, 120);
      expect(PowerSavingSettings(profile: profile).effective
          .gpsIntervalSeconds, 60);
    }
  });

  test('each preset selects its own interval without changing custom values', () {
    const settings = PowerSavingSettings(
      custom: PowerSavingOptions(
        hiddenRadioStatsIntervalSeconds: 19,
        pauseHiddenRadioIndicator: true,
        pauseIdleImageCleanup: true,
        pauseHiddenGifs: true,
        batteryIntervalSeconds: 240,
        gpsIntervalSeconds: 180,
      ),
    );
    const expected = {
      PowerSavingProfile.disabled: 1,
      PowerSavingProfile.balanced: 15,
      PowerSavingProfile.economical: 30,
      PowerSavingProfile.maximum: 60,
      PowerSavingProfile.custom: 19,
    };
    const batteries = {
      PowerSavingProfile.disabled: 120,
      PowerSavingProfile.balanced: 180,
      PowerSavingProfile.economical: 300,
      PowerSavingProfile.maximum: 600,
      PowerSavingProfile.custom: 240,
    };
    const gps = {
      PowerSavingProfile.disabled: 60,
      PowerSavingProfile.balanced: 120,
      PowerSavingProfile.economical: 300,
      PowerSavingProfile.maximum: 600,
      PowerSavingProfile.custom: 180,
    };
    for (final entry in expected.entries) {
      final selected = settings.copyWith(profile: entry.key);
      expect(selected.effective.hiddenRadioStatsIntervalSeconds, entry.value);
      expect(selected.custom.hiddenRadioStatsIntervalSeconds, 19);
      expect(selected.custom.pauseHiddenRadioIndicator, isTrue);
      expect(selected.effective.pauseHiddenRadioIndicator,
          entry.key != PowerSavingProfile.disabled);
      expect(selected.effective.pauseIdleImageCleanup,
          entry.key != PowerSavingProfile.disabled);
      expect(selected.custom.pauseIdleImageCleanup, isTrue);
      expect(selected.custom.pauseHiddenGifs, isTrue);
      expect(selected.effective.pauseHiddenGifs,
          entry.key != PowerSavingProfile.disabled);
      expect(selected.effective.batteryIntervalSeconds, batteries[entry.key]);
      expect(selected.effective.gpsIntervalSeconds, gps[entry.key]);
      expect(selected.custom.batteryIntervalSeconds, 240);
      expect(selected.custom.gpsIntervalSeconds, 180);
    }
  });

  test('malformed and future profiles fall back to off and clamp custom data', () {
    for (final raw in [null, false, 7, 'custom', <Object>[]]) {
      expect(PowerSavingSettings.fromJson(raw).profile,
          PowerSavingProfile.disabled);
    }
    final future = PowerSavingSettings.fromJson({
      'profile': 'future-profile',
      'custom': {'hidden_radio_stats_interval_seconds': 99},
    });
    expect(future.profile, PowerSavingProfile.disabled);
    expect(future.effective.hiddenRadioStatsIntervalSeconds, 1);
    expect(future.custom.hiddenRadioStatsIntervalSeconds, 60);
    for (final entry in <Object?, int>{
      -10: 1, 0: 1, 1: 1, 31: 31, 60: 60, 200: 60,
      null: 1, '30': 1, 2.5: 1,
    }.entries) {
      final options = PowerSavingOptions.fromJson({
        'hidden_radio_stats_interval_seconds': entry.key,
      });
      expect(options.hiddenRadioStatsIntervalSeconds, entry.value);
    }
  });

  test('profile and custom data survive JSON and unrelated copyWith', () {
    final original = AppSettings(powerSaving: const PowerSavingSettings(
      profile: PowerSavingProfile.maximum,
      custom: PowerSavingOptions(
        hiddenRadioStatsIntervalSeconds: 23,
        pauseHiddenRadioIndicator: true,
        pauseIdleImageCleanup: true,
        pauseHiddenGifs: true,
        batteryIntervalSeconds: 240,
        gpsIntervalSeconds: 180,
      ),
    ));
    final decoded = AppSettings.fromJson(jsonDecode(jsonEncode(
      original.copyWith(hideRadioStatsButton: true).toJson(),
    )) as Map<String, dynamic>);
    expect(decoded.hideRadioStatsButton, isTrue);
    expect(decoded.powerSaving.profile, PowerSavingProfile.maximum);
    expect(decoded.powerSaving.custom.hiddenRadioStatsIntervalSeconds, 23);
    expect(decoded.powerSaving.effective.hiddenRadioStatsIntervalSeconds, 60);
    expect(decoded.powerSaving.custom.pauseHiddenRadioIndicator, isTrue);
    expect(decoded.powerSaving.custom.pauseIdleImageCleanup, isTrue);
    expect(decoded.powerSaving.custom.pauseHiddenGifs, isTrue);
    expect(decoded.powerSaving.custom.batteryIntervalSeconds, 240);
    expect(decoded.powerSaving.custom.gpsIntervalSeconds, 180);
  });

  test('indicator pause requires a boolean and old custom data keeps it off', () {
    for (final raw in [null, false, 0, 1, 'true', true]) {
      final options = PowerSavingOptions.fromJson({
        'pause_hidden_radio_indicator': raw,
      });
      expect(options.pauseHiddenRadioIndicator, raw == true);
    }
    expect(PowerSavingOptions.fromJson({}).pauseHiddenRadioIndicator, isFalse);
  });

  test('device intervals restore defaults, clamp and use whole-minute steps', () {
    for (final raw in [null, false, '300', 2.5, <String, Object>{}]) {
      final options = PowerSavingOptions.fromJson({
        'battery_interval_seconds': raw,
        'gps_interval_seconds': raw,
      });
      expect(options.batteryIntervalSeconds, 120);
      expect(options.gpsIntervalSeconds, 60);
    }
    const values = <int, (int, int)>{
      -1: (120, 60),
      0: (120, 60),
      60: (120, 60),
      120: (120, 120),
      179: (120, 120),
      180: (180, 180),
      599: (540, 540),
      600: (600, 600),
      999: (600, 600),
    };
    for (final entry in values.entries) {
      final options = PowerSavingOptions.fromJson({
        'battery_interval_seconds': entry.key,
        'gps_interval_seconds': entry.key,
      });
      final copied = const PowerSavingOptions().copyWith(
        batteryIntervalSeconds: entry.key,
        gpsIntervalSeconds: entry.key,
      );
      expect(options.batteryIntervalSeconds, entry.value.$1);
      expect(options.gpsIntervalSeconds, entry.value.$2);
      expect(copied.toJson(), options.toJson());
    }
  });

  test('hidden GIF pause is opt-in for old data and accepts only a boolean', () {
    for (final raw in [null, false, 0, 1, 'true', true]) {
      final options = PowerSavingOptions.fromJson({'pause_hidden_gifs': raw});
      expect(options.pauseHiddenGifs, raw == true);
      expect(options.copyWith(gpsIntervalSeconds: 180).pauseHiddenGifs, raw == true);
    }
    expect(PowerSavingOptions.fromJson({}).pauseHiddenGifs, isFalse);
    final enabled = const PowerSavingOptions().copyWith(pauseHiddenGifs: true);
    expect(enabled.toJson()['pause_hidden_gifs'], isTrue);
    expect(enabled.pauseHiddenRadioIndicator, isFalse);
    expect(enabled.pauseIdleImageCleanup, isFalse);
    expect(enabled.copyWith(pauseHiddenGifs: false).pauseHiddenGifs, isFalse);
  });

  test('idle image cleanup is opt-in for old data and accepts only a boolean', () {
    for (final raw in [null, false, 0, 1, 'true', true]) {
      final options = PowerSavingOptions.fromJson({
        'pause_idle_image_cleanup': raw,
      });
      expect(options.pauseIdleImageCleanup, raw == true);
      expect(options.copyWith(batteryIntervalSeconds: 300)
          .pauseIdleImageCleanup, raw == true);
    }
    expect(PowerSavingOptions.fromJson({}).pauseIdleImageCleanup, isFalse);
    expect(PowerSavingOptions.fromJson(null).pauseIdleImageCleanup, isFalse);
    final enabled = const PowerSavingOptions().copyWith(pauseIdleImageCleanup: true);
    expect(enabled.toJson()['pause_idle_image_cleanup'], isTrue);
    expect(enabled.pauseHiddenRadioIndicator, isFalse);
    expect(enabled.copyWith(pauseIdleImageCleanup: false).pauseIdleImageCleanup,
        isFalse);
  });
}
