import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../l10n/app_localizations.dart';
import '../utils/platform_info.dart';
import 'app_debug_log_service.dart';

class BackgroundService {
  BackgroundService({AppDebugLogService? debugLogService})
    : _debugLogService = debugLogService;

  final AppDebugLogService? _debugLogService;
  bool _initialized = false;
  // Multiple app features can keep the foreground service alive independently.
  // Stop it only after the last active feature releases its reason.
  final Set<String> _keepAliveReasons = {};
  String? Function()? _languageOverrideProvider;
  bool _connectionLost = false;
  int _notificationRevision = 0;
  final Set<String> _batteryOptimizationPromptReasons = {};

  /// Allows the app to expose its current language override (e.g. from
  /// AppSettingsService) so the foreground notification matches the app UI
  /// language instead of only the system locale.
  void setLanguageOverrideProvider(String? Function()? provider) {
    _languageOverrideProvider = provider;
  }

  Future<void> initialize() async {
    if (!PlatformInfo.isAndroid || _initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'meshcore_background',
        channelName: 'MeshCore Background',
        channelDescription: 'Keeps MeshCore running in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
    _debugLogService?.info(
      'Foreground service initialized',
      tag: 'Background',
    );
  }

  Future<bool> ensureBatteryOptimizationExemption({
    required String reason,
  }) async {
    if (!PlatformInfo.isAndroid) return true;

    try {
      final ignored =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      _debugLogService?.info(
        'Battery optimization exemption check ($reason): $ignored',
        tag: 'Background',
      );
      if (ignored) return true;

      // Startup and the first explicit BLE connection may each prompt once.
      // Automatic reconnect attempts must never reopen system settings.
      if (!_batteryOptimizationPromptReasons.add(reason)) return false;

      _debugLogService?.warn(
        'Battery optimization exemption missing; opening system request ($reason)',
        tag: 'Background',
      );
      final requestOpened =
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      _debugLogService?.info(
        'Battery optimization request result ($reason): $requestOpened',
        tag: 'Background',
      );
      if (!requestOpened) {
        final settingsOpened = await FlutterForegroundTask
            .openIgnoreBatteryOptimizationSettings();
        _debugLogService?.warn(
          'Direct battery request was unavailable; settings opened: $settingsOpened',
          tag: 'Background',
        );
      }
      return false;
    } catch (error) {
      _debugLogService?.error(
        'Battery optimization check/request failed ($reason): $error',
        tag: 'Background',
      );
      return false;
    }
  }

  Future<void> logRuntimeState(String reason) async {
    if (!PlatformInfo.isAndroid) return;
    try {
      final running = await FlutterForegroundTask.isRunningService;
      final batteryExempt =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      _debugLogService?.info(
        'Runtime state ($reason): serviceRunning=$running, batteryExempt=$batteryExempt',
        tag: 'Background',
      );
    } catch (error) {
      _debugLogService?.error(
        'Runtime state check failed ($reason): $error',
        tag: 'Background',
      );
    }
  }

  Future<void> start({String reason = 'connection'}) async {
    if (!PlatformInfo.isAndroid) return;
    _keepAliveReasons.add(reason);
    try {
      if (!_initialized) {
        await initialize();
      }
      final running = await FlutterForegroundTask.isRunningService;
      if (running) {
        _debugLogService?.info(
          'Foreground service already running (reason=$reason)',
          tag: 'Background',
        );
        return;
      }
      final l10n = await _loadLocalizations();
      final result = await FlutterForegroundTask.startService(
        notificationTitle: l10n.background_serviceTitle,
        notificationText: _connectionLost
            ? l10n.app_connectionLostReconnect
            : l10n.background_serviceText,
        callback: startCallback,
      );
      switch (result) {
        case ServiceRequestSuccess():
          _debugLogService?.info(
            'Foreground service started (reason=$reason)',
            tag: 'Background',
          );
        case ServiceRequestFailure(:final error):
          _debugLogService?.error(
            'Foreground service failed to start (reason=$reason): $error',
            tag: 'Background',
          );
      }
    } catch (error) {
      _debugLogService?.error(
        'Foreground service start check failed (reason=$reason): $error',
        tag: 'Background',
      );
    }
  }

  Future<void> setConnectionLost(bool connectionLost) async {
    if (!PlatformInfo.isAndroid) return;
    _connectionLost = connectionLost;
    final revision = ++_notificationRevision;
    final running = await FlutterForegroundTask.isRunningService;
    if (!running) return;
    final l10n = await _loadLocalizations();
    if (revision != _notificationRevision) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: l10n.background_serviceTitle,
      notificationText: connectionLost
          ? l10n.app_connectionLostReconnect
          : l10n.background_serviceText,
    );
  }

  Future<AppLocalizations> _loadLocalizations() async {
    final supported = AppLocalizations.supportedLocales;
    final override = _languageOverrideProvider?.call();
    if (override != null && override.isNotEmpty) {
      final overrideLocale = Locale(override);
      final isSupported = supported.any(
        (l) => l.languageCode == overrideLocale.languageCode,
      );
      if (isSupported) {
        return AppLocalizations.delegate.load(overrideLocale);
      }
    }
    final preferred = WidgetsBinding.instance.platformDispatcher.locales;
    final match = basicLocaleListResolution(preferred, supported);
    return AppLocalizations.delegate.load(match);
  }

  Future<void> stop({String reason = 'connection'}) async {
    if (!PlatformInfo.isAndroid) return;
    _keepAliveReasons.remove(reason);
    if (reason == 'connection') {
      _connectionLost = false;
      _notificationRevision++;
    }
    if (_keepAliveReasons.isNotEmpty) return;

    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (!running) {
        _debugLogService?.warn(
          'Foreground service was already stopped (reason=$reason)',
          tag: 'Background',
        );
        return;
      }
      final result = await FlutterForegroundTask.stopService();
      switch (result) {
        case ServiceRequestSuccess():
          _debugLogService?.info(
            'Foreground service stopped (reason=$reason)',
            tag: 'Background',
          );
        case ServiceRequestFailure(:final error):
          _debugLogService?.error(
            'Foreground service failed to stop (reason=$reason): $error',
            tag: 'Background',
          );
      }
    } catch (error) {
      _debugLogService?.error(
        'Foreground service stop check failed (reason=$reason): $error',
        tag: 'Background',
      );
    }
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_MeshCoreTaskHandler());
}

class _MeshCoreTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}
