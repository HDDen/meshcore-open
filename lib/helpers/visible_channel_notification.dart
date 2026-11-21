import 'package:flutter/widgets.dart';

/// Keyboard focus does not change route visibility. Inactive can still mean
/// a visible window (including Android split screen and desktop focus loss).
bool suppressVisibleChannelNotification({
  required bool isVisible,
  required AppLifecycleState? lifecycleState,
}) => isVisible && switch (lifecycleState) {
  null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
  AppLifecycleState.hidden ||
  AppLifecycleState.paused ||
  AppLifecycleState.detached => false,
};
