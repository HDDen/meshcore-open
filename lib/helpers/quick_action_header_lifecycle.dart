import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/widgets.dart' show AppLifecycleState;

/// Mobile inactive means visible without focus (split screen, a floating
/// window, Control Center). Only actual background/view removal pauses reads.
/// Desktop header queries are independent of window focus and lifecycle.
bool quickActionHeaderAllowsPolling(
  AppLifecycleState? state, {
  required TargetPlatform platform,
  bool isWeb = false,
}) {
  if (isWeb) {
    return state == null || state == AppLifecycleState.resumed;
  }
  return switch (platform) {
    TargetPlatform.android || TargetPlatform.iOS =>
      state != AppLifecycleState.paused && state != AppLifecycleState.hidden &&
      state != AppLifecycleState.detached,
    TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => true,
    _ => state == null || state == AppLifecycleState.resumed,
  };
}
