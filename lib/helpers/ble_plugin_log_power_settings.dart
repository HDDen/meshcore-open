import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../services/app_settings_service.dart';
import '../utils/platform_info.dart';

/// Меняет только служебные логи плагина, не журнал кадров и не BLE-транспорт.
class BlePluginLogPowerSettings {
  BlePluginLogPowerSettings({
    required this.settings,
    Future<void> Function(LogLevel)? applyLevel,
    bool? supported,
    this.onError,
  }) : _applyLevel = applyLevel ?? _setPluginLevel,
       _supported = supported ??
           (PlatformInfo.isAndroid || PlatformInfo.isIOS || PlatformInfo.isMacOS),
       _appliedLevel = FlutterBluePlus.logLevel == LogLevel.debug
           ? LogLevel.debug
           : null {
    settings.addListener(_sync);
    _sync();
  }

  final AppSettingsService settings;
  final void Function(Object, StackTrace)? onError;
  final Future<void> Function(LogLevel) _applyLevel;
  final bool _supported;
  LogLevel? _appliedLevel;
  LogLevel? _desiredLevel;
  bool _running = false;
  bool _disposed = false;
  Future<void> _pending = Future<void>.value();

  @visibleForTesting
  Future<void> get pendingApplicationForTest => _pending;

  static Future<void> _setPluginLevel(LogLevel level) =>
      FlutterBluePlus.setLogLevel(level);

  void _sync() {
    if (_disposed || !_supported) {
      return;
    }
    final next = settings.settings.powerSaving.effective.reduceBlePluginLogs
        ? LogLevel.warning
        : LogLevel.debug;
    // Посторонние настройки не повторяют вызов, в том числе после отказа.
    if (next == _desiredLevel) {
      return;
    }
    _desiredLevel = next;
    if (_running || next == _appliedLevel) {
      return;
    }
    _running = true;
    _pending = _applyPending();
    unawaited(_pending);
  }

  Future<void> _applyPending() async {
    try {
      while (!_disposed && _desiredLevel != _appliedLevel) {
        final next = _desiredLevel!;
        try {
          await _applyLevel(next);
          // API завершён, но нативный bool скрыт публичным методом FBP.
          _appliedLevel = next;
        } catch (error, stackTrace) {
          // Dart getter FBP уже мог измениться; повтор нельзя решать по нему.
          _appliedLevel = null;
          if (!_disposed) {
            onError?.call(error, stackTrace);
          }
          if (_desiredLevel == next) {
            break;
          }
        }
      }
    } finally {
      _running = false;
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    settings.removeListener(_sync);
    // Начатый нативный вызов не отменяется; новых вызовов после dispose не будет.
  }
}
