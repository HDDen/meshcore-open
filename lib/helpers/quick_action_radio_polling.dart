import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' as foundation;

import '../connector/meshcore_connector.dart';
import '../models/quick_actions_settings.dart';
import '../models/quick_actions_header_settings.dart';
import '../services/app_settings_service.dart';
import 'ios_presentation_guard.dart';
import 'quick_action_header_lifecycle.dart';

/// Owns queries for one visible quick-action surface. Header and popup use
/// independent cadences; other consumers keep their own polling ownership.
/// Each kind permits one request in flight.
enum QuickActionPollingSource { popup, header }

class QuickActionRadioPolling with WidgetsBindingObserver {
  QuickActionRadioPolling(this.connector, this.settings, {
    required this.isVisible, this.source = QuickActionPollingSource.popup,
  }) {
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    connector.addListener(update);
    settings.addListener(update);
    if (source == QuickActionPollingSource.popup) {
      iosAppPresentationActive.addListener(update);
    }
    update();
  }

  final MeshCoreConnector connector;
  final AppSettingsService settings;
  final bool Function() isVisible;
  final QuickActionPollingSource source;
  Duration? _interval;
  AppLifecycleState? _lifecycle;
  bool _disposed = false;
  bool _noiseBusy = false;
  bool _powerBusy = false;
  bool _noiseEnabled = false;
  bool _powerEnabled = false;
  Timer? _timer;
  Timer? _initial;

  bool get _visible {
    if (_disposed || !isVisible()) return false;
    if (source == QuickActionPollingSource.header) {
      return quickActionHeaderAllowsPolling(_lifecycle,
        platform: foundation.defaultTargetPlatform, isWeb: foundation.kIsWeb);
    }
    // Popup lifetime/foreground behavior is independent of the header policy.
    return (_lifecycle == null || _lifecycle == AppLifecycleState.resumed) &&
        iosAppPresentationActive.value;
  }
  bool get _ready => _visible && connector.isConnected &&
      !connector.isOfflineMode && connector.isSessionReady;

  bool _enabled(QuickAction action) => settings.settings.quickActions.items.any(
    (item) => item.action == action && item.visible,
  );

  void update() {
    if (_disposed) return;
    final header = settings.settings.quickActionsHeader;
    final fromHeader = source == QuickActionPollingSource.header;
    final wantsNoise = fromHeader ? header.display == QuickActionsHeaderDisplay.noise
        : _enabled(QuickAction.radioNoise);
    final wantsPower = !fromHeader && _enabled(QuickAction.radioTxPower);
    final noise = _ready && wantsNoise && connector.supportsCompanionRadioStats;
    final power = _ready && wantsPower;
    final interval = fromHeader
        ? Duration(milliseconds: header.intervalMsFor(header.display))
        : const Duration(seconds: 1);
    final changed = noise != _noiseEnabled || power != _powerEnabled || _interval != interval;
    if (_interval != interval) {
      _timer?.cancel();
      _timer = null;
      _interval = interval;
    }
    _noiseEnabled = noise;
    _powerEnabled = power;
    if (!noise && !power) {
      _timer?.cancel();
      _timer = null;
      _initial?.cancel();
      _initial = null;
      return;
    }
    _timer ??= Timer.periodic(interval, (_) => _tick());
    if (changed) {
      _initial?.cancel();
      // Never synchronously query/notify while the popup is being built.
      _initial = Timer(Duration.zero, _tick);
    }
  }

  void _tick() {
    if (!_ready) {
      update();
      return;
    }
    if (_noiseEnabled && !_noiseBusy) unawaited(_noise());
    if (_powerEnabled && !_powerBusy) unawaited(_power());
  }

  Future<void> _noise() async {
    _noiseBusy = true;
    try {
      if (_ready && _noiseEnabled && connector.supportsCompanionRadioStats) {
        await connector.requestRadioStats();
      }
    } catch (_) {
      // A failed read is retried on the next visible tick.
    } finally {
      _noiseBusy = false;
    }
  }

  Future<void> _power() async {
    _powerBusy = true;
    try {
      if (_ready && _powerEnabled) await connector.refreshRadioPower();
    } catch (_) {
      // A failed read is retried on the next visible tick.
    } finally {
      _powerBusy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    update();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _initial?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    connector.removeListener(update);
    settings.removeListener(update);
    if (source == QuickActionPollingSource.popup) {
      iosAppPresentationActive.removeListener(update);
    }
  }
}
