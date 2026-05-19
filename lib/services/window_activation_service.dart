import 'package:flutter/services.dart';

import '../utils/platform_info.dart';

class WindowActivationService {
  WindowActivationService._();

  static const MethodChannel _channel = MethodChannel(
    'meshcore_open/window_activation',
  );

  static Future<void> restoreAndFocus() async {
    if (!PlatformInfo.isWindows) return;

    try {
      await _channel.invokeMethod<void>('restoreAndFocus');
    } on PlatformException {
      // Notification navigation should still work if the native window
      // activation call is unavailable on an older build.
    } on MissingPluginException {
      // No-op on platforms/runners that do not expose the channel.
    }
  }
}
