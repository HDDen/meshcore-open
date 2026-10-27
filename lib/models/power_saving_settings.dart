import 'cpu_sleep_options.dart';
import 'ble_power_options.dart';
import 'ios_immortalizer_power_options.dart';

enum PowerSavingProfile { disabled, balanced, economical, maximum, custom }

class PowerSavingOptions {
  const PowerSavingOptions({
    this.iosImmortalizer = const IosImmortalizerPowerOptions(),
    this.cpuSleep = const CpuSleepOptions(),
    this.bleConnectionPriority = BleConnectionPriorityMode.original,
    this.blePeripheralLatency = BlePeripheralLatencyMode.original,
    this.releaseTcpWifiLock = false,
    this.reduceDeliveryObservationWrites = false,
    this.hiddenRadioStatsIntervalSeconds = 1,
    this.pauseHiddenRadioIndicator = false,
    this.pauseIdleImageCleanup = false,
    this.pauseHiddenGifs = false,
    this.deferBleLogDescriptions = false,
    this.reduceBlePluginLogs = false,
    this.pauseHiddenStatusAnimations = false,
    this.disableContinuousStatusAnimations = false,
    this.cacheChannelKeyHashes = false,
    this.skipIdleDirectProgressParsing = false,
    this.uiNotificationIntervalMilliseconds = minUiNotificationInterval,
    this.batteryIntervalSeconds = minBatteryInterval,
    this.gpsIntervalSeconds = minGpsInterval,
    this.backgroundReconnectIntervalSeconds = minBackgroundReconnectInterval,
  }) : assert(uiNotificationIntervalMilliseconds >= minUiNotificationInterval),
      assert(uiNotificationIntervalMilliseconds <= maxUiNotificationInterval),
      assert(uiNotificationIntervalMilliseconds % uiNotificationIntervalStep == 0),
      assert(hiddenRadioStatsIntervalSeconds >= 1),
      assert(hiddenRadioStatsIntervalSeconds <= 60),
      assert(batteryIntervalSeconds >= minBatteryInterval),
      assert(batteryIntervalSeconds <= maxBatteryInterval),
      assert(batteryIntervalSeconds % deviceIntervalStep == 0),
      assert(gpsIntervalSeconds >= minGpsInterval),
      assert(gpsIntervalSeconds <= maxGpsInterval),
      assert(gpsIntervalSeconds % deviceIntervalStep == 0),
      assert(backgroundReconnectIntervalSeconds >= minBackgroundReconnectInterval),
      assert(backgroundReconnectIntervalSeconds <= maxBackgroundReconnectInterval),
      assert(backgroundReconnectIntervalSeconds % backgroundReconnectIntervalStep == 0);

  static const minRadioStatsInterval = 1;
  static const maxRadioStatsInterval = 60;
  static const minBatteryInterval = 120;
  static const maxBatteryInterval = 600;
  static const minGpsInterval = 60;
  static const maxGpsInterval = 600;
  static const deviceIntervalStep = 60;
  static const minUiNotificationInterval = 50;
  static const maxUiNotificationInterval = 1000;
  static const uiNotificationIntervalStep = 50;
  static const minBackgroundReconnectInterval = 30;
  static const maxBackgroundReconnectInterval = 600;
  static const backgroundReconnectIntervalStep = 30;

  final CpuSleepOptions cpuSleep;
  final IosImmortalizerPowerOptions iosImmortalizer;
  final BleConnectionPriorityMode bleConnectionPriority;
  final BlePeripheralLatencyMode blePeripheralLatency;
  final bool releaseTcpWifiLock;
  final bool reduceDeliveryObservationWrites;
  final int hiddenRadioStatsIntervalSeconds;
  final bool pauseHiddenRadioIndicator;
  final bool pauseIdleImageCleanup;
  final bool pauseHiddenGifs;
  final bool deferBleLogDescriptions;
  final bool reduceBlePluginLogs;
  final bool pauseHiddenStatusAnimations;
  final bool disableContinuousStatusAnimations;
  final bool cacheChannelKeyHashes;
  final bool skipIdleDirectProgressParsing;
  final int uiNotificationIntervalMilliseconds;
  final int batteryIntervalSeconds;
  final int gpsIntervalSeconds;
  final int backgroundReconnectIntervalSeconds;

