import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../helpers/background_task_options.dart';
import '../helpers/android_cpu_runtime.dart';
import '../helpers/uptime_heartbeat_monitor.dart';
import '../l10n/app_localizations.dart';
import '../storage/prefs_manager.dart';
import '../utils/platform_info.dart';
import 'app_debug_log_service.dart';

const String _connectionTaskMessageType = 'connectionHeartbeat';
const String _connectionKeepAliveReason = 'connection';
const String _tcpConnectionKeepAliveReason = 'tcp-connection';
const String _connectionMonitorDataKey = 'connectionMonitorEnabled';
const String _connectionTitleDataKey = 'connectionNotificationTitle';
const String _connectionConnectedTextDataKey = 'connectionConnectedText';
const String _connectionReconnectingTextDataKey = 'connectionReconnectingText';
const String _connectionBrokenTextDataKey = 'connectionBrokenText';
const Duration _connectionHeartbeatInterval = Duration(seconds: 5);
const Duration _connectionHeartbeatTimeout = Duration(seconds: 20);

class BackgroundService {
  BackgroundService({AppDebugLogService? debugLogService})
    : _debugLogService = debugLogService,
      _androidForTest = null;

  // Изолируем Android-ветку в тестах без реальной службы и подмены ОС процесса.
  @visibleForTesting
  BackgroundService.forTest({required bool isAndroid})
    : _debugLogService = null,
      _androidForTest = isAndroid;

  final AppDebugLogService? _debugLogService;
  final bool? _androidForTest;
  bool get _isAndroid => _androidForTest ?? PlatformInfo.isAndroid;

  @visibleForTesting
  static TaskHandler taskHandlerForTest({DateTime Function()? now}) =>
      _MeshCoreTaskHandler(now: now);
  bool _initialized = false;
  bool _managedCpu = false;
  bool _pluginCpuManaged = false;
  bool _cpuRequested = false;
  bool _cpuSleepAllowed = false;
  bool _cpuWork = false;
  bool _cpuUnconditional = false;
  bool _cpuPolicyKnown = false;
  Future<void> _cpuUpdates = Future<void>.value();
  int _heartbeatSequence = 0;

  Future<void> get cpuPolicySettled => _cpuUpdates;

  Future<void> configureCpuSleep({required bool requested,
    required bool allowSleep, required bool protectedWork,
    bool unconditional = false}) {
    if (!_isAndroid || kDiagnosticCpuOff) return Future<void>.value();
    if (unconditional) {
      requested = true;
      allowSleep = true;
      protectedWork = false;
    }
    if (_cpuPolicyKnown && _cpuRequested == requested && _cpuSleepAllowed == allowSleep &&
        _cpuWork == protectedWork && _cpuUnconditional == unconditional) {
      return _cpuUpdates;
    }
    final policyChanged = _cpuRequested != requested || _cpuSleepAllowed != allowSleep ||
        _cpuUnconditional != unconditional;
    _cpuPolicyKnown = true;
    _cpuRequested = requested;
    _cpuSleepAllowed = allowSleep;
    _cpuWork = protectedWork;
    _cpuUnconditional = unconditional;
    return _cpuUpdates = _cpuUpdates.then((_) async {
      try {
        var handedOff = false;
        if (!_initialized) await initialize();
        if (!_managedCpu && !requested) return;
        if (!_pluginCpuManaged && requested) {
          final running = await FlutterForegroundTask.isRunningService;
          await AndroidCpuRuntime.configure(hold: !unconditional, work: protectedWork,
              migrate: running, unconditional: unconditional);
          _managedCpu = true;
          _configureTaskOptions();
          if (running) {
            final update = await FlutterForegroundTask.updateService(
              foregroundTaskOptions: backgroundTaskOptions(managedCpu: true));
            if (update is ServiceRequestFailure) throw update.error;
            final restart = await FlutterForegroundTask.restartService();
            if (restart is ServiceRequestFailure) throw restart.error;
          }
          _pluginCpuManaged = true;
          handedOff = true;
        }
        await AndroidCpuRuntime.configure(hold: !allowSleep, work: protectedWork,
          unconditional: unconditional);
        // Packet work must not create a log and worker heartbeat on every lease.
        if (policyChanged || handedOff) {
          _debugLogService?.info('CPU policy: sleepAllowed=$allowSleep, unconditional=$unconditional',
            tag: 'PowerSaving', noNotify: true);
          _sendConnectionHeartbeat();
        }
      } catch (error) {
        _cpuPolicyKnown = false;
        try { await AndroidCpuRuntime.configure(hold: !unconditional, work: false,
          unconditional: unconditional); }
        catch (_) { /* Original plugin lock is retained before handoff. */ }
        _debugLogService?.warn('CPU policy could not be applied: $error',
            tag: 'PowerSaving');
      }
    });
  }
  // Multiple app features can keep the foreground service alive independently.
  // Stop it only after the last active feature releases its reason.
  final Set<String> _keepAliveReasons = {};
  String? Function()? _languageOverrideProvider;
  bool _connectionLost = false;
  int _notificationRevision = 0;

