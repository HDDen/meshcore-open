import 'package:flutter/services.dart';

import '../utils/platform_info.dart';

class IosWifiSsidService {
  const IosWifiSsidService();

  static const MethodChannel _channel = MethodChannel(
    'mco_advanced/ios_wifi_ssid',
  );

  Future<String?> currentSsid() async {
    if (!PlatformInfo.isIOS) return null;
    try {
      final ssid = await _channel.invokeMethod<String>('currentSsid');
      final trimmed = ssid?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }
}
