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
      pauseHiddenStatusAnimations: true,
      disableContinuousStatusAnimations: true,
      cacheChannelKeyHashes: true,
      skipIdleDirectProgressParsing: true,
      uiNotificationIntervalMilliseconds: 750,
      batteryIntervalSeconds: 300,
      gpsIntervalSeconds: 180,
    ));
    expect(settings.profile, PowerSavingProfile.disabled);
    expect(settings.effective.toJson(), {
      'background_reconnect_interval_seconds': 30,
      'hidden_radio_stats_interval_seconds': 1,
      'pause_hidden_radio_indicator': false,
      'pause_idle_image_cleanup': false,
      'pause_hidden_gifs': false,
      'defer_ble_log_descriptions': false,
      'reduce_ble_plugin_logs': false,
      'pause_hidden_status_animations': false,
      'disable_continuous_status_animations': false,
      'cache_channel_key_hashes': false,
      'skip_idle_direct_progress_parsing': false,
      'ui_notification_interval_milliseconds': 50,
      'battery_interval_seconds': 120,
      'gps_interval_seconds': 60,
    });
  });

  test('background reconnect defaults, normalization, presets and JSON are independent', () {
    for (final raw in [null, false, '180', 180.0, <String, Object>{}]) {
      expect(PowerSavingOptions.fromJson({
        'background_reconnect_interval_seconds': raw,
      }).backgroundReconnectIntervalSeconds, 30);
    }
    for (final entry in {
      -1: 30, 0: 30, 29: 30, 30: 30, 59: 30, 60: 60,
      179: 150, 180: 180, 599: 570, 600: 600, 9999: 600,
    }.entries) {
      final options = PowerSavingOptions.fromJson({
        'background_reconnect_interval_seconds': entry.key,
      });
      expect(options.backgroundReconnectIntervalSeconds, entry.value);
      expect(const PowerSavingOptions().copyWith(
        backgroundReconnectIntervalSeconds: entry.key,
      ).toJson(), options.toJson());
    }
    const original = PowerSavingOptions(
      gpsIntervalSeconds: 180, skipIdleDirectProgressParsing: true,
    );
    final changed = original.copyWith(backgroundReconnectIntervalSeconds: 90);
    expect(changed.toJson(), {
      ...original.toJson(), 'background_reconnect_interval_seconds': 90,
    });
    expect(changed.copyWith(backgroundReconnectIntervalSeconds: 30).toJson(), original.toJson());
    for (final entry in {
      PowerSavingProfile.disabled: 30,
      PowerSavingProfile.balanced: 60,
      PowerSavingProfile.economical: 180,
      PowerSavingProfile.maximum: 600,
      PowerSavingProfile.custom: 90,
    }.entries) {
      final restored = PowerSavingSettings.fromJson(jsonDecode(jsonEncode(
        PowerSavingSettings(profile: entry.key, custom: changed).toJson(),
      )));
      expect(restored.effective.backgroundReconnectIntervalSeconds, entry.value);
      expect(restored.custom.toJson(), changed.toJson());
    }
    final unknown = PowerSavingSettings.fromJson({
      'profile': 'future', 'custom': changed.toJson(),
    });
    expect(unknown.effective.backgroundReconnectIntervalSeconds, 30);
    expect(unknown.custom.backgroundReconnectIntervalSeconds, 90);
    expect(PowerSavingOptions.fromJson({}).backgroundReconnectIntervalSeconds, 30);
  });

  test('idle direct progress flag preserves old settings, profiles and other choices', () {
    for (final raw in [null, false, 0, 1, 'true', true]) {
      final options = PowerSavingOptions.fromJson({'skip_idle_direct_progress_parsing': raw});
      expect(options.skipIdleDirectProgressParsing, raw == true);
      expect(PowerSavingOptions.fromJson(options.toJson()).skipIdleDirectProgressParsing,
          raw == true);
    }
    expect(PowerSavingOptions.fromJson({}).skipIdleDirectProgressParsing, isFalse);
    const original = PowerSavingOptions(cacheChannelKeyHashes: true,
        uiNotificationIntervalMilliseconds: 750);
    final changed = original.copyWith(skipIdleDirectProgressParsing: true);
    expect(changed.toJson(), {
      ...original.toJson(), 'skip_idle_direct_progress_parsing': true,
    });
    expect(changed.copyWith(skipIdleDirectProgressParsing: false).toJson(), original.toJson());
    for (final profile in PowerSavingProfile.values) {
      expect(PowerSavingSettings(profile: profile).effective.skipIdleDirectProgressParsing,
          profile != PowerSavingProfile.disabled && profile != PowerSavingProfile.custom);
    }
    final unknown = PowerSavingSettings.fromJson({
      'profile': 'future', 'custom': changed.toJson(),
    });
    expect(unknown.effective.skipIdleDirectProgressParsing, isFalse);
    expect(unknown.custom.skipIdleDirectProgressParsing, isTrue);
  });

  test('channel key hash cache preserves JSON, old settings and independent choices', () {
    for (final raw in [null, false, 0, 1, 'true', true]) {
      final options = PowerSavingOptions.fromJson({'cache_channel_key_hashes': raw});
      expect(options.cacheChannelKeyHashes, raw == true);
      expect(PowerSavingOptions.fromJson(options.toJson()).cacheChannelKeyHashes,
          raw == true);
    }
    expect(PowerSavingOptions.fromJson({}).cacheChannelKeyHashes, isFalse);
    const original = PowerSavingOptions(
      pauseHiddenStatusAnimations: true,
      uiNotificationIntervalMilliseconds: 750,
    );
    final changed = original.copyWith(cacheChannelKeyHashes: true);
    expect(changed.toJson(), {...original.toJson(), 'cache_channel_key_hashes': true});
    expect(changed.copyWith(cacheChannelKeyHashes: false).toJson(), original.toJson());
    for (final profile in PowerSavingProfile.values) {
      final settings = PowerSavingSettings(profile: profile);
      expect(settings.effective.cacheChannelKeyHashes,
          profile != PowerSavingProfile.disabled && profile != PowerSavingProfile.custom);
    }
    final unknown = PowerSavingSettings.fromJson({
      'profile': 'future', 'custom': changed.toJson(),
    });
    expect(unknown.effective.cacheChannelKeyHashes, isFalse);
    expect(unknown.custom.cacheChannelKeyHashes, isTrue);
  });

  test('status animation flags keep separate boolean values and preset defaults', () {
    for (final raw in [null, false, 0, 1, 'true', true]) {
      final options = PowerSavingOptions.fromJson({
        'pause_hidden_status_animations': raw,
        'disable_continuous_status_animations': raw,
      });
      expect(options.pauseHiddenStatusAnimations, raw == true);
      expect(options.disableContinuousStatusAnimations, raw == true);
      final copied = options.copyWith(reduceBlePluginLogs: true);
      final restored = PowerSavingOptions.fromJson(copied.toJson());
      expect(restored.pauseHiddenStatusAnimations, raw == true);
      expect(restored.disableContinuousStatusAnimations, raw == true);
    }
    const expected = {
      PowerSavingProfile.disabled: (false, false),
      PowerSavingProfile.balanced: (true, false),
      PowerSavingProfile.economical: (true, true),
      PowerSavingProfile.maximum: (true, true),
      PowerSavingProfile.custom: (false, false),
    };
    for (final entry in expected.entries) {
      final options = PowerSavingSettings(profile: entry.key).effective;
      expect((options.pauseHiddenStatusAnimations,
          options.disableContinuousStatusAnimations), entry.value);
    }
    final independent = const PowerSavingOptions()
        .copyWith(pauseHiddenStatusAnimations: true)
        .copyWith(disableContinuousStatusAnimations: true)
        .copyWith(pauseHiddenStatusAnimations: false);
    expect(independent.pauseHiddenStatusAnimations, isFalse);
    expect(independent.disableContinuousStatusAnimations, isTrue);
    final old = PowerSavingOptions.fromJson({});
    expect(old.pauseHiddenStatusAnimations, isFalse);
    expect(old.disableContinuousStatusAnimations, isFalse);
    final unknown = PowerSavingSettings.fromJson({
      'profile': 'future',
      'custom': independent.toJson(),
    });
    expect(unknown.effective.pauseHiddenStatusAnimations, isFalse);
    expect(unknown.effective.disableContinuousStatusAnimations, isFalse);
    expect(unknown.custom.disableContinuousStatusAnimations, isTrue);
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
