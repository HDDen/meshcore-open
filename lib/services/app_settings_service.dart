import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mco_service/mco_service.dart';
import 'package:uuid/uuid.dart';
import '../models/app_settings.dart';
import '../models/app_settings_backup.dart';
import '../models/custom_theme.dart';
import '../models/holiday_schedule.dart';
import '../models/low_battery_alert_settings.dart';
import '../storage/channel_identity_store.dart';
import '../models/cpu_sleep_options.dart';
import '../models/power_saving_settings.dart';
import '../models/ble_power_options.dart';
import '../models/ios_immortalizer_power_options.dart';
import '../models/image_codec_support.dart';
import '../models/translation_support.dart';
import '../storage/prefs_manager.dart';
import '../utils/app_logger.dart';
import '../utils/battery_utils.dart';
import '../helpers/channel_binary_data_helper.dart';
import '../helpers/cyr2lat.dart';
import 'ios_background_tcp_service.dart';

export '../models/app_settings.dart' show ChannelNotificationMode;

class AppSettingsService extends ChangeNotifier {
  static const String _settingsKey = 'app_settings';

  AppSettingsService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  ActiveHoliday? _scheduledHoliday;
  Timer? _holidayTimer;
  bool _holidayForeground = false;

  AppSettings _settings = AppSettings();
  List<McoBatteryChemistryProfile> Function(String deviceId)?
  _extraBatteryProfilesForDevice;

  AppSettings get settings => _settings;

  void setExtraBatteryProfilesProvider(
    List<McoBatteryChemistryProfile> Function(String deviceId)? provider,
  ) {
    _extraBatteryProfilesForDevice = provider;
  }

  McoBatteryChemistryProfile? _extraBatteryProfileForDevice(
    String deviceId,
    String chemistry,
  ) {
    final profiles = _extraBatteryProfilesForDevice?.call(deviceId);
    if (profiles == null) return null;
    McoBatteryChemistryProfile? match;
    for (final profile in profiles) {
      if (profile.id == chemistry) match = profile;
    }
    return match;
  }

  int resolvedGpsIntervalSeconds(Map<String, String>? deviceCustomVars) {
    final deviceValue = int.tryParse(deviceCustomVars?['gps_interval'] ?? '');
    if (deviceValue != null && deviceValue >= 0) {
      return deviceValue;
    }
    return _settings.gpsIntervalSeconds;
  }

  String batteryChemistryForDevice(String deviceId) {
    final stored = _settings.batteryChemistryByDeviceId[deviceId];
    if (stored == 'liion') return 'nmc';
    return stored ?? 'nmc';
  }

  ({double minVolts, double maxVolts})? batteryCustomRangeForDevice(
    String deviceId,
  ) {
    final minVolts = _settings.batteryCustomMinVoltsByDeviceId[deviceId];
    final maxVolts = _settings.batteryCustomMaxVoltsByDeviceId[deviceId];
    if (minVolts == null || maxVolts == null) return null;
    if (minVolts <= 0 || maxVolts <= 0 || minVolts >= maxVolts) return null;
    return (minVolts: minVolts, maxVolts: maxVolts);
  }

  BatteryVoltageRange? batteryVoltageRangeForDevice(String deviceId) {
    final chemistry = batteryChemistryForDevice(deviceId);
    if (chemistry != batteryChemistryCustom) {
      final profile = _extraBatteryProfileForDevice(deviceId, chemistry);
      if (profile == null) return null;
      final minMv = (profile.minVolts * 1000).round();
      final maxMv = (profile.maxVolts * 1000).round();
      if (minMv >= maxMv) return null;
      return (minMv: minMv, maxMv: maxMv);
    } else {
      final range = batteryCustomRangeForDevice(deviceId);
      if (range == null) return null;
      final minMv = (range.minVolts * 1000).round();
      final maxMv = (range.maxVolts * 1000).round();
      if (minMv >= maxMv) return null;
      return (minMv: minMv, maxMv: maxMv);
    }
  }

  String batteryChemistryForRepeater(String repeaterPubKeyHex) {
    final stored = _settings.batteryChemistryByRepeaterId[repeaterPubKeyHex];
    if (stored == 'liion') return 'nmc';
    return stored ?? 'nmc';
  }

  Future<void> loadSettings() async {
    final prefs = PrefsManager.instance;
    final jsonStr = prefs.getString(_settingsKey);

    if (jsonStr != null) {
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        final loadedSettings = AppSettings.fromJson(json);
        _settings = _normalizeRuntimeDependentSettings(loadedSettings);
        _applyRuntimeSettings();
        if (_settings.channelsSendAsBinary !=
            loadedSettings.channelsSendAsBinary) {
          await _saveSettings();
        }
        _syncHolidaySchedule();
        notifyListeners();
      } catch (e) {
        // If parsing fails, use defaults
        _settings = _normalizeRuntimeDependentSettings(AppSettings());
        _applyRuntimeSettings();
        _syncHolidaySchedule();
      }
    } else {
      _settings = _normalizeRuntimeDependentSettings(AppSettings());
      _applyRuntimeSettings();
      _syncHolidaySchedule();
    }
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    final autoSwitchChanged =
        _settings.holidayAutoSwitch != newSettings.holidayAutoSwitch;
    _settings = _normalizeRuntimeDependentSettings(newSettings);
    _applyRuntimeSettings();
    if (autoSwitchChanged) _syncHolidaySchedule();
    notifyListeners();

