import 'package:flutter/services.dart';

import '../utils/platform_info.dart';

class IosBackgroundTcpConfigurationResult {
  final bool enabled;
  final bool active;
  final String host;
  final int port;
  final String wifiSsid;

  const IosBackgroundTcpConfigurationResult({
    required this.enabled,
    required this.active,
    required this.host,
    required this.port,
    required this.wifiSsid,
  });

  factory IosBackgroundTcpConfigurationResult.fromMap(
    Map<Object?, Object?> map,
  ) {
    return IosBackgroundTcpConfigurationResult(
      enabled: map['enabled'] as bool? ?? false,
      active: map['active'] as bool? ?? false,
      host: map['host'] as String? ?? '',
      port: map['port'] as int? ?? 0,
      wifiSsid: map['wifiSsid'] as String? ?? '',
    );
  }
}

class IosBackgroundTcpService {
  const IosBackgroundTcpService();

  static const MethodChannel _channel = MethodChannel(
    'mco_advanced/ios_background_tcp',
  );

  Future<IosBackgroundTcpConfigurationResult?> configure({
    required String host,
    required int port,
    required String wifiSsid,
    required bool enabled,
  }) async {
    if (!PlatformInfo.isIOS) return null;
    final normalizedHost = host.trim();
    final normalizedSsid = wifiSsid.trim();
    if (normalizedHost.isEmpty || port < 1 || port > 65535) return null;
    if (enabled && normalizedSsid.isEmpty) return null;

    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'configure',
      <String, Object?>{
        'host': normalizedHost,
        'port': port,
        'wifiSsid': normalizedSsid,
        'enabled': enabled,
      },
    );
    if (result == null) return null;
    return IosBackgroundTcpConfigurationResult.fromMap(result);
  }
}