  // While the link stays down, every failed reconnect attempt reports the loss
  // again, seconds apart. The "connection lost" text is posted once per outage
  // and stays in the notification until the link is back; a restored
  // connection re-arms it, so the next loss is always announced.
  bool _connectionLostPosted = false;
  final Set<String> _batteryOptimizationPromptReasons = {};
  static const String _batteryOptimizationAskedKey =
      'background_battery_exemption_asked_v1';
  Timer? _connectionHeartbeatTimer;
  Map<String, Object>? _connectionHeartbeatData;
  static const MethodChannel _engineLifecycleChannel = MethodChannel(
    'mco_advanced/engine_lifecycle',
  );
  static const MethodChannel _tcpWifiLockChannel = MethodChannel(
    'mco_advanced/tcp_wifi_lock',
  );

  /// Allows the app to expose its current language override (e.g. from
  /// AppSettingsService) so the foreground notification matches the app UI
  /// language instead of only the system locale.
  void setLanguageOverrideProvider(String? Function()? provider) {
    _languageOverrideProvider = provider;
  }

  Future<void> initialize() async {
    if (!_isAndroid || _initialized) return;
    try {
      if (kDiagnosticCpuOff) await AndroidCpuRuntime.diagnostic(true);
      _managedCpu = (await AndroidCpuRuntime.clock())?.managed ?? false;
      if (_managedCpu) await AndroidCpuRuntime.beginMainSession();
    } catch (_) { /* Older native builds keep the original plugin lock. */ }
    _configureTaskOptions();
    _initialized = true;
    if (kDiagnosticCpuOff) {
      _debugLogService?.warn(
        'Diagnostic CPU-off: plugin wake lock disabled; heartbeat unchanged',
        tag: 'Background',
      );
    }
    _debugLogService?.info('Foreground service initialized', tag: 'Background');
  }

