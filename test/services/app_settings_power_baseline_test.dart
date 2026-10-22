import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Existing settings must survive adding a power profile and its custom values.
// The fixture and first three tests were frozen before adding power settings.
const _legacySettings = <String, dynamic>{
  'hide_radio_stats_button': false,
  'show_hops': false,
  'notifications_enabled': false,
  'background_tcp_enabled': false,
  'channel_min_hops_enabled': true,
  'channel_min_hops': 5,
  'channel_min_hops_retries': 3,
  'channel_min_hops_delay_seconds': 45,
  'channel_min_hops_count_repeaters': true,
  'channel_min_hops_repeater_count': 7,
};

Map<String, dynamic> _deliveryChoices(AppSettings settings) => {
  'notifications_enabled': settings.notificationsEnabled,
  'background_tcp_enabled': settings.backgroundTcpEnabled,
  'channel_min_hops_enabled': settings.channelMinHopsEnabled,
  'channel_min_hops': settings.channelMinHops,
  'channel_min_hops_retries': settings.channelMinHopsRetries,
  'channel_min_hops_delay_seconds': settings.channelMinHopsDelaySeconds,
  'channel_min_hops_count_repeaters': settings.channelMinHopsCountRepeaters,
  'channel_min_hops_repeater_count': settings.channelMinHopsRepeaterCount,
};

void _expectDeliveryChoices(AppSettings settings) {
  expect(_deliveryChoices(settings), {
    for (final key in _deliveryChoices(settings).keys)
      key: _legacySettings[key],
  });
}

