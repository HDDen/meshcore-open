import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mco_service/mco_service.dart';

import '../connector/meshcore_connector.dart';
import '../services/app_settings_service.dart';
import '../utils/platform_info.dart';
import 'ios_execution_diagnostics.dart';
import 'ios_immortalizer_power_binding.dart';

/// Native owns physical background state and the persistent manual override.
/// Dart supplies only the current, already-authorized TCP reasons.
class IosBackgroundExecutionBinding {
  IosBackgroundExecutionBinding({
    required this.connector,
    required this.settings,
    required this.sections,
    bool? isIos,
    MethodChannel channel = const MethodChannel('mco_advanced/ios_execution'),
    this.onError,
    this.onState,
    this.onDiagnostics,
  }) : _channel = channel,
       _enabled = isIos ?? PlatformInfo.isIOS {
    if (!_enabled) {
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (!_disposed && call.method == 'diagnostics') {
        final raw = call.arguments;
        final formatted = formatIosExecutionDiagnostics(raw);
        if (formatted != null && raw is Map &&
            (raw['revision'] as int) > _diagnosticsRevision) {
          _diagnosticsRevision = raw['revision'] as int;
          onDiagnostics?.call(formatted);
        }
        return;
      }
      if (_disposed || call.method != 'state' || call.arguments is! Map) {
        return;
      }
      final state = call.arguments as Map;
      final revision = state['revision'];
      const fields = <String>[
        'eligible', 'manualAllowed', 'background', 'armed', 'audioRunning', 'legacyInjection',
      ];
      if (state['schema'] != 1 || revision is! int || revision <= _nativeRevision ||
          !fields.every((key) => state[key] is bool)) {
        return;
      }
      _nativeRevision = revision;
      onState?.call('eligible=${state['eligible']}, manual=${state['manualAllowed']}, '
          'background=${state['background']}, armed=${state['armed']}, '
          'audio=${state['audioRunning']}, legacy=${state['legacyInjection']}');
    });
    // Параметры отправляются раньше первой авторизации удержания, тем же FIFO channel.
    _powerBinding = IosImmortalizerPowerBinding(
      settings: settings, channel: _channel, onError: onError,
    );
    connector.addListener(_sync);
    settings.addListener(_sync);
    sections.addListener(_sync);
    _sync();
  }

  final MeshCoreConnector connector;
  final AppSettingsService settings;
  final SettingsSectionsService sections;
  final void Function(Object error)? onError;
  final void Function(String state)? onState;
  final void Function(String diagnostics)? onDiagnostics;
  final MethodChannel _channel;
  final bool _enabled;
  IosImmortalizerPowerBinding? _powerBinding;
  bool _tcpWasConnected = false;
  bool? _sent;
  bool _disposed = false;
  int _revision = 0;
  int _nativeRevision = -1;
  int _diagnosticsRevision = -1;

  void _sync() {
    if (_disposed || !_enabled) {
      return;
    }
    final tcp = connector.activeTransport == MeshCoreTransportType.tcp;
    final manual = connector.wasManuallyDisconnected;
    if (tcp && connector.isConnected && !manual) {
      _tcpWasConnected = true;
    } else if (!tcp || manual || !connector.isRecoveringConnection) {
      _tcpWasConnected = false;
    }
    final tcpSession = tcp && !manual &&
        (connector.isConnected ||
            (_tcpWasConnected && connector.isRecoveringConnection));
    // Running means an actual TCP listener. The BLE frontend alone is not a
    // reason; a TCP listener remains a reason even with no IP clients yet.
    final tcpProxy = sections.companionProxyEnabled &&
        sections.companionProxyRunning;
    _send(settings.settings.backgroundTcpEnabled && (tcpSession || tcpProxy));
  }

  void _send(bool eligible, {bool force = false}) {
    if (!force && _sent == eligible) {
      return;
    }
    _sent = eligible;
    final revision = ++_revision;
    unawaited(_channel.invokeMethod<void>('configure', <String, Object>{
      'eligible': eligible,
    }).catchError((Object error) {
      // A late reply cannot roll back a newer request. Native configure is
      // synchronous on main; it never awaits an old start operation.
      if (revision != _revision || _disposed) {
        return;
      }
      _sent = null;
      onError?.call(error);
    }));
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (!_enabled) {
      return;
    }
    connector.removeListener(_sync);
    settings.removeListener(_sync);
    sections.removeListener(_sync);
    _channel.setMethodCallHandler(null);
    // This does not clear the native manual preference.
    _send(false, force: true);
    _powerBinding?.dispose();
  }
}