  static int _reconnectInterval(Object? value) {
    if (value is! int) return minBackgroundReconnectInterval;
    return value.clamp(minBackgroundReconnectInterval, maxBackgroundReconnectInterval) ~/
        backgroundReconnectIntervalStep * backgroundReconnectIntervalStep;
  }

  static int _deviceInterval(Object? value, int minimum, int maximum) {
    if (value is! int) return minimum;
    final bounded = value.clamp(minimum, maximum).toInt();
    return minimum + ((bounded - minimum) ~/ deviceIntervalStep) *
        deviceIntervalStep;
  }

  static int _uiInterval(Object? value) {
    if (value is! int) return minUiNotificationInterval;
    return value.clamp(minUiNotificationInterval, maxUiNotificationInterval) ~/
        uiNotificationIntervalStep * uiNotificationIntervalStep;
  }

  PowerSavingOptions copyWith({
    IosImmortalizerPowerOptions? iosImmortalizer,
    CpuSleepOptions? cpuSleep,
    BleConnectionPriorityMode? bleConnectionPriority,
    BlePeripheralLatencyMode? blePeripheralLatency,
    bool? releaseTcpWifiLock,
    bool? reduceDeliveryObservationWrites,
    int? hiddenRadioStatsIntervalSeconds,
    bool? pauseHiddenRadioIndicator,
    bool? pauseIdleImageCleanup,
    bool? pauseHiddenGifs,
    bool? deferBleLogDescriptions,
    bool? reduceBlePluginLogs,
    bool? pauseHiddenStatusAnimations,
    bool? disableContinuousStatusAnimations,
    bool? cacheChannelKeyHashes,
    bool? skipIdleDirectProgressParsing,
    int? uiNotificationIntervalMilliseconds,
    int? batteryIntervalSeconds,
    int? gpsIntervalSeconds,
    int? backgroundReconnectIntervalSeconds,
  }) =>
      PowerSavingOptions(
        iosImmortalizer: iosImmortalizer ?? this.iosImmortalizer,
        cpuSleep: cpuSleep ?? this.cpuSleep,
        bleConnectionPriority: bleConnectionPriority ?? this.bleConnectionPriority,
        blePeripheralLatency: blePeripheralLatency ?? this.blePeripheralLatency,
        releaseTcpWifiLock: releaseTcpWifiLock ?? this.releaseTcpWifiLock,
        reduceDeliveryObservationWrites:
            reduceDeliveryObservationWrites ?? this.reduceDeliveryObservationWrites,
        backgroundReconnectIntervalSeconds: _reconnectInterval(
          backgroundReconnectIntervalSeconds ?? this.backgroundReconnectIntervalSeconds,
        ),
        hiddenRadioStatsIntervalSeconds: (hiddenRadioStatsIntervalSeconds ??
            this.hiddenRadioStatsIntervalSeconds)
            .clamp(minRadioStatsInterval, maxRadioStatsInterval).toInt(),
        pauseHiddenRadioIndicator:
            pauseHiddenRadioIndicator ?? this.pauseHiddenRadioIndicator,
        pauseIdleImageCleanup: pauseIdleImageCleanup ?? this.pauseIdleImageCleanup,
        pauseHiddenGifs: pauseHiddenGifs ?? this.pauseHiddenGifs,
        deferBleLogDescriptions: deferBleLogDescriptions ?? this.deferBleLogDescriptions,
        reduceBlePluginLogs: reduceBlePluginLogs ?? this.reduceBlePluginLogs,
        pauseHiddenStatusAnimations:
            pauseHiddenStatusAnimations ?? this.pauseHiddenStatusAnimations,
        disableContinuousStatusAnimations:
            disableContinuousStatusAnimations ?? this.disableContinuousStatusAnimations,
        cacheChannelKeyHashes: cacheChannelKeyHashes ?? this.cacheChannelKeyHashes,
        skipIdleDirectProgressParsing:
            skipIdleDirectProgressParsing ?? this.skipIdleDirectProgressParsing,
        uiNotificationIntervalMilliseconds: _uiInterval(
          uiNotificationIntervalMilliseconds ?? this.uiNotificationIntervalMilliseconds,
        ),
        batteryIntervalSeconds: _deviceInterval(
          batteryIntervalSeconds ?? this.batteryIntervalSeconds,
          minBatteryInterval, maxBatteryInterval,
        ),
        gpsIntervalSeconds: _deviceInterval(
          gpsIntervalSeconds ?? this.gpsIntervalSeconds,
          minGpsInterval, maxGpsInterval,
        ),
      );

