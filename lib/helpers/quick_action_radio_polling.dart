import 'dart:async';

import 'package:flutter/widgets.dart';

import '../connector/meshcore_connector.dart';
import '../models/quick_actions_settings.dart';
import '../services/app_settings_service.dart';
import 'ios_presentation_guard.dart';

/// Owns only the popup's live queries; other radio-stat consumers keep their
/// own polling ownership and cadence. Each kind permits one request in flight.
class QuickActionRadioPolling with WidgetsBindingObserver {
  QuickActionRadioPolling(this.connector, this.settings, {required this.isVisible}) {
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    connector.addListener(update);
    settings.addListener(update);
    iosAppPresentationActive.addListener(update);
    update();
  }

  final MeshCoreConnector connector;
  final AppSettingsService settings;
  final bool Function() isVisible;
  bool _foreground = true;
  bool _disposed = false;
  bool _noiseBusy = false;
  bool _powerBusy = false;
  bool _noiseEnabled = false;
  bool _powerEnabled = false;
  Timer? _timer;
  Timer? _initial;

  bool get _visible => !_disposed && _foreground &&
      iosAppPresentationActive.value && isVisible();
  bool get _ready => _visible && connector.isConnected &&
      !connector.isOfflineMode && connector.isSessionReady;

  bool _enabled(QuickAction action) => settings.settings.quickActions.items.any(
    (item) => item.action == action && item.visible,
  );

  void update() {
    if (_disposed) return;
    final noise = _ready && _enabled(QuickAction.radioNoise) && connector.supportsCompanionRadioStats;
    final power = _ready && _enabled(QuickAction.radioTxPower);
    final changed = noise != _noiseEnabled || power != _powerEnabled;
    _noiseEnabled = noise;
    _powerEnabled = power;
    if (!noise && !power) {
      _timer?.cancel();
      _timer = null;
      _initial?.cancel();
      _initial = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
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
      if (_ready && _enabled(QuickAction.radioNoise) && connector.supportsCompanionRadioStats) {
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
      if (_ready && _enabled(QuickAction.radioTxPower)) await connector.refreshRadioPower();
    } catch (_) {
      // A failed read is retried on the next visible tick.
    } finally {
      _powerBusy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
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
    iosAppPresentationActive.removeListener(update);
  }
}
