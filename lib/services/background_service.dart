import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../l10n/app_localizations.dart';
import '../utils/platform_info.dart';
import 'app_debug_log_service.dart';

const String _connectionTaskMessageType = 'connectionHeartbeat';
const String _connectionMonitorDataKey = 'connectionMonitorEnabled';
const String _connectionTitleDataKey = 'connectionNotificationTitle';
const String _connectionConnectedTextDataKey = 'connectionConnectedText';
const String _connectionReconnectingTextDataKey = 'connectionReconnectingText';
const String _connectionBrokenTextDataKey = 'connectionBrokenText';
const Duration _connectionHeartbeatInterval = Duration(seconds: 5);
const Duration _connectionHeartbeatTimeout = Duration(seconds: 20);

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
  Timer? _connectionHeartbeatTimer;
  Map<String, Object>? _connectionHeartbeatData;
  static const MethodChannel _engineLifecycleChannel = MethodChannel(
    'mco_advanced/engine_lifecycle',
  );

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
        await _setEngineRetention(true);
        _debugLogService?.info(
          'Foreground service already running (reason=$reason)',
          tag: 'Background',
        );
        await _syncConnectionMonitor();
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
          await _setEngineRetention(true);
          _debugLogService?.info(
            'Foreground service started (reason=$reason)',
            tag: 'Background',
          );
          await _syncConnectionMonitor();
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
    await _syncConnectionMonitor(l10n: l10n);
  }

  Future<void> _syncConnectionMonitor({AppLocalizations? l10n}) async {
    if (!PlatformInfo.isAndroid) return;

    final monitorConnection = _keepAliveReasons.contains('connection');
    if (!monitorConnection) {
      _connectionHeartbeatTimer?.cancel();
      _connectionHeartbeatTimer = null;
      _connectionHeartbeatData = null;
      await FlutterForegroundTask.saveData(
        key: _connectionMonitorDataKey,
        value: false,
      );
      FlutterForegroundTask.sendDataToTask(<String, Object>{
        'type': _connectionTaskMessageType,
        'monitor': false,
        'timestampMs': DateTime.now().millisecondsSinceEpoch,
      });
      return;
    }

    final resolvedL10n = l10n ?? await _loadLocalizations();
    final data = <String, Object>{
      'type': _connectionTaskMessageType,
      'monitor': true,
      'state': _connectionLost ? 'reconnecting' : 'connected',
      'title': resolvedL10n.background_serviceTitle,
      'connectedText': resolvedL10n.background_serviceText,
      'reconnectingText': resolvedL10n.app_connectionLostReconnect,
      'brokenText': resolvedL10n.app_connectionLostBreaked,
    };
    _connectionHeartbeatData = data;

    await FlutterForegroundTask.saveData(
      key: _connectionMonitorDataKey,
      value: true,
    );
    await FlutterForegroundTask.saveData(
      key: _connectionTitleDataKey,
      value: resolvedL10n.background_serviceTitle,
    );
    await FlutterForegroundTask.saveData(
      key: _connectionConnectedTextDataKey,
      value: resolvedL10n.background_serviceText,
    );
    await FlutterForegroundTask.saveData(
      key: _connectionReconnectingTextDataKey,
      value: resolvedL10n.app_connectionLostReconnect,
    );
    await FlutterForegroundTask.saveData(
      key: _connectionBrokenTextDataKey,
      value: resolvedL10n.app_connectionLostBreaked,
    );

    _sendConnectionHeartbeat();
    _connectionHeartbeatTimer ??= Timer.periodic(
      _connectionHeartbeatInterval,
      (_) => _sendConnectionHeartbeat(),
    );
  }

  void _sendConnectionHeartbeat() {
    final data = _connectionHeartbeatData;
    if (data == null) return;
    FlutterForegroundTask.sendDataToTask(<String, Object>{
      ...data,
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
    });
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
    await _syncConnectionMonitor();
    await _setEngineRetention(_keepAliveReasons.isNotEmpty);
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

  Future<void> _setEngineRetention(bool retain) async {
    try {
      await _engineLifecycleChannel.invokeMethod<void>('setRetainEngine', {
        'retain': retain,
      });
    } catch (error) {
      _debugLogService?.warn(
        'Failed to update Android Flutter engine retention: $error',
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
  bool _monitorConnection = false;
  DateTime? _startedAt;
  DateTime? _lastHeartbeatAt;
  String? _title;
  String? _connectedText;
  String? _reconnectingText;
  String? _brokenText;
  String? _shownState;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _startedAt = DateTime.now();
    _monitorConnection =
        await FlutterForegroundTask.getData<bool>(
          key: _connectionMonitorDataKey,
        ) ??
        false;
    _title = await FlutterForegroundTask.getData<String>(
      key: _connectionTitleDataKey,
    );
    _connectedText = await FlutterForegroundTask.getData<String>(
      key: _connectionConnectedTextDataKey,
    );
    _reconnectingText = await FlutterForegroundTask.getData<String>(
      key: _connectionReconnectingTextDataKey,
    );
    _brokenText = await FlutterForegroundTask.getData<String>(
      key: _connectionBrokenTextDataKey,
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (!_monitorConnection) return;
    final now = DateTime.now();
    final heartbeatAnchor = _lastHeartbeatAt ?? _startedAt;
    final heartbeatExpired =
        heartbeatAnchor != null &&
        now.difference(heartbeatAnchor) >= _connectionHeartbeatTimeout;
    if (heartbeatExpired) {
      unawaited(_showState('broken'));
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map || data['type'] != _connectionTaskMessageType) return;

    _monitorConnection = data['monitor'] == true;
    if (!_monitorConnection) {
      _lastHeartbeatAt = null;
      _shownState = null;
      return;
    }

    _title = data['title'] as String? ?? _title;
    _connectedText = data['connectedText'] as String? ?? _connectedText;
    _reconnectingText =
        data['reconnectingText'] as String? ?? _reconnectingText;
    _brokenText = data['brokenText'] as String? ?? _brokenText;
    final timestampMs = data['timestampMs'];
    _lastHeartbeatAt = timestampMs is int
        ? DateTime.fromMillisecondsSinceEpoch(timestampMs)
        : DateTime.now();

    final state = data['state'] as String? ?? 'connected';
    unawaited(_showState(state));
  }

  Future<void> _showState(String state) async {
    if (_shownState == state || _title == null) return;
    final text = switch (state) {
      'broken' => _brokenText,
      'reconnecting' => _reconnectingText,
      _ => _connectedText,
    };
    if (text == null) return;
    _shownState = state;
    await FlutterForegroundTask.updateService(
      notificationTitle: _title!,
      notificationText: text,
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}