  factory PowerSavingOptions.fromJson(Object? json) {
    final value = json is Map
        ? json['hidden_radio_stats_interval_seconds'] : null;
    return PowerSavingOptions(
      iosImmortalizer: IosImmortalizerPowerOptions.fromJson(json is Map ? json['ios_immortalizer'] : null),
      cpuSleep: CpuSleepOptions.fromJson(json is Map ? json['cpu_sleep'] : null),
      releaseTcpWifiLock: json is Map && json['release_tcp_wifi_lock'] == true,
      reduceDeliveryObservationWrites:
          json is Map && json['reduce_delivery_observation_writes'] == true,
      bleConnectionPriority: bleConnectionPriorityFromJson(
        json is Map ? json['ble_connection_priority'] : null,
      ),
      blePeripheralLatency: blePeripheralLatencyFromJson(
        json is Map ? json['ble_peripheral_latency'] : null,
      ),
      backgroundReconnectIntervalSeconds: _reconnectInterval(json is Map
          ? json['background_reconnect_interval_seconds'] : null),
      hiddenRadioStatsIntervalSeconds: value is int
          ? value.clamp(minRadioStatsInterval, maxRadioStatsInterval).toInt()
          : minRadioStatsInterval,
      pauseHiddenRadioIndicator: json is Map &&
          json['pause_hidden_radio_indicator'] == true,
      pauseIdleImageCleanup: json is Map && json['pause_idle_image_cleanup'] == true,
      pauseHiddenGifs: json is Map && json['pause_hidden_gifs'] == true,
      deferBleLogDescriptions: json is Map && json['defer_ble_log_descriptions'] == true,
      reduceBlePluginLogs: json is Map && json['reduce_ble_plugin_logs'] == true,
      pauseHiddenStatusAnimations:
          json is Map && json['pause_hidden_status_animations'] == true,
      disableContinuousStatusAnimations:
          json is Map && json['disable_continuous_status_animations'] == true,
      cacheChannelKeyHashes: json is Map && json['cache_channel_key_hashes'] == true,
      skipIdleDirectProgressParsing:
          json is Map && json['skip_idle_direct_progress_parsing'] == true,
      uiNotificationIntervalMilliseconds: _uiInterval(json is Map
          ? json['ui_notification_interval_milliseconds'] : null),
      batteryIntervalSeconds: _deviceInterval(
        json is Map ? json['battery_interval_seconds'] : null,
        minBatteryInterval, maxBatteryInterval,
      ),
      gpsIntervalSeconds: _deviceInterval(
        json is Map ? json['gps_interval_seconds'] : null,
        minGpsInterval, maxGpsInterval,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    if (!iosImmortalizer.isOriginal) 'ios_immortalizer': iosImmortalizer.toJson(),
    if (cpuSleep.enabled) 'cpu_sleep': cpuSleep.toJson(),
    if (releaseTcpWifiLock) 'release_tcp_wifi_lock': true,
    if (reduceDeliveryObservationWrites) 'reduce_delivery_observation_writes': true,
    if (bleConnectionPriority != BleConnectionPriorityMode.original)
      'ble_connection_priority': bleConnectionPriority.name,
    if (blePeripheralLatency != BlePeripheralLatencyMode.original)
      'ble_peripheral_latency': blePeripheralLatency.name,
    'background_reconnect_interval_seconds': backgroundReconnectIntervalSeconds,
    'hidden_radio_stats_interval_seconds': hiddenRadioStatsIntervalSeconds,
    'pause_hidden_radio_indicator': pauseHiddenRadioIndicator,
    'pause_idle_image_cleanup': pauseIdleImageCleanup,
    'pause_hidden_gifs': pauseHiddenGifs,
    'defer_ble_log_descriptions': deferBleLogDescriptions,
    'reduce_ble_plugin_logs': reduceBlePluginLogs,
    'pause_hidden_status_animations': pauseHiddenStatusAnimations,
    'disable_continuous_status_animations': disableContinuousStatusAnimations,
    'cache_channel_key_hashes': cacheChannelKeyHashes,
    'skip_idle_direct_progress_parsing': skipIdleDirectProgressParsing,
    'ui_notification_interval_milliseconds': uiNotificationIntervalMilliseconds,
    'battery_interval_seconds': batteryIntervalSeconds,
    'gps_interval_seconds': gpsIntervalSeconds,
  };
}

/// Presets select effective values without overwriting the saved custom ones.
class PowerSavingSettings {
  const PowerSavingSettings({
    this.profile = PowerSavingProfile.disabled,
    this.custom = const PowerSavingOptions(),
  });

  final PowerSavingProfile profile;
  final PowerSavingOptions custom;

  PowerSavingOptions get effective => switch (profile) {
    PowerSavingProfile.disabled => const PowerSavingOptions(),
    PowerSavingProfile.balanced => const PowerSavingOptions(
      backgroundReconnectIntervalSeconds: 60,
      skipIdleDirectProgressParsing: true,
      cacheChannelKeyHashes: true,
      pauseHiddenStatusAnimations: true,
      reduceBlePluginLogs: true,
      deferBleLogDescriptions: true,
      uiNotificationIntervalMilliseconds: 100,
      hiddenRadioStatsIntervalSeconds: 15,
      pauseHiddenRadioIndicator: true,
      pauseIdleImageCleanup: true,
      pauseHiddenGifs: true,
      batteryIntervalSeconds: 180,
      gpsIntervalSeconds: 120,
    ),
    PowerSavingProfile.economical => const PowerSavingOptions(
      cpuSleep: CpuSleepOptions(ble: true),
      backgroundReconnectIntervalSeconds: 180,
      skipIdleDirectProgressParsing: true,
      cacheChannelKeyHashes: true,
      pauseHiddenStatusAnimations: true,
      disableContinuousStatusAnimations: true,
      reduceBlePluginLogs: true,
      deferBleLogDescriptions: true,
      uiNotificationIntervalMilliseconds: 250,
      hiddenRadioStatsIntervalSeconds: 30,
      pauseHiddenRadioIndicator: true,
      pauseIdleImageCleanup: true,
      pauseHiddenGifs: true,
      batteryIntervalSeconds: 300,
      gpsIntervalSeconds: 300,
    ),
    PowerSavingProfile.maximum => const PowerSavingOptions(
      cpuSleep: CpuSleepOptions(always: true),
      backgroundReconnectIntervalSeconds: 600,
      skipIdleDirectProgressParsing: true,
      cacheChannelKeyHashes: true,
      pauseHiddenStatusAnimations: true,
      disableContinuousStatusAnimations: true,
      reduceBlePluginLogs: true,
      deferBleLogDescriptions: true,
      uiNotificationIntervalMilliseconds: 500,
      hiddenRadioStatsIntervalSeconds: 60,
      pauseHiddenRadioIndicator: true,
      pauseIdleImageCleanup: true,
      pauseHiddenGifs: true,
      batteryIntervalSeconds: 600,
      gpsIntervalSeconds: 600,
    ),
    PowerSavingProfile.custom => custom,
  };

  PowerSavingSettings copyWith({
    PowerSavingProfile? profile,
    PowerSavingOptions? custom,
  }) => PowerSavingSettings(
    profile: profile ?? this.profile,
    custom: custom ?? this.custom,
  );

  factory PowerSavingSettings.fromJson(Object? json) {
    if (json is! Map) return const PowerSavingSettings();
    var profile = PowerSavingProfile.disabled;
    for (final candidate in PowerSavingProfile.values) {
      if (candidate.name == json['profile']) {
        profile = candidate;
        break;
      }
    }
    return PowerSavingSettings(
      profile: profile,
      custom: PowerSavingOptions.fromJson(json['custom']),
    );
  }

  Map<String, dynamic> toJson() => {
    'profile': profile.name,
    'custom': custom.toJson(),
  };
}