Future<AppSettingsService> _loadSettings() async {
  final service = AppSettingsService();
  addTearDown(service.dispose);
  await service.loadSettings();
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode(_legacySettings),
    });
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  test('legacy preferences preserve radio and delivery settings', () async {
    final service = await _loadSettings();
    _expectDeliveryChoices(service.settings);
    expect(service.settings.hideRadioStatsButton, isFalse);
    expect(service.settings.showHops, isFalse);

    final roundTrip = AppSettings.fromJson(
      jsonDecode(jsonEncode(service.settings.toJson()))
          as Map<String, dynamic>,
    );
    _expectDeliveryChoices(roundTrip);
    expect(roundTrip.hideRadioStatsButton, isFalse);
  });

  test('a UI toggle persists without changing delivery settings', () async {
    final service = await _loadSettings();
    await service.setHideRadioStatsButton(true);

    final saved = jsonDecode(
      PrefsManager.instance.getString('app_settings')!,
    ) as Map<String, dynamic>;
    expect(saved['hide_radio_stats_button'], isTrue);
    _expectDeliveryChoices(AppSettings.fromJson(saved));

    final reloaded = await _loadSettings();
    expect(reloaded.settings.hideRadioStatsButton, isTrue);
    expect(reloaded.settings.showHops, isFalse);
    _expectDeliveryChoices(reloaded.settings);
  });

  test('unrelated settings updates preserve an earlier UI choice after reload',
      () async {
    final service = await _loadSettings();
    await service.setHideRadioStatsButton(true);

    final reloaded = await _loadSettings();
    await reloaded.setShowHops(true);
    final savedAgain = await _loadSettings();
    expect(savedAgain.settings.showHops, isTrue);
    expect(savedAgain.settings.hideRadioStatsButton, isTrue);
    _expectDeliveryChoices(savedAgain.settings);
  });

  test('every power profile and reload preserve all custom and delivery choices',
      () async {
    var service = await _loadSettings();
    expect(service.settings.powerSaving.profile, PowerSavingProfile.disabled);
    await service.setPowerSavingProfile(PowerSavingProfile.custom);
    await service.setHiddenRadioStatsIntervalSeconds(19);
    await service.setPauseHiddenRadioIndicator(true);
    await service.setPauseIdleImageCleanup(true);
    await service.setPauseHiddenGifs(true);
    await service.setBatteryPollingIntervalSeconds(240);
    await service.setGpsPollingIntervalSeconds(180);
    await service.setBackgroundReconnectIntervalSeconds(90);
    await service.setUiNotificationIntervalMilliseconds(750);
    await service.setDeferBleLogDescriptions(false);
    await service.setReduceBlePluginLogs(true);
    await service.setPauseHiddenStatusAnimations(true);
    await service.setDisableContinuousStatusAnimations(false);
    await service.setCacheChannelKeyHashes(false);
    await service.setSkipIdleDirectProgressParsing(true);
    final savedCustom = service.settings.powerSaving.custom.toJson();
    for (final profile in PowerSavingProfile.values) {
      await service.setPowerSavingProfile(profile);
      expect(service.settings.powerSaving.custom.toJson(), savedCustom);
      service = await _loadSettings();
      expect(service.settings.powerSaving.profile, profile);
      expect(service.settings.powerSaving.custom.toJson(), savedCustom);
      expect(service.settings.powerSaving.effective.toJson(),
          profile == PowerSavingProfile.custom ? savedCustom
              : PowerSavingSettings(profile: profile).effective.toJson());
      _expectDeliveryChoices(service.settings);
      // Возврат в свои настройки после каждого чужого профиля и перезагрузки.
      await service.setPowerSavingProfile(PowerSavingProfile.custom);
      service = await _loadSettings();
      expect(service.settings.powerSaving.effective.toJson(), savedCustom);
    }
    await service.setPowerSavingProfile(PowerSavingProfile.custom);
    await service.setHideRadioStatsButton(true);
    final reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.profile, PowerSavingProfile.custom);
    expect(reloaded.settings.powerSaving.effective
        .hiddenRadioStatsIntervalSeconds, 19);
    expect(reloaded.settings.powerSaving.effective.pauseHiddenRadioIndicator,
        isTrue);
    expect(reloaded.settings.powerSaving.effective.pauseIdleImageCleanup, isTrue);
    expect(reloaded.settings.powerSaving.effective.pauseHiddenGifs, isTrue);
    expect(reloaded.settings.powerSaving.effective.batteryIntervalSeconds, 240);
    expect(reloaded.settings.powerSaving.effective.gpsIntervalSeconds, 180);
    expect(reloaded.settings.powerSaving.effective.backgroundReconnectIntervalSeconds, 90);
    expect(reloaded.settings.powerSaving.effective.toJson(), savedCustom);
    expect(reloaded.settings.hideRadioStatsButton, isTrue);
    _expectDeliveryChoices(reloaded.settings);
  });

  test('custom interval is bounded without enabling power saving', () async {
    final service = await _loadSettings();
    await service.setHiddenRadioStatsIntervalSeconds(-5);
    expect(service.settings.powerSaving.custom.hiddenRadioStatsIntervalSeconds,
        1);
    await service.setHiddenRadioStatsIntervalSeconds(100);
    expect(service.settings.powerSaving.custom.hiddenRadioStatsIntervalSeconds,
        60);
    expect(service.settings.powerSaving.effective.hiddenRadioStatsIntervalSeconds,
        1);
    expect(service.settings.powerSaving.profile, PowerSavingProfile.disabled);
  });

  test('indicator option is independent from the slider and survives reload',
      () async {
    final service = await _loadSettings();
    await service.setPauseHiddenRadioIndicator(true);
    expect(service.settings.powerSaving.profile, PowerSavingProfile.disabled);
    expect(service.settings.powerSaving.effective.pauseHiddenRadioIndicator,
        isFalse);
    await service.setPowerSavingProfile(PowerSavingProfile.custom);
    var reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.pauseHiddenRadioIndicator,
        isTrue);
    expect(reloaded.settings.powerSaving.effective.hiddenRadioStatsIntervalSeconds,
        1);
    await reloaded.setHiddenRadioStatsIntervalSeconds(17);
    await reloaded.setPauseHiddenRadioIndicator(false);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.pauseHiddenRadioIndicator,
        isFalse);
    expect(reloaded.settings.powerSaving.effective.hiddenRadioStatsIntervalSeconds,
        17);
    _expectDeliveryChoices(reloaded.settings);
  });

  test('device interval setters preserve each other and never enable the profile',
      () async {
    final service = await _loadSettings();
    await service.setBatteryPollingIntervalSeconds(999);
    await service.setGpsPollingIntervalSeconds(179);
    expect(service.settings.powerSaving.profile, PowerSavingProfile.disabled);
    expect(service.settings.powerSaving.effective.batteryIntervalSeconds, 120);
    expect(service.settings.powerSaving.effective.gpsIntervalSeconds, 60);
    await service.setPowerSavingProfile(PowerSavingProfile.custom);
    var reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.batteryIntervalSeconds, 600);
    expect(reloaded.settings.powerSaving.effective.gpsIntervalSeconds, 120);
    await reloaded.setGpsPollingIntervalSeconds(240);
    await reloaded.setHiddenRadioStatsIntervalSeconds(7);
    await reloaded.setBatteryPollingIntervalSeconds(-1);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.batteryIntervalSeconds, 120);
    expect(reloaded.settings.powerSaving.effective.gpsIntervalSeconds, 240);
    expect(reloaded.settings.powerSaving.effective.hiddenRadioStatsIntervalSeconds,
        7);
    _expectDeliveryChoices(reloaded.settings);
  });

  test('idle progress parsing persists independently and preserves all other choices', () async {
    final service = await _loadSettings();
    await service.setPauseHiddenStatusAnimations(true);
    await service.setDisableContinuousStatusAnimations(true);
    await service.setReduceBlePluginLogs(true);
    await service.setDeferBleLogDescriptions(true);
    await service.setPauseHiddenGifs(true);
    await service.setPauseIdleImageCleanup(true);
    await service.setPauseHiddenRadioIndicator(true);
    await service.setCacheChannelKeyHashes(true);
    await service.setUiNotificationIntervalMilliseconds(750);
    await service.setBatteryPollingIntervalSeconds(300);
    await service.setGpsPollingIntervalSeconds(240);
    await service.setHiddenRadioStatsIntervalSeconds(17);
    final other = service.settings.powerSaving.custom.toJson();
    await service.setSkipIdleDirectProgressParsing(true);
    expect(service.settings.powerSaving.profile, PowerSavingProfile.disabled);
    expect(service.settings.powerSaving.effective.skipIdleDirectProgressParsing, isFalse);
    await service.setPowerSavingProfile(PowerSavingProfile.custom);
    var reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.toJson(), {
      ...other, 'skip_idle_direct_progress_parsing': true,
    });
    await reloaded.setPowerSavingProfile(PowerSavingProfile.maximum);
    await reloaded.setSkipIdleDirectProgressParsing(false);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.skipIdleDirectProgressParsing, isTrue);
    expect(reloaded.settings.powerSaving.custom.toJson(), other);
    await reloaded.setPowerSavingProfile(PowerSavingProfile.custom);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.toJson(), other);
    _expectDeliveryChoices(reloaded.settings);
  });

  test('channel hash cache persists independently and preserves all other choices', () async {
    final service = await _loadSettings();
    await service.setPauseHiddenStatusAnimations(true);
    await service.setDisableContinuousStatusAnimations(true);
    await service.setReduceBlePluginLogs(true);
    await service.setDeferBleLogDescriptions(true);
    await service.setPauseHiddenGifs(true);
    await service.setPauseIdleImageCleanup(true);
    await service.setPauseHiddenRadioIndicator(true);
    await service.setUiNotificationIntervalMilliseconds(750);
    await service.setBatteryPollingIntervalSeconds(300);
    await service.setGpsPollingIntervalSeconds(240);
    await service.setHiddenRadioStatsIntervalSeconds(17);
    final other = service.settings.powerSaving.custom.toJson();
    await service.setCacheChannelKeyHashes(true);
    expect(service.settings.powerSaving.profile, PowerSavingProfile.disabled);
    expect(service.settings.powerSaving.effective.cacheChannelKeyHashes, isFalse);
    await service.setPowerSavingProfile(PowerSavingProfile.custom);
    var reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.toJson(), {
      ...other, 'cache_channel_key_hashes': true,
    });
    await reloaded.setPowerSavingProfile(PowerSavingProfile.maximum);
    await reloaded.setCacheChannelKeyHashes(false);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.cacheChannelKeyHashes, isTrue);
    expect(reloaded.settings.powerSaving.custom.toJson(), other);
    await reloaded.setPowerSavingProfile(PowerSavingProfile.custom);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.toJson(), other);
    _expectDeliveryChoices(reloaded.settings);
  });

  test('status animation choices persist independently and preserve other options', () async {
    final service = await _loadSettings();
    await service.setPauseHiddenStatusAnimations(true);
    await service.setDisableContinuousStatusAnimations(true);
    expect(service.settings.powerSaving.profile, PowerSavingProfile.disabled);
    expect(service.settings.powerSaving.effective.pauseHiddenStatusAnimations, isFalse);
    expect(service.settings.powerSaving.effective.disableContinuousStatusAnimations, isFalse);
    await service.setPowerSavingProfile(PowerSavingProfile.custom);
    var reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.pauseHiddenStatusAnimations, isTrue);
    expect(reloaded.settings.powerSaving.effective.disableContinuousStatusAnimations, isTrue);
    await reloaded.setPauseHiddenStatusAnimations(false);
    await reloaded.setReduceBlePluginLogs(true);
    await reloaded.setDeferBleLogDescriptions(true);
    await reloaded.setPauseHiddenGifs(true);
    await reloaded.setPauseIdleImageCleanup(true);
    await reloaded.setPauseHiddenRadioIndicator(true);
    await reloaded.setUiNotificationIntervalMilliseconds(750);
    await reloaded.setBatteryPollingIntervalSeconds(300);
    await reloaded.setGpsPollingIntervalSeconds(240);
    await reloaded.setHiddenRadioStatsIntervalSeconds(17);
    final saved = reloaded.settings.powerSaving.custom.toJson();
    await reloaded.setPowerSavingProfile(PowerSavingProfile.maximum);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.custom.toJson(), saved);
    expect(reloaded.settings.powerSaving.effective.pauseHiddenStatusAnimations, isTrue);
    await reloaded.setPowerSavingProfile(PowerSavingProfile.custom);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.toJson(), saved);
    await reloaded.setDisableContinuousStatusAnimations(false);
    await reloaded.setPauseHiddenStatusAnimations(true);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.toJson(), {
      ...saved,
      'pause_hidden_status_animations': true,
      'disable_continuous_status_animations': false,
    });
    _expectDeliveryChoices(reloaded.settings);
  });

  test('plugin log flag persists independently without enabling the profile', () async {
    final service = await _loadSettings();
    await service.setReduceBlePluginLogs(true);
    expect(service.settings.powerSaving.profile, PowerSavingProfile.disabled);
    expect(service.settings.powerSaving.effective.reduceBlePluginLogs, isFalse);
    await service.setPowerSavingProfile(PowerSavingProfile.custom);
    var reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.reduceBlePluginLogs, isTrue);
    await reloaded.setDeferBleLogDescriptions(true);
    await reloaded.setPauseHiddenGifs(true);
    await reloaded.setPauseIdleImageCleanup(true);
    await reloaded.setPauseHiddenRadioIndicator(true);
    await reloaded.setUiNotificationIntervalMilliseconds(750);
    await reloaded.setBatteryPollingIntervalSeconds(300);
    await reloaded.setGpsPollingIntervalSeconds(240);
    await reloaded.setHiddenRadioStatsIntervalSeconds(17);
    await reloaded.setPowerSavingProfile(PowerSavingProfile.maximum);
    await reloaded.setReduceBlePluginLogs(false);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.reduceBlePluginLogs, isTrue);
    expect(reloaded.settings.powerSaving.custom.reduceBlePluginLogs, isFalse);
    await reloaded.setPowerSavingProfile(PowerSavingProfile.custom);
    reloaded = await _loadSettings();
    final options = reloaded.settings.powerSaving.effective;
    expect(options.reduceBlePluginLogs, isFalse);
    expect(options.deferBleLogDescriptions, isTrue);
    expect(options.pauseHiddenGifs, isTrue);
    expect(options.pauseIdleImageCleanup, isTrue);
    expect(options.pauseHiddenRadioIndicator, isTrue);
    expect(options.uiNotificationIntervalMilliseconds, 750);
    expect(options.batteryIntervalSeconds, 300);
    expect(options.gpsIntervalSeconds, 240);
    expect(options.hiddenRadioStatsIntervalSeconds, 17);
    _expectDeliveryChoices(reloaded.settings);
  });

  test('log description flag persists independently without enabling the profile', () async {
    final service = await _loadSettings();
    await service.setDeferBleLogDescriptions(true);
    expect(service.settings.powerSaving.profile, PowerSavingProfile.disabled);
    expect(service.settings.powerSaving.effective.deferBleLogDescriptions, isFalse);
    await service.setPowerSavingProfile(PowerSavingProfile.custom);
    var reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.deferBleLogDescriptions, isTrue);
    await reloaded.setPauseHiddenGifs(true);
    await reloaded.setPauseIdleImageCleanup(true);
    await reloaded.setPauseHiddenRadioIndicator(true);
    await reloaded.setUiNotificationIntervalMilliseconds(750);
    await reloaded.setBatteryPollingIntervalSeconds(300);
    await reloaded.setGpsPollingIntervalSeconds(240);
    await reloaded.setHiddenRadioStatsIntervalSeconds(17);
    await reloaded.setPowerSavingProfile(PowerSavingProfile.maximum);
    await reloaded.setDeferBleLogDescriptions(false);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.deferBleLogDescriptions, isTrue);
    expect(reloaded.settings.powerSaving.custom.deferBleLogDescriptions, isFalse);
    await reloaded.setPowerSavingProfile(PowerSavingProfile.custom);
    reloaded = await _loadSettings();
    final options = reloaded.settings.powerSaving.effective;
    expect(options.deferBleLogDescriptions, isFalse);
    expect(options.pauseHiddenGifs, isTrue);
    expect(options.pauseIdleImageCleanup, isTrue);
    expect(options.pauseHiddenRadioIndicator, isTrue);
    expect(options.uiNotificationIntervalMilliseconds, 750);
    expect(options.batteryIntervalSeconds, 300);
    expect(options.gpsIntervalSeconds, 240);
    expect(options.hiddenRadioStatsIntervalSeconds, 17);
    _expectDeliveryChoices(reloaded.settings);
  });

  test('UI interval persists independently without enabling the profile', () async {
    final service = await _loadSettings();
    await service.setUiNotificationIntervalMilliseconds(799);
    expect(service.settings.powerSaving.profile, PowerSavingProfile.disabled);
    expect(service.settings.powerSaving.effective.uiNotificationIntervalMilliseconds, 50);
    await service.setPowerSavingProfile(PowerSavingProfile.custom);
    var reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.uiNotificationIntervalMilliseconds, 750);
    await reloaded.setPauseHiddenGifs(true);
    await reloaded.setPauseIdleImageCleanup(true);
    await reloaded.setPauseHiddenRadioIndicator(true);
    await reloaded.setBatteryPollingIntervalSeconds(300);
    await reloaded.setGpsPollingIntervalSeconds(240);
    await reloaded.setHiddenRadioStatsIntervalSeconds(17);
    await reloaded.setPowerSavingProfile(PowerSavingProfile.maximum);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.uiNotificationIntervalMilliseconds, 500);
    expect(reloaded.settings.powerSaving.custom.uiNotificationIntervalMilliseconds, 750);
    await reloaded.setPowerSavingProfile(PowerSavingProfile.custom);
    await reloaded.setUiNotificationIntervalMilliseconds(-1);
    reloaded = await _loadSettings();
    final options = reloaded.settings.powerSaving.effective;
    expect(options.uiNotificationIntervalMilliseconds, 50);
    expect(options.pauseHiddenGifs, isTrue);
    expect(options.pauseIdleImageCleanup, isTrue);
    expect(options.pauseHiddenRadioIndicator, isTrue);
    expect(options.batteryIntervalSeconds, 300);
    expect(options.gpsIntervalSeconds, 240);
    expect(options.hiddenRadioStatsIntervalSeconds, 17);
    _expectDeliveryChoices(reloaded.settings);
  });

  test('hidden GIF pause persists independently without enabling the profile',
      () async {
    final service = await _loadSettings();
    await service.setPauseHiddenGifs(true);
    expect(service.settings.powerSaving.profile, PowerSavingProfile.disabled);
    expect(service.settings.powerSaving.effective.pauseHiddenGifs, isFalse);
    expect(service.settings.powerSaving.custom.pauseIdleImageCleanup, isFalse);
    expect(service.settings.powerSaving.custom.pauseHiddenRadioIndicator, isFalse);
    await service.setPowerSavingProfile(PowerSavingProfile.custom);
    var reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.pauseHiddenGifs, isTrue);
    await reloaded.setPauseIdleImageCleanup(true);
    await reloaded.setPauseHiddenRadioIndicator(true);
    await reloaded.setBatteryPollingIntervalSeconds(300);
    await reloaded.setGpsPollingIntervalSeconds(240);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.pauseHiddenGifs, isTrue);
    await reloaded.setPauseHiddenGifs(false);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.pauseHiddenGifs, isFalse);
    expect(reloaded.settings.powerSaving.effective.pauseIdleImageCleanup, isTrue);
    expect(reloaded.settings.powerSaving.effective.pauseHiddenRadioIndicator, isTrue);
    expect(reloaded.settings.powerSaving.effective.batteryIntervalSeconds, 300);
    expect(reloaded.settings.powerSaving.effective.gpsIntervalSeconds, 240);
    _expectDeliveryChoices(reloaded.settings);
  });

  test('idle image cleanup persists independently without enabling the profile',
      () async {
    final service = await _loadSettings();
    await service.setPauseIdleImageCleanup(true);
    expect(service.settings.powerSaving.profile, PowerSavingProfile.disabled);
    expect(service.settings.powerSaving.effective.pauseIdleImageCleanup, isFalse);
    expect(service.settings.powerSaving.custom.pauseHiddenRadioIndicator, isFalse);
    await service.setPowerSavingProfile(PowerSavingProfile.custom);
    var reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.pauseIdleImageCleanup, isTrue);
    await reloaded.setBatteryPollingIntervalSeconds(300);
    await reloaded.setGpsPollingIntervalSeconds(240);
    await reloaded.setHiddenRadioStatsIntervalSeconds(17);
    await reloaded.setPauseHiddenRadioIndicator(true);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.pauseIdleImageCleanup, isTrue);
    await reloaded.setPauseIdleImageCleanup(false);
    reloaded = await _loadSettings();
    expect(reloaded.settings.powerSaving.effective.pauseIdleImageCleanup, isFalse);
    expect(reloaded.settings.powerSaving.effective.pauseHiddenRadioIndicator, isTrue);
    expect(reloaded.settings.powerSaving.effective.hiddenRadioStatsIntervalSeconds, 17);
    expect(reloaded.settings.powerSaving.effective.batteryIntervalSeconds, 300);
    expect(reloaded.settings.powerSaving.effective.gpsIntervalSeconds, 240);
    _expectDeliveryChoices(reloaded.settings);
  });
}