  void _configureTaskOptions() {
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
      foregroundTaskOptions: backgroundTaskOptions(managedCpu: _managedCpu),
    );
  }

  /// Whether the exemption has ever been asked for on this install.
  ///
  /// App-wide and unscoped by node, like the other states that describe this
  /// phone rather than any radio's data: the exemption belongs to the app in
  /// Android's eyes, not to whatever it happens to be connected to.
  bool get hasRequestedBatteryOptimizationExemption =>
      PrefsManager.instance.getBool(_batteryOptimizationAskedKey) ?? false;

  /// Checks the exemption, and asks for it at most once per install.
  ///
  /// The check itself is free and always runs — it is what the return value
  /// and the log line are built from. The *prompt* is the part that is
  /// rationed: it sends the user out to a system screen, and repeating that on
  /// every launch reads as nagging for something already declined once. So the
  /// first launch that finds the exemption missing asks, records that it did,
  /// and every later one only looks.
  ///
  /// [force] is how the settings screen asks again on purpose: it steps past
  /// both the recorded ask and the per-run guard below.
  Future<bool> ensureBatteryOptimizationExemption({
    required String reason,
    bool force = false,
  }) async {
    if (!_isAndroid) return true;

    try {
      final ignored =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      _debugLogService?.info(
        'Battery optimization exemption check ($reason): $ignored',
        tag: 'Background',
      );
      if (ignored) return true;

      if (!force && hasRequestedBatteryOptimizationExemption) {
        _debugLogService?.info(
          'Battery optimization exemption already requested once; '
          'not prompting again ($reason)',
          tag: 'Background',
        );
        return false;
      }

      // Startup and the first explicit BLE connection may each prompt once.
      // Automatic reconnect attempts must never reopen system settings.
      if (!force && !_batteryOptimizationPromptReasons.add(reason)) {
        return false;
      }

      // Recorded before the prompt rather than after it: what is being spent
      // is the one interruption we allow ourselves, and it is spent whether
      // the user grants, declines, or backs out of the system screen.
      await PrefsManager.instance.setBool(_batteryOptimizationAskedKey, true);

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
    if (!_isAndroid) return;
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
    if (!_isAndroid) return;
    _keepAliveReasons.add(reason);
    await _cpuUpdates;
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
      if (_managedCpu) await _syncConnectionMonitor(l10n: l10n);
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
    if (!_isAndroid) return;
    _connectionLost = connectionLost;
    if (!connectionLost) {
      _connectionLostPosted = false;
    } else if (_connectionLostPosted) {
      return;
    }
    final revision = ++_notificationRevision;
    final running = await FlutterForegroundTask.isRunningService;
    if (!running) return;
    final l10n = await _loadLocalizations();
    if (revision != _notificationRevision) return;
    if (connectionLost) _connectionLostPosted = true;
    await FlutterForegroundTask.updateService(
      notificationTitle: l10n.background_serviceTitle,
      notificationText: connectionLost
          ? l10n.app_connectionLostReconnect
          : l10n.background_serviceText,
    );
    await _syncConnectionMonitor(l10n: l10n);
  }

  Future<void> setTcpWifiLock(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _tcpWifiLockChannel.invokeMethod<void>('setEnabled', {
        'enabled': enabled,
      });
      _debugLogService?.info(
        'TCP Wi-Fi lock ${enabled ? 'enabled' : 'disabled'}',
        tag: 'Background',
      );
    } catch (error) {
      _debugLogService?.warn(
        'Failed to update TCP Wi-Fi lock: $error',
        tag: 'Background',
      );
    }
  }

  bool get _monitorsConnection =>
      _keepAliveReasons.contains(_connectionKeepAliveReason) ||
      _keepAliveReasons.contains(_tcpConnectionKeepAliveReason);

  Future<void> _syncConnectionMonitor({AppLocalizations? l10n}) async {
    if (!_isAndroid) return;

    final monitorConnection = _monitorsConnection;
    if (!monitorConnection) {
      _connectionHeartbeatTimer?.cancel();
      _connectionHeartbeatTimer = null;
      _connectionHeartbeatData = null;
      await FlutterForegroundTask.saveData(
        key: _connectionMonitorDataKey,
        value: false,
      );
      final disabled = <String, Object>{
        'type': _connectionTaskMessageType,
        'monitor': false,
        'timestampMs': DateTime.now().millisecondsSinceEpoch,
      };
      if (_managedCpu) {
        unawaited(_sendManagedHeartbeat(disabled));
      } else {
        FlutterForegroundTask.sendDataToTask(disabled);
      }
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
    if (_managedCpu) {
      unawaited(_sendManagedHeartbeat(data));
      return;
    }
    FlutterForegroundTask.sendDataToTask(<String, Object>{
      ...data,
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _sendManagedHeartbeat(Map<String, Object> data) async {
    final sequence = ++_heartbeatSequence;
    try {
      final clock = await AndroidCpuRuntime.clock();
      if (clock == null || sequence != _heartbeatSequence) return;
      FlutterForegroundTask.sendDataToTask(<String, Object>{
        ...data, 'uptimeMs': clock.uptimeMs, 'generation': clock.generation,
        'sequence': sequence, 'session': clock.session,
        'timestampMs': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) { /* Do not send an unverified heartbeat. */ }
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

  static Future<void> openBatteryOptimizationSettings() async {
    if (!PlatformInfo.isAndroid) return;
    await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
  }

  Future<void> stop({String reason = 'connection'}) async {
    if (!_isAndroid) return;
    _keepAliveReasons.remove(reason);
    if ((reason == _connectionKeepAliveReason ||
            reason == _tcpConnectionKeepAliveReason) &&
        !_monitorsConnection) {
      _connectionLost = false;
      _connectionLostPosted = false;
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
      if (_managedCpu && result is ServiceRequestSuccess) {
        await AndroidCpuRuntime.stopped();
      }
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
  _MeshCoreTaskHandler({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  bool _monitorConnection = false;
  DateTime? _startedAt;
  DateTime? _lastHeartbeatAt;
  String? _title;
  String? _connectedText;
  String? _reconnectingText;
  String? _brokenText;
  String? _shownState;
  UptimeHeartbeatMonitor? _uptimeMonitor;
  bool _closed = false;
  bool _checking = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _startedAt = _now();
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
    try {
      final clock = await AndroidCpuRuntime.clock(workerReady: true);
      if (clock != null && clock.managed) {
        _uptimeMonitor = UptimeHeartbeatMonitor(
          generation: clock.generation, startedAt: clock.uptimeMs)
          ..restoreMonitoring(_monitorConnection);
      }
    } catch (_) { /* Ordinary builds and tests retain the legacy monitor. */ }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_closed) return;
    if (_uptimeMonitor != null) {
      unawaited(_checkUptime());
      return;
    }
    if (!_monitorConnection) return;
    final now = _now();
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
    if (_closed || data is! Map || data['type'] != _connectionTaskMessageType) return;
    if (_uptimeMonitor != null) {
      unawaited(_receiveUptime(data));
      return;
    }

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
        : _now();

    final state = data['state'] as String? ?? 'connected';
    unawaited(_showState(state));
  }

  Future<void> _checkUptime() async {
    if (_checking || _closed) return;
    _checking = true;
    var valid = false;
    try {
      final clock = await AndroidCpuRuntime.clock();
      if (_closed || clock == null || clock.generation != _uptimeMonitor?.generation) return;
      valid = true;
      if (_uptimeMonitor!.expired(clock.uptimeMs)) await _showState('broken');
    } catch (_) { /* Leave native protection held until the clock recovers. */ }
    finally {
      _checking = false;
      if (valid) {
        try { await AndroidCpuRuntime.tickDone(); } catch (_) { /* Worker ended. */ }
      }
    }
  }

  Future<void> _receiveUptime(Map data) async {
    try {
      final clock = await AndroidCpuRuntime.clock();
      if (_closed || clock == null || !_uptimeMonitor!.receive(data, clock.uptimeMs,
          session: clock.session)) {
        return;
      }
      _monitorConnection = data['monitor'] == true;
      if (!_monitorConnection) { _shownState = null; return; }
      _title = data['title'] as String? ?? _title;
      _connectedText = data['connectedText'] as String? ?? _connectedText;
      _reconnectingText = data['reconnectingText'] as String? ?? _reconnectingText;
      _brokenText = data['brokenText'] as String? ?? _brokenText;
      await _showState(data['state'] as String? ?? 'connected');
    } catch (_) { /* Clock/channel failure is not evidence of a lost link. */ }
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
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async { _closed = true; }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}
