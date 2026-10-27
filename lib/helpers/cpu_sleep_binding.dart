import 'dart:async';

import 'package:flutter/widgets.dart';

import '../connector/meshcore_connector.dart';
import '../models/cpu_sleep_options.dart';
import '../services/app_settings_service.dart';
import '../services/background_service.dart';
import '../services/wardrive_service.dart';
import '../utils/platform_info.dart';
import 'background_work_tracker.dart';

// Passive retry tombstones and a connecting socket alone do not keep CPU awake.
const cpuProtectedKinds = <BackgroundWorkKind>{
  BackgroundWorkKind.transportWrite, BackgroundWorkKind.transportTeardown,
  BackgroundWorkKind.persistence, BackgroundWorkKind.messageSync,
  BackgroundWorkKind.radioReceive, BackgroundWorkKind.frameDispatch,
  BackgroundWorkKind.messageReplay, BackgroundWorkKind.radioSend,
  BackgroundWorkKind.imageTransfer, BackgroundWorkKind.queuedMessageRequest,
  BackgroundWorkKind.commandReply, BackgroundWorkKind.notification,
};

bool cpuHasProtectedWork(BackgroundWorkSnapshot snapshot, {int runningRetry = 0}) =>
    runningRetry > 0 || cpuProtectedKinds.any((kind) => snapshot.countFor(kind) > 0);

class CpuSleepBinding with WidgetsBindingObserver {
  CpuSleepBinding({required this.connector, required this.settings,
    required this.service, required this.wardrive, required this.proxyChanges,
    required this.proxyActive, this.onError, bool? isAndroid})
      : _enabled = isAndroid ?? PlatformInfo.isAndroid {
    if (!_enabled) return;
    _background = _isBackground(WidgetsBinding.instance.lifecycleState);
    connector.addListener(_sync);
    settings.addListener(_sync);
    wardrive.addListener(_sync);
    proxyChanges.addListener(_sync);
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  final MeshCoreConnector connector;
  final AppSettingsService settings;
  final BackgroundService service;
  final WardriveService wardrive;
  final Listenable proxyChanges;
  final bool Function() proxyActive;
  final void Function(Object)? onError;
  final bool _enabled;
  bool _background = false;
  bool _disposed = false;
  bool _tracking = false;
  bool _unconditional = false;
  CpuSleepOptions get _options => settings.settings.powerSaving.effective.cpuSleep;

  static bool _isBackground(AppLifecycleState? state) =>
      state == AppLifecycleState.paused || state == AppLifecycleState.hidden ||
      state == AppLifecycleState.detached;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _background = _isBackground(state);
    _sync();
  }

  Future<void>? _prepare(BackgroundWorkKind kind) {
    if (_disposed || !_options.enabled || _options.unconditional ||
        (!cpuProtectedKinds.contains(kind) && kind != BackgroundWorkKind.retry)) {
      return null;
    }
    // begin() already published the hold request; await its native acknowledgement.
    return service.cpuPolicySettled;
  }

  void _sync() {
    if (_disposed || !_enabled) return;
    try {
      _syncPolicy();
    } catch (error) {
      unawaited(service.configureCpuSleep(requested: _unconditional,
        allowSleep: _unconditional, protectedWork: !_unconditional,
        unconditional: _unconditional));
      onError?.call(error);
    }
  }

  void _syncPolicy() {
    final options = _options;
    _unconditional = options.unconditional;
    final trackWork = options.enabled && !_unconditional;
    if (_tracking != trackWork) {
      _tracking = trackWork;
      if (_tracking) {
        connector.addBackgroundWorkListener(_sync);
        connector.backgroundWorkPreparation = _prepare;
      } else {
        connector.removeBackgroundWorkListener(_sync);
        if (connector.backgroundWorkPreparation == _prepare) {
          connector.backgroundWorkPreparation = null;
        }
      }
    }
    if (_unconditional) {
      unawaited(service.configureCpuSleep(requested: true,
        allowSleep: true, protectedWork: false, unconditional: true));
      return;
    }
    if (!options.enabled) {
      unawaited(service.configureCpuSleep(requested: false,
        allowSleep: false, protectedWork: false));
      return;
    }
    final scenarios = <String>{};
    if (connector.isConnected || connector.isRecoveringConnection) {
      switch (connector.activeTransport) {
        case MeshCoreTransportType.bluetooth: scenarios.add('ble'); break;
        case MeshCoreTransportType.tcp: scenarios.add('tcp'); break;
        default: scenarios.add('other'); break;
      }
    }
    if (proxyActive()) scenarios.add('proxy');
    if (wardrive.isRunning) scenarios.add('wardrive');
    unawaited(service.configureCpuSleep(
      requested: options.enabled,
      allowSleep: options.permits(background: _background, scenarios: scenarios),
      protectedWork: cpuHasProtectedWork(connector.backgroundWorkSnapshot,
        runningRetry: connector.runningBackgroundWorkCount(BackgroundWorkKind.retry)),
    ));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (!_enabled) return;
    WidgetsBinding.instance.removeObserver(this);
    connector.removeListener(_sync);
    connector.removeBackgroundWorkListener(_sync);
    if (connector.backgroundWorkPreparation == _prepare) {
      connector.backgroundWorkPreparation = null;
    }
    settings.removeListener(_sync);
    wardrive.removeListener(_sync);
    proxyChanges.removeListener(_sync);
    // Disposing UI does not revoke a persisted unconditional choice.
    unawaited(service.configureCpuSleep(requested: _unconditional,
      allowSleep: _unconditional, protectedWork: false,
      unconditional: _unconditional));
  }
}