    await _saveSettings();
  }

  Future<bool> restoreAppSettingsBackup(AppSettingsBackupPreview preview) async {
    final next = preview.applyTo(_settings);
    if (next == null) return false;
    if (!identical(next, _settings)) await updateSettings(next);
    return true;
  }

  Future<void> _saveSettings() async {
    final prefs = PrefsManager.instance;
    final jsonStr = jsonEncode(_settings.toJson());
    await prefs.setString(_settingsKey, jsonStr);
  }

  AppSettings _normalizeRuntimeDependentSettings(AppSettings settings) {
    final adaptive = settings.adaptiveTxPower;
    final enabled = settings.channelMinHopsEnabled && adaptive.enabled;
    final channelRetries = adaptive.channelRetries
        .clamp(0, settings.channelMinHopsRetries.clamp(0, 10)).toInt();
    final forcedFloodRetries = adaptive.forcedFloodRetries
        .clamp(0, settings.maxMessageRetries.clamp(0, 10)).toInt();
    if (enabled != adaptive.enabled ||
        channelRetries != adaptive.channelRetries ||
        forcedFloodRetries != adaptive.forcedFloodRetries) {
      settings = settings.copyWith(adaptiveTxPower: adaptive.copyWith(
        enabled: enabled,
        channelRetries: channelRetries,
        forcedFloodRetries: forcedFloodRetries,
      ));
    }
    if (!ChannelBinaryDataHelper.isAvailable && settings.channelsSendAsBinary) {
      return settings.copyWith(channelsSendAsBinary: false);
    }
    return settings;
  }

  void _applyRuntimeSettings() {
    Cyr2Lat.setCharMap(_settings.cyr2latCharMap);
    ChannelBinaryDataHelper.sendEnabled = _settings.channelsSendAsBinary;
  }

  Future<void> setClearPathOnMaxRetry(bool value) async {
    await updateSettings(_settings.copyWith(clearPathOnMaxRetry: value));
  }

  Future<void> setBleConnectionPriorityMode(BleConnectionPriorityMode mode) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(bleConnectionPriority: mode),
      ),
    ));
  }

  Future<void> setBlePeripheralLatencyMode(BlePeripheralLatencyMode mode) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(blePeripheralLatency: mode),
      ),
    ));
  }

  Future<void> setReleaseTcpWifiLock(bool value) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(releaseTcpWifiLock: value),
      ),
    ));
  }

  Future<void> setIosImmortalizerPowerOptions(IosImmortalizerPowerOptions value) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(iosImmortalizer: value),
      ),
    ));
  }

  Future<void> setPowerSavingProfile(PowerSavingProfile profile) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(profile: profile),
    ));
  }

  Future<void> setReduceDeliveryObservationWrites(bool value) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(reduceDeliveryObservationWrites: value),
      ),
    ));
  }

  Future<void> setBackgroundReconnectIntervalSeconds(int seconds) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(
          backgroundReconnectIntervalSeconds: seconds,
        ),
      ),
    ));
  }

  Future<void> setUiNotificationIntervalMilliseconds(int milliseconds) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(
          uiNotificationIntervalMilliseconds: milliseconds,
        ),
      ),
    ));
  }

  Future<void> setHiddenRadioStatsIntervalSeconds(int seconds) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(
          hiddenRadioStatsIntervalSeconds: seconds,
        ),
      ),
    ));
  }

  Future<void> setPauseHiddenRadioIndicator(bool value) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(
          pauseHiddenRadioIndicator: value,
        ),
      ),
    ));
  }

  Future<void> setBatteryPollingIntervalSeconds(int seconds) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(
          batteryIntervalSeconds: seconds,
        ),
      ),
    ));
  }

  Future<void> setPauseIdleImageCleanup(bool value) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(
          pauseIdleImageCleanup: value,
        ),
      ),
    ));
  }

  Future<void> setPauseHiddenGifs(bool value) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(pauseHiddenGifs: value),
      ),
    ));
  }

  Future<void> setDeferBleLogDescriptions(bool value) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(deferBleLogDescriptions: value),
      ),
    ));
  }

  Future<void> setReduceBlePluginLogs(bool value) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(reduceBlePluginLogs: value),
      ),
    ));
  }

  Future<void> setGpsPollingIntervalSeconds(int seconds) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(
          gpsIntervalSeconds: seconds,
        ),
      ),
    ));
  }

  Future<void> setPauseHiddenStatusAnimations(bool value) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(pauseHiddenStatusAnimations: value),
      ),
    ));
  }

  Future<void> setDisableContinuousStatusAnimations(bool value) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(disableContinuousStatusAnimations: value),
      ),
    ));
  }

  Future<void> setCacheChannelKeyHashes(bool value) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(cacheChannelKeyHashes: value),
      ),
    ));
  }

  Future<void> setCpuSleepOptions(CpuSleepOptions value) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(cpuSleep: value),
      ),
    ));
  }

  Future<void> setSkipIdleDirectProgressParsing(bool value) async {
    await updateSettings(_settings.copyWith(
      powerSaving: _settings.powerSaving.copyWith(
        custom: _settings.powerSaving.custom.copyWith(skipIdleDirectProgressParsing: value),
      ),
    ));
  }

  Future<void> setMapShowRepeaters(bool value) async {
    await updateSettings(_settings.copyWith(mapShowRepeaters: value));
  }

  Future<void> setMapShowChatNodes(bool value) async {
    await updateSettings(_settings.copyWith(mapShowChatNodes: value));
  }

  Future<void> setMapShowOtherNodes(bool value) async {
    await updateSettings(_settings.copyWith(mapShowOtherNodes: value));
  }

  Future<void> setMapShowOnlineLinks(bool value) =>
      updateSettings(_settings.copyWith(mapShowOnlineLinks: value));

  Future<void> setPathTraceHighTimeoutEnabled(bool value) async {
    await updateSettings(
      _settings.copyWith(pathTraceHighTimeoutEnabled: value),
    );
  }

  Future<void> setMapShowOverlaps(bool value) async {
    await updateSettings(_settings.copyWith(mapShowOverlaps: value));
  }

  Future<void> setMapTimeFilterHours(double value) async {
    await updateSettings(_settings.copyWith(mapTimeFilterHours: value));
  }

  Future<void> setMapKeyPrefixEnabled(bool value) async {
    await updateSettings(_settings.copyWith(mapKeyPrefixEnabled: value));
  }

  Future<void> setMapKeyPrefix(String value) async {
    await updateSettings(_settings.copyWith(mapKeyPrefix: value));
  }

  Future<void> setMapShowMarkers(bool value) async {
    await updateSettings(_settings.copyWith(mapShowMarkers: value));
  }

  Future<void> setMapShowGuessedLocations(bool value) async {
    await updateSettings(_settings.copyWith(mapShowGuessedLocations: value));
  }

  Future<void> setMapClusterNodes(bool value) async {
    await updateSettings(_settings.copyWith(mapClusterNodes: value));
  }

  Future<void> setEnableMessageTracing(bool value) async {
    await updateSettings(_settings.copyWith(enableMessageTracing: value));
  }

  Future<void> setEnableTimeSeconds(bool value) async {
    await updateSettings(_settings.copyWith(enableTimeSeconds: value));
  }

  Future<void> setShowKeyboardHidingButton(bool value) async {
    await updateSettings(_settings.copyWith(showKeyboardHidingButton: value));
  }

  Future<void> setCanvasActive(bool value) async {
    await updateSettings(_settings.copyWith(canvasActive: value));
  }

  Future<void> setCanvasShowLockButton(bool value) async {
    await updateSettings(_settings.copyWith(canvasShowLockButton: value));
  }

  Future<void> setShowHops(bool value) async {
    await updateSettings(_settings.copyWith(showHops: value));
  }

  Future<void> setHideChannelIndexIndicator(bool value) async {
    await updateSettings(_settings.copyWith(hideChannelIndexIndicator: value));
  }

  Future<void> setCheckGitHubUpdates(bool value) async {
    await updateSettings(_settings.copyWith(checkGitHubUpdates: value));
  }

  Future<void> setShowChannelPreviewSender(bool value) async {
    await updateSettings(_settings.copyWith(showChannelPreviewSender: value));
  }

  Future<void> setHideChannelMuteButton(bool value) async {
    await updateSettings(_settings.copyWith(hideChannelMuteButton: value));
  }

  Future<void> setHideRadioStatsButton(bool value) async {
    await updateSettings(_settings.copyWith(hideRadioStatsButton: value));
  }

  Future<void> setSnrIndicatorAllRepActivity(bool value) async {
    await updateSettings(_settings.copyWith(snrIndicatorAllRepActivity: value));
  }

  Future<void> setHideMapZoomControls(bool value) async {
    await updateSettings(_settings.copyWith(hideMapZoomControls: value));
  }

  Future<void> setAlwaysRequestMapLocation(bool value) async {
    await updateSettings(_settings.copyWith(alwaysRequestMapLocation: value));
  }

  Future<void> setShowMcoImageResolution(bool value) async {
    await updateSettings(_settings.copyWith(showMcoImageResolution: value));
  }

  Future<void> setShowMcoImageFormat(bool value) async {
    await updateSettings(_settings.copyWith(showMcoImageFormat: value));
  }

  Future<void> setShowMcoImageAlgorithm(bool value) async {
    await updateSettings(_settings.copyWith(showMcoImageAlgorithm: value));
  }

  Future<void> setShowMcoImageBytes(bool value) async {
    await updateSettings(_settings.copyWith(showMcoImageBytes: value));
  }

  Future<void> setShowMcoImagePackReplacements(bool value) async {
    await updateSettings(
      _settings.copyWith(showMcoImagePackReplacements: value),
    );
  }

  Future<void> setMcoImageReplacementsScale(double value) async {
    await updateSettings(_settings.copyWith(mcoImageReplacementsScale: value));
  }

  Future<void> setMcoImageReplacementsLottieScalePercent(int value) async {
    await updateSettings(
      _settings.copyWith(
        mcoImageReplacementsLottieScalePercent: value.clamp(10, 100).toInt(),
      ),
    );
  }

  Future<void> setSenderNameScalePercent(int value) async {
    await updateSettings(
      _settings.copyWith(
        senderNameScalePercent: AppSettings.snapSenderNameScalePercent(value),
      ),
    );
  }

  Future<void> setMcoImageScaleNearestNeighbor(bool value) async {
    await updateSettings(
      _settings.copyWith(mcoImageScaleNearestNeighbor: value),
    );
  }

  Future<void> setMcoImageReplacementsSharpness(int value) async {
    await updateSettings(
      _settings.copyWith(mcoImageReplacementsSharpness: value),
    );
  }

  Future<void> setUiScale(double value) async {
    await updateSettings(_settings.copyWith(uiScale: value));
  }

  Future<void> setUiScaleApplyToIcons(bool value) async {
    await updateSettings(_settings.copyWith(uiScaleApplyToIcons: value));
  }

  Future<void> setShowCompressionRatio(bool value) async {
    await updateSettings(_settings.copyWith(showCompressionRatio: value));
  }

  Future<void> setCompressionRatioWithSenderName(bool value) async {
    await updateSettings(
      _settings.copyWith(compressionRatioWithSenderName: value),
    );
  }

  Future<void> setMonochromeSenderNames(bool value) async {
    await updateSettings(_settings.copyWith(monochromeSenderNames: value));
  }

  Future<void> setShowMessageRegion(bool value) async {
    await updateSettings(_settings.copyWith(showMessageRegion: value));
  }

  Future<void> setChannelsUnreadSorting(bool value) async {
    await updateSettings(_settings.copyWith(channelsUnreadSorting: value));
  }

  Future<void> setIncomingQuoteAsMentions(bool value) async {
    await updateSettings(_settings.copyWith(incomingQuoteAsMentions: value));
  }

  Future<void> setExactQuote(bool value) async {
    await updateSettings(_settings.copyWith(exactQuote: value));
  }

  Future<void> setExactQuoteLatest(bool value) async {
    await updateSettings(_settings.copyWith(exactQuoteLatest: value));
  }

  Future<void> setExactQuoteLimit(int value) async {
    await updateSettings(
      _settings.copyWith(
        exactQuoteLimit: AppSettings.normalizeExactQuoteLimit(value),
      ),
    );
  }

  Future<void> setShowLastHopSignal(bool value) async {
    await updateSettings(_settings.copyWith(showLastHopSignal: value));
  }

  Future<void> setRecoverLongPacketEchoes(bool value) async {
    await updateSettings(_settings.copyWith(recoverLongPacketEchoes: value));
  }

  Future<void> setDirectEchoRecovery(bool value) async {
    await updateSettings(_settings.copyWith(directEchoRecovery: value));
  }

  Future<void> setSuppressPhantomChannels(bool value) async {
    await updateSettings(_settings.copyWith(suppressPhantomChannels: value));
    try {
      await const IosBackgroundTcpService().updatePhantomChannelSuppression(
        _settings.suppressPhantomChannels,
      );
    } catch (error) {
      appLogger.warn(
        'Could not update phantom channel suppression: $error',
        tag: 'iOS TCP',
      );
    }
  }

  Future<void> handleDirectEchoRecoveryPrompt({required bool enable}) async {
    await updateSettings(
      _settings.copyWith(
        directEchoRecovery: enable ? true : _settings.directEchoRecovery,
        directEchoRecoveryPromptHandled: true,
      ),
    );
  }

  Future<void> setSimplifiedMentions(bool value) async {
    await updateSettings(_settings.copyWith(simplifiedMentions: value));
  }

  Future<void> setSharedMessageHistoryMode(
    SharedMessageHistoryMode value,
  ) async {
    await updateSettings(_settings.copyWith(sharedMessageHistoryMode: value));
  }

  Future<void> setNoRetransmissionWarningSeconds(int value) async {
    await updateSettings(
      _settings.copyWith(noRetransmissionWarningSeconds: value),
    );
  }

  Future<void> setBackgroundTcpEnabled(bool value) async {
    await updateSettings(_settings.copyWith(backgroundTcpEnabled: value));
  }

  Future<void> setRoomServerShowNotemptyOnChatscreen(bool value) async {
    await updateSettings(
      _settings.copyWith(roomServerShowNotemptyOnChatscreen: value),
    );
  }

  Future<void> setRoomServerShowNotemptyContactsOnChatscreen(bool value) async {
    await updateSettings(
      _settings.copyWith(roomServerShowNotemptyContactsOnChatscreen: value),
    );
  }

  Future<void> setRoomServerDisableRoomAndContactsSorting(bool value) async {
    await updateSettings(
      _settings.copyWith(roomServerDisableRoomAndContactsSorting: value),
    );
  }

  Future<void> setMapCacheBounds(Map<String, double>? value) async {
    await updateSettings(_settings.copyWith(mapCacheBounds: value));
  }

  Future<void> setMapCacheZoomRange(int minZoom, int maxZoom) async {
    final safeMin = minZoom <= maxZoom ? minZoom : maxZoom;
    final safeMax = minZoom <= maxZoom ? maxZoom : minZoom;
    await updateSettings(
      _settings.copyWith(mapCacheMinZoom: safeMin, mapCacheMaxZoom: safeMax),
    );
  }

  Future<void> setMapRasterSourceId(String value) async {
    await updateSettings(_settings.copyWith(mapRasterSourceId: value));
  }

  Future<void> setMapTileEndpointId(String value) async {
    await updateSettings(_settings.copyWith(mapTileEndpointId: value));
  }

  Future<void> setMapTileApiKey(String? value) async {
    final normalized = value?.trim();
    await updateSettings(
      _settings.copyWith(
        mapTileApiKey: (normalized == null || normalized.isEmpty)
            ? null
            : normalized,
      ),
    );
  }

  Future<void> setMapYandexApiKey(String? value) async {
    final normalized = value?.trim();
    await updateSettings(
      _settings.copyWith(
        mapYandexApiKey: (normalized == null || normalized.isEmpty)
            ? null
            : normalized,
      ),
    );
  }

  Future<void> setMapYandexSigningSecret(String? value) async {
    final normalized = value?.trim();
    await updateSettings(
      _settings.copyWith(
        mapYandexSigningSecret: (normalized == null || normalized.isEmpty)
            ? null
            : normalized,
      ),
    );
  }

  Future<void> setMapYandexTileScale(double value) async {
    await updateSettings(
      _settings.copyWith(
        mapYandexTileScale: AppSettings.normalizeMapYandexTileScale(value),
      ),
    );
  }

  Future<void> setLowBatteryAlertsEnabled(bool enabled) async {
    await updateSettings(_settings.copyWith(
      lowBatteryAlerts: _settings.lowBatteryAlerts.copyWith(enabled: enabled),
    ));
  }

  Future<void> setLowBatteryAlertThreshold(int threshold, bool selected) async {
    if (!LowBatteryAlertSettings.supportedThresholds.contains(threshold)) return;
    final values = _settings.lowBatteryAlerts.thresholds.toSet();
    if (selected) {
      values.add(threshold);
    } else {
      values.remove(threshold);
    }
    await updateSettings(_settings.copyWith(
      lowBatteryAlerts: _settings.lowBatteryAlerts.copyWith(thresholds: values.toList()),
    ));
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await updateSettings(_settings.copyWith(notificationsEnabled: value));
  }

  Future<void> setNotifyOnNewMessage(bool value) async {
    await updateSettings(_settings.copyWith(notifyOnNewMessage: value));
  }

  Future<void> setNotifyOnNewChannelMessage(bool value) async {
    await updateSettings(_settings.copyWith(notifyOnNewChannelMessage: value));
  }

  Future<void> setNotifyOnNewAdvert(bool value) async {
    await updateSettings(_settings.copyWith(notifyOnNewAdvert: value));
  }

  Future<void> setAutoSendZeroHopAdvertOnGpsUpdate(bool value) async {
    await updateSettings(
      _settings.copyWith(autoSendZeroHopAdvertOnGpsUpdate: value),
    );
  }

  Future<void> setGpsIntervalSeconds(
    int value, {
    Future<void> Function(int value)? writeToDevice,
  }) async {
    await updateSettings(_settings.copyWith(gpsIntervalSeconds: value));
    if (writeToDevice == null) return;
    try {
      await writeToDevice(value);
    } catch (e) {
      appLogger.warn(
        'Failed to write GPS interval to device: $e',
        tag: 'AppSettings',
      );
    }
  }

  Future<void> setAutoRouteRotationEnabled(bool value) async {
    await updateSettings(_settings.copyWith(autoRouteRotationEnabled: value));
  }

  Future<void> setExperimentalRouteRanking(bool value) =>
      updateSettings(settings.copyWith(experimentalRouteRanking: value));

  Future<void> setMaxRouteWeight(double value) async {
    await updateSettings(_settings.copyWith(maxRouteWeight: value));
  }

  Future<void> setInitialRouteWeight(double value) async {
    await updateSettings(_settings.copyWith(initialRouteWeight: value));
  }

  Future<void> setRouteWeightSuccessIncrement(double value) async {
    await updateSettings(
      _settings.copyWith(routeWeightSuccessIncrement: value),
    );
  }

  Future<void> setRouteWeightFailureDecrement(double value) async {
    await updateSettings(
      _settings.copyWith(routeWeightFailureDecrement: value),
    );
  }

  Future<void> setMaxMessageRetries(int value) async {
    await updateSettings(_settings.copyWith(maxMessageRetries: value));
  }

  Future<void> resetRoutingSettingsToDefault() => updateSettings(
    settings.copyWith(
      maxRouteWeight: AppSettings.defaultMaxRouteWeight,
      initialRouteWeight: AppSettings.defaultInitialRouteWeight,
      routeWeightSuccessIncrement: AppSettings.defaultRouteWeightSuccessIncrement,
      routeWeightFailureDecrement: AppSettings.defaultRouteWeightFailureDecrement,
      maxMessageRetries: AppSettings.defaultMaxMessageRetries,
    ),
  );

  Future<void> setChannelResendTimeoutSeconds(int value) async {
    await updateSettings(
      _settings.copyWith(
        channelResendTimeoutSeconds:
            AppSettings.normalizeChannelResendTimeoutSeconds(value),
      ),
    );
  }

  Future<void> setChannelMinHopsEnabled(bool value) async {
    await updateSettings(_settings.copyWith(channelMinHopsEnabled: value));
  }

  Future<void> setChannelMinHops(int value) async {
    await updateSettings(_settings.copyWith(channelMinHops: value));
  }

  Future<void> setChannelMinHopsRetries(int value) async {
    await updateSettings(_settings.copyWith(channelMinHopsRetries: value));
  }

  Future<void> setChannelMinHopsDelaySeconds(int value) async {
    await updateSettings(
      _settings.copyWith(channelMinHopsDelaySeconds: value),
    );
  }

  Future<void> setChannelMinHopsCountRepeaters(bool value) async {
    await updateSettings(
      _settings.copyWith(channelMinHopsCountRepeaters: value),
    );
  }

  Future<void> setChannelMinHopsRepeaterCount(int value) async {
    await updateSettings(
      _settings.copyWith(channelMinHopsRepeaterCount: value.clamp(2, 10).toInt()),
    );
  }

  Future<void> setRegionOnHopsLine(bool value) async {
    await updateSettings(_settings.copyWith(regionOnHopsLine: value));
  }

  Future<void> setThemeMode(String value) async {
    await updateSettings(
      _dismissAutoHoliday(
        _settings.copyWith(themeMode: value, activeThemeId: null),
      ),
    );
  }

  CustomTheme? get chosenCustomTheme => _themeById(_settings.activeThemeId);

  CustomTheme? get activeCustomTheme => autoHolidayTheme ?? chosenCustomTheme;

  ActiveHoliday? get autoHoliday {
    final holiday = _scheduledHoliday;
    if (holiday == null ||
        _settings.holidayThemeDismissed == holiday.occurrenceKey ||
        _settings.activeThemeId == holiday.themeId) {
      return null;
    }
    return holiday;
  }

  CustomTheme? get autoHolidayTheme => _themeById(autoHoliday?.themeId);

  AppSettings _dismissAutoHoliday(AppSettings next) {
    final holiday = _scheduledHoliday;
    return holiday == null
        ? next
        : next.copyWith(holidayThemeDismissed: holiday.occurrenceKey);
  }

  Future<void> setHolidayAutoSwitch(bool enabled) async {
    if (_settings.holidayAutoSwitch == enabled) return;
    await updateSettings(
      _settings.copyWith(
        holidayAutoSwitch: enabled,
        holidayThemeDismissed: enabled ? null : _settings.holidayThemeDismissed,
      ),
    );
  }

  Future<void> setHolidayAnimationsEnabled(bool enabled) =>
      updateSettings(_settings.copyWith(holidayAnimationsEnabled: enabled));

  /// Date tracking is owned by the app's foreground lifecycle.
  void setHolidayThemeForeground(bool foreground) {
    if (_holidayForeground == foreground) return;
    _holidayForeground = foreground;
    if (foreground) {
      _refreshHolidayDate();
    } else {
      _holidayTimer?.cancel();
      _holidayTimer = null;
    }
  }

  void _refreshHolidayDate() {
    final previous = autoHolidayTheme;
    _syncHolidaySchedule();
    if (previous != autoHolidayTheme) notifyListeners();
  }

  void _syncHolidaySchedule() {
    _holidayTimer?.cancel();
    _holidayTimer = null;
    if (!_settings.holidayAutoSwitch) {
      _scheduledHoliday = null;
      return;
    }

    final now = _clock().toLocal();
    _scheduledHoliday = activeHolidayFor(now);
    if (_holidayForeground) {
      final next = nextHolidayThemeChangeAfter(now);
      _holidayTimer = Timer(next.difference(now), _refreshHolidayDate);
    }
  }

  @override
  void dispose() {
    _holidayTimer?.cancel();
    super.dispose();
  }

  CustomTheme? _themeById(String? id) {
    if (id == null) return null;
    return CustomTheme.presetById(id) ??
        _settings.customThemes.where((theme) => theme.id == id).firstOrNull;
  }

  /// Selects a saved theme or preset. Null restores the saved stock mode.
  Future<void> setActiveTheme(String? id) async {
    if (id != null && _themeById(id) == null) {
      throw ArgumentError.value(id, 'id', 'Unknown theme');
    }
    final automaticId = autoHoliday?.themeId;
    if (automaticId != null && automaticId == id) return;
    final next = _dismissAutoHoliday(_settings.copyWith(activeThemeId: id));
    if (next.activeThemeId == _settings.activeThemeId &&
        next.holidayThemeDismissed == _settings.holidayThemeDismissed) {
      return;
    }
    await updateSettings(next);
  }

  Future<void> saveCustomTheme(CustomTheme theme, {bool apply = false}) async {
    final themes = List<CustomTheme>.of(_settings.customThemes);
    final snapshot = theme.copyWith(icons: Map.unmodifiable(theme.icons));
    final index = themes.indexWhere((saved) => saved.id == theme.id);
    if (index < 0) {
      themes.add(snapshot);
    } else {
      themes[index] = snapshot;
    }
    await _saveThemeLibrary(
      themes,
      apply ? theme.id : _settings.activeThemeId,
      manualChoice: apply,
    );
  }

  Future<void> deleteCustomTheme(String id) async {
    final themes = _settings.customThemes.where((theme) => theme.id != id).toList();
    if (themes.length == _settings.customThemes.length) return;
    await _saveThemeLibrary(
      themes,
      _settings.activeThemeId == id ? null : _settings.activeThemeId,
    );
  }

  String newCustomThemeId() => 'custom:${const Uuid().v4()}';

  /// Saves the batch together after validating the library. A background
  /// carried inline by an import must first be written to the image store.
  Future<int> importCustomThemes(List<CustomTheme> themes) async {
    if (themes.length > CustomTheme.maxSavedThemes) {
      throw StateError('Too many themes in the import');
    }
    final saved = List<CustomTheme>.of(_settings.customThemes);
    final ids = saved.map((theme) => theme.id).toSet();
    var added = 0;
    for (final theme in themes) {
      if (saved.any((existing) => existing.sameContent(theme))) continue;
      final id = ids.contains(theme.id) || theme.isPreset
          ? newCustomThemeId()
          : theme.id;
      final candidate = theme.copyWith(id: id, icons: Map.unmodifiable(theme.icons));
      saved.add(candidate);
      ids.add(candidate.id);
      added++;
    }
    if (added > 0) await _saveThemeLibrary(saved, _settings.activeThemeId);
    return added;
  }

  Future<void> _saveThemeLibrary(
    List<CustomTheme> themes,
    String? activeId, {
    bool manualChoice = false,
  }) async {
    if (themes.length > CustomTheme.maxSavedThemes) {
      throw StateError('Theme library is full');
    }
    var iconCharacters = 0;
    for (final theme in themes) {
      if (!theme.canSave) {
        throw ArgumentError('Theme needs a valid ID, name and stored background');
      }
      iconCharacters += theme.storedIconCharacters;
    }
    if (iconCharacters > CustomTheme.maxSavedIconCharacters) {
      throw StateError('Theme library icon data exceeds the storage limit');
    }
    final next = _settings.copyWith(
      customThemes: List.unmodifiable(themes),
      activeThemeId: activeId,
    );
    await updateSettings(manualChoice ? _dismissAutoHoliday(next) : next);
  }

  Future<void> setLanguageOverride(String? value) async {
    await updateSettings(_settings.copyWith(languageOverride: value));
  }

  Future<void> setAppDebugLogEnabled(bool value) async {
    await updateSettings(_settings.copyWith(appDebugLogEnabled: value));
    // Update the global logger
    appLogger.setEnabled(value);
  }

  Future<void> setMapShowDiscoveryContacts(bool value) async {
    await updateSettings(_settings.copyWith(mapShowDiscoveryContacts: value));
  }

  Future<void> setBatteryChemistryForDevice(
    String deviceId,
    String chemistry,
  ) async {
    final updated = Map<String, String>.from(
      _settings.batteryChemistryByDeviceId,
    );
    updated[deviceId] = chemistry;
    await updateSettings(
      _settings.copyWith(batteryChemistryByDeviceId: updated),
    );
  }

  Future<void> setBatteryCustomRangeForDevice(
    String deviceId,
    double minVolts,
    double maxVolts,
  ) async {
    if (minVolts <= 0 || maxVolts <= 0 || minVolts >= maxVolts) return;
    final updatedMin = Map<String, double>.from(
      _settings.batteryCustomMinVoltsByDeviceId,
    );
    final updatedMax = Map<String, double>.from(
      _settings.batteryCustomMaxVoltsByDeviceId,
    );
    updatedMin[deviceId] = minVolts;
    updatedMax[deviceId] = maxVolts;
    await updateSettings(
      _settings.copyWith(
        batteryCustomMinVoltsByDeviceId: updatedMin,
        batteryCustomMaxVoltsByDeviceId: updatedMax,
      ),
    );
  }

  Future<void> setBatteryChemistryForRepeater(
    String repeaterPubKeyHex,
    String chemistry,
  ) async {
    final updated = Map<String, String>.from(
      _settings.batteryChemistryByRepeaterId,
    );
    updated[repeaterPubKeyHex] = chemistry;
    await updateSettings(
      _settings.copyWith(batteryChemistryByRepeaterId: updated),
    );
  }

  Future<void> setUnitSystem(UnitSystem value) async {
    await updateSettings(_settings.copyWith(unitSystem: value));
  }

  Set<String>? _notificationMentionsSource;
  Set<String>? _notificationSilenceSource;
  int _notificationIdentityRevision = -1;
  final Map<String, ChannelNotificationMode> _notificationModes = {};
  Set<String> _restrictedChannelNames = const {};

  void _refreshNotificationModeCache() {
    final identities = ChannelIdentities.instance;
    if (identical(_notificationMentionsSource, _settings.mutedChannels) &&
        identical(_notificationSilenceSource, _settings.silencedChannels) &&
        _notificationIdentityRevision == identities.revision) {
      return;
    }
    _notificationMentionsSource = _settings.mutedChannels;
    _notificationSilenceSource = _settings.silencedChannels;
    _notificationIdentityRevision = identities.revision;
    _notificationModes.clear();
    for (final name in _settings.mutedChannels) {
      for (final alias in identities.namesLinkedTo(name)) {
        _notificationModes[alias] = ChannelNotificationMode.mentionsOnly;
      }
    }
    for (final name in _settings.silencedChannels) {
      for (final alias in identities.namesLinkedTo(name)) {
        _notificationModes[alias] = ChannelNotificationMode.muted;
      }
    }
    _restrictedChannelNames = Set.unmodifiable(_notificationModes.keys);
  }

  // Build aliases only when restrictions or identities change, not on every
  // received message or channel card rebuild. Lookups afterwards are O(1).
  Set<String> get restrictedChannelNames {
    _refreshNotificationModeCache();
    return _restrictedChannelNames;
  }

  ChannelNotificationMode getChannelNotificationMode(String name) {
    _refreshNotificationModeCache();
    return _notificationModes[name] ?? ChannelNotificationMode.all;
  }

  bool isChannelMuted(String name) =>
      getChannelNotificationMode(name) != ChannelNotificationMode.all;

  Future<void> setChannelNotificationMode(String name, ChannelNotificationMode mode) async {
    if (getChannelNotificationMode(name) == mode) {
      return;
    }
    // Clear aliases too: selecting All must also undo an inherited restriction.
    final aliases = ChannelIdentities.instance.namesLinkedTo(name);
    final mentions = Set<String>.of(_settings.mutedChannels)..removeAll(aliases);
    final silenced = Set<String>.of(_settings.silencedChannels)..removeAll(aliases);
    if (mode == ChannelNotificationMode.mentionsOnly) {
      mentions.add(name);
    }
    if (mode == ChannelNotificationMode.muted) {
      silenced.add(name);
    }
    await updateSettings(_settings.copyWith(mutedChannels: mentions, silencedChannels: silenced));
  }

  // Existing notification-shade action retains its mentions exception.
  Future<void> muteChannel(String name) =>
      setChannelNotificationMode(name, ChannelNotificationMode.mentionsOnly);
  Future<void> unmuteChannel(String name) =>
      setChannelNotificationMode(name, ChannelNotificationMode.all);

  Future<void> setTcpServerAddress(String value) async {
    await updateSettings(_settings.copyWith(tcpServerAddress: value));
  }

  Future<void> setTcpServerPort(int value) async {
    await updateSettings(_settings.copyWith(tcpServerPort: value));
  }

  Future<void> setTcpServerWifiSsid(String value) async {
    await updateSettings(_settings.copyWith(tcpServerWifiSsid: value.trim()));
  }

  Future<void> recordTcpConnection(
    String host,
    int port, {
    String? wifiSsid,
  }) async {
    final normalizedHost = host.trim();
    if (normalizedHost.isEmpty || port <= 0) return;
    final normalizedWifiSsid = wifiSsid?.trim() ?? '';
    final existing = _settings.tcpConnectionBookmarks
        .cast<TcpConnectionBookmark?>()
        .firstWhere(
          (item) =>
              item?.host.toLowerCase() == normalizedHost.toLowerCase() &&
              item?.port == port,
          orElse: () => null,
        );

    final bookmark = TcpConnectionBookmark(
      host: normalizedHost,
      port: port,
      lastConnectedAt: DateTime.now(),
      name: existing?.name ?? '',
      isFavorite: existing?.isFavorite ?? false,
      wifiSsid: normalizedWifiSsid.isNotEmpty
          ? normalizedWifiSsid
          : existing?.wifiSsid ?? '',
    );

    // Move this endpoint to the top, drop duplicates, and keep only recent ones.
    final bookmarks = _limitTcpBookmarks([
      bookmark,
      ..._settings.tcpConnectionBookmarks.where(
        (item) =>
            item.host.toLowerCase() != normalizedHost.toLowerCase() ||
            item.port != port,
      ),
    ]);

    await updateSettings(
      _settings.copyWith(
        tcpServerAddress: normalizedHost,
        tcpServerPort: port,
        tcpServerWifiSsid: normalizedWifiSsid,
        tcpConnectionBookmarks: bookmarks.take(5).toList(),
      ),
    );
  }

  Future<void> setTcpConnectionBookmarkName(
    TcpConnectionBookmark bookmark,
    String name,
  ) async {
    await setTcpConnectionBookmarkDetails(
      bookmark,
      name: name,
      isFavorite: bookmark.isFavorite,
    );
  }

  Future<void> setTcpConnectionBookmarkDetails(
    TcpConnectionBookmark bookmark, {
    required String name,
    required bool isFavorite,
    String? wifiSsid,
  }) async {
    final bookmarks = _settings.tcpConnectionBookmarks.map((item) {
      if (item.host.toLowerCase() == bookmark.host.toLowerCase() &&
          item.port == bookmark.port) {
        return item.copyWith(
          name: name.trim(),
          isFavorite: isFavorite,
          wifiSsid: wifiSsid?.trim(),
        );
      }
      return item;
    }).toList();

    await updateSettings(
      _settings.copyWith(tcpConnectionBookmarks: _sortTcpBookmarks(bookmarks)),
    );
  }

  Future<void> removeTcpConnectionBookmark(
    TcpConnectionBookmark bookmark,
  ) async {
    final bookmarks = _settings.tcpConnectionBookmarks
        .where(
          (item) =>
              item.host.toLowerCase() != bookmark.host.toLowerCase() ||
              item.port != bookmark.port,
        )
        .toList();

    await updateSettings(_settings.copyWith(tcpConnectionBookmarks: bookmarks));
  }

  List<TcpConnectionBookmark> _limitTcpBookmarks(
    List<TcpConnectionBookmark> bookmarks,
  ) {
    final limited = List<TcpConnectionBookmark>.from(bookmarks);
    while (limited.length > 5) {
      final removable =
          limited.where((bookmark) => !bookmark.isFavorite).toList()
            ..sort((a, b) => a.lastConnectedAt.compareTo(b.lastConnectedAt));
      if (removable.isEmpty) break;
      limited.remove(removable.first);
    }
    return _sortTcpBookmarks(limited.take(5).toList());
  }

  List<TcpConnectionBookmark> _sortTcpBookmarks(
    List<TcpConnectionBookmark> bookmarks,
  ) {
    return List<TcpConnectionBookmark>.from(bookmarks)..sort((a, b) {
      if (a.isFavorite != b.isFavorite) {
        return a.isFavorite ? -1 : 1;
      }
      return b.lastConnectedAt.compareTo(a.lastConnectedAt);
    });
  }

  Future<void> setJumpToOldestUnread(bool value) async {
    await updateSettings(_settings.copyWith(jumpToOldestUnread: value));
  }

  Future<void> setLoadLinkImages(bool value) async {
    await updateSettings(_settings.copyWith(loadLinkImages: value));
  }

  Future<void> setShowLinkImagesByDefault(bool value) async {
    await updateSettings(_settings.copyWith(showLinkImagesByDefault: value));
  }

  Future<void> setIpfsImageSettings({
    required String publicGateway,
    required String uploadGateway,
    required String uploadEndpoint,
    required String uploadApiKey,
  }) async {
    final normalizedPublicGateway = normalizeIpfsGateway(publicGateway);
    final normalizedUploadGateway = normalizeIpfsGateway(uploadGateway);
    await updateSettings(
      _settings.copyWith(
        publicIpfsGateway: normalizedPublicGateway,
        uploadIpfsGateway: normalizedUploadGateway,
        uploadIpfsEndpoint: uploadEndpoint.trim(),
        uploadIpfsApiKey: uploadApiKey.trim(),
      ),
    );
  }

  Future<void> setImageMessagesEnabled(bool value) async {
    await updateSettings(_settings.copyWith(imageMessagesEnabled: value));
  }

  Future<void> setNetworkMapUploadEnabled(bool value) async {
    await updateSettings(_settings.copyWith(networkMapUploadEnabled: value));
  }

  Future<void> setNetworkMapPromptShown(bool value) async {
    await updateSettings(_settings.copyWith(networkMapPromptShown: value));
  }

  Future<void> setEvictDiscoveredContactsEnabled(bool value) async {
    await updateSettings(
      _settings.copyWith(evictDiscoveredContactsEnabled: value),
    );
  }

  /// See [AppSettings.imageProcessAutomatically]. `main.dart` mirrors this into
  /// `ReceivedImageStore.processAutomatically` on every settings change; the
  /// store applies it to future arrivals only, so flipping it does not
  /// retroactively decode a backlog.
  Future<void> setImageProcessAutomatically(bool value) async {
    await updateSettings(_settings.copyWith(imageProcessAutomatically: value));
  }

  // ---- neural image codec (AEIC-SE) ---------------------------------------

  Future<void> setImageCodecEnabled(bool value) async {
    await updateSettings(_settings.copyWith(imageCodecEnabled: value));
  }

  Future<void> setImageCodecSelectedModelId(String? value) async {
    await updateSettings(_settings.copyWith(imageCodecSelectedModelId: value));
  }

  Future<void> setImageCodecModelSourceUrl(String? value) async {
    await updateSettings(_settings.copyWith(imageCodecModelSourceUrl: value));
  }

  /// [value] is an [AeicRatePoint.wireValue], not an enum index.
  Future<void> setImageCodecRatePoint(int value) async {
    await updateSettings(_settings.copyWith(imageCodecRatePoint: value));
  }

  Future<void> setImageCodecDownloadedModels(
    List<ImageCodecModelRecord> value,
  ) async {
    await updateSettings(_settings.copyWith(imageCodecDownloadedModels: value));
  }

  /// Writes the whole block in one persist, which is what
  /// `ImageCodecService` does on every preference change.
  Future<void> setImageCodecPreferences(ImageCodecPreferences value) async {
    await updateSettings(
      _settings.copyWith(
        imageCodecEnabled: value.enabled,
        imageCodecSelectedModelId: value.selectedModelId,
        imageCodecModelSourceUrl: value.modelSourceUrl,
        imageCodecRatePoint: value.ratePoint,
        imageCodecDownloadedModels: value.downloadedModels,
      ),
    );
  }

  Future<void> setTranslationEnabled(bool value) async {
    await updateSettings(_settings.copyWith(translationEnabled: value));
  }

  Future<void> setAutoTranslateIncomingMessages(bool value) async {
    await updateSettings(
      _settings.copyWith(autoTranslateIncomingMessages: value),
    );
  }

  Future<void> setTranslationTargetLanguageCode(String? value) async {
    await updateSettings(
      _settings.copyWith(translationTargetLanguageCode: value),
    );
  }

  Future<void> setComposerTranslationEnabled(bool value) async {
    await updateSettings(_settings.copyWith(composerTranslationEnabled: value));
  }

  Future<void> setTranslationModelSourceUrl(String? value) async {
    await updateSettings(_settings.copyWith(translationModelSourceUrl: value));
  }

  Future<void> setTranslationSelectedModelId(String? value) async {
    await updateSettings(_settings.copyWith(translationSelectedModelId: value));
  }

  Future<void> setTranslationDownloadedModels(
    List<TranslationModelRecord> value,
  ) async {
    await updateSettings(
      _settings.copyWith(translationDownloadedModels: value),
    );
  }

  Future<void> setMcmpTextLimit(int value) async {
    await updateSettings(
      _settings.copyWith(
        mcmpTextLimit: AppSettings.normalizeMcmpTextLimit(value),
      ),
    );
  }

  Future<void> setChannelMaxbytesOutgoing(int value) async {
    await updateSettings(
      _settings.copyWith(
        channelMaxbytesOutgoing: AppSettings.normalizeChannelMaxbytesOutgoing(
          value,
        ),
      ),
    );
  }

  Future<void> setQuickAnswers(List<QuickAnswer> value) async {
    await updateSettings(
      _settings.copyWith(
        // Keep stored replies normalized so empty rows never leak into UI lists.
        quickAnswers: AppSettings.normalizeQuickAnswers(value),
      ),
    );
  }

  Future<void> setCopyMsgPathTemplate(String value) async {
    await updateSettings(
      _settings.copyWith(
        copyMsgPathTemplate: AppSettings.normalizeCopyMsgPathTemplate(value),
      ),
    );
  }

  Future<void> setCopyMsgPathTemplates({
    required String hopTemplate,
    required String finalTemplate,
  }) async {
    await updateSettings(
      _settings.copyWith(
        copyMsgPathTemplate: AppSettings.normalizeCopyMsgPathTemplate(
          hopTemplate,
        ),
        copyMsgPathFinalTemplate: AppSettings.normalizeCopyMsgPathFinalTemplate(
          finalTemplate,
        ),
      ),
    );
  }

  Future<void> setChannelsSendAsBinary(bool value) async {
    await updateSettings(_settings.copyWith(channelsSendAsBinary: value));
  }

  Future<void> setSendingDelayForCancellationSeconds(int value) async {
    await updateSettings(
      _settings.copyWith(
        sendingDelayForCancellationSeconds:
            AppSettings.normalizeSendingDelayForCancellation(value),
      ),
    );
  }

  Cyr2LatProfile getSelectedCyr2LatProfile() {
    return _settings.cyr2latProfiles.firstWhere(
      (p) => p.id == _settings.selectedCyr2latProfileId,
      orElse: () => _settings.cyr2latProfiles.first,
    );
  }

  Cyr2LatProfile? getCyr2LatProfileById(String profileId) {
    return _settings.cyr2latProfiles.cast<Cyr2LatProfile?>().firstWhere(
      (p) => p?.id == profileId,
      orElse: () => null,
    );
  }

  Future<void> setSelectedCyr2LatProfile(String profileId) async {
    await updateSettings(
      _settings.copyWith(selectedCyr2latProfileId: profileId),
    );
  }

  Future<void> addCyr2LatProfile(Cyr2LatProfile profile) async {
    final updated = List<Cyr2LatProfile>.from(_settings.cyr2latProfiles)
      ..add(profile);
    await updateSettings(_settings.copyWith(cyr2latProfiles: updated));
  }

  Future<void> updateCyr2LatProfile(Cyr2LatProfile updatedProfile) async {
    final updated = _settings.cyr2latProfiles
        .map((p) => p.id == updatedProfile.id ? updatedProfile : p)
        .toList();
    await updateSettings(_settings.copyWith(cyr2latProfiles: updated));
  }

  Future<void> removeCyr2LatProfile(String profileId) async {
    if (_settings.cyr2latProfiles.length <= 1) {
      return; // Don't remove the last profile
    }
    final updated = _settings.cyr2latProfiles
        .where((p) => p.id != profileId)
        .toList();
    var newSelectedId = _settings.selectedCyr2latProfileId;
    if (newSelectedId == profileId) {
      newSelectedId = updated.first.id;
    }
    await updateSettings(
      _settings.copyWith(
        cyr2latProfiles: updated,
        selectedCyr2latProfileId: newSelectedId,
      ),
    );
  }

  Future<void> setDoNotFilterMessagesOnChannels(String value) async {
    await updateSettings(
      _settings.copyWith(doNotFilterMessagesOnChannels: value),
    );
  }
}
