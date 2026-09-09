import 'package:flutter/services.dart';

import '../utils/platform_info.dart';

class IosBackgroundTcpService {
  const IosBackgroundTcpService();

  static const MethodChannel _channel = MethodChannel(
    'mco_advanced/ios_background_tcp',
  );

  Future<void> configure({
    required String host,
    required int port,
    required String wifiSsid,
    required bool enabled,
  }) async {
    if (!PlatformInfo.isIOS) return;
    final normalizedHost = host.trim();
    final normalizedSsid = wifiSsid.trim();
    if (normalizedHost.isEmpty || port < 1 || port > 65535) return;
    if (enabled && normalizedSsid.isEmpty) return;

    await _channel.invokeMethod<void>('configure', <String, Object?>{
      'host': normalizedHost,
      'port': port,
      'wifiSsid': normalizedSsid,
      'enabled': enabled,
    });
  }
}
