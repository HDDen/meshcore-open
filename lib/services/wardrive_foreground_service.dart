import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../helpers/wardrive_background_requirements.dart';
import '../utils/platform_info.dart';
import 'notification_service.dart';

/// The Android location foreground service behind background wardriving,
/// and what the phone has to allow before it may run.
class WardriveForegroundService {
  static const MethodChannel _channel = MethodChannel(
    'mco_advanced/wardrive_foreground',
  );

  static const Duration _postSettingsRecheckDelay = Duration(milliseconds: 800);
  static const Duration _inPlaceSettingsRecheckDelay = Duration(seconds: 8);

  /// The requirements the phone does not meet, in the order they are asked
  /// for. Nothing is asked here: a check at the start of a session must not
  /// open a system screen. Empty anywhere but Android.
  Future<List<WardriveBackgroundRequirement>>
  missingAndroidRequirements() async {
    if (!PlatformInfo.isAndroid) return const [];
    return [
      if (!await NotificationService().areNotificationsEnabled())
        WardriveBackgroundRequirement.notifications,
      if (!await Geolocator.isLocationServiceEnabled())
        WardriveBackgroundRequirement.locationServices,
      if (await Geolocator.checkPermission() != LocationPermission.always)
        WardriveBackgroundRequirement.locationAlways,
      if (await _isBackgroundRestricted())
        WardriveBackgroundRequirement.backgroundActivity,
      if (!await _isIgnoringBatteryOptimizations())
        WardriveBackgroundRequirement.batteryOptimization,
    ];
  }

  /// Asks for one [requirement]: the runtime prompt where Android has one,
  /// for the notification permission and the first location grant, else the
  /// system screen for it, waited out until the app comes back from that
  /// screen. Whether the requirement is met afterwards.
  Future<bool> requestAndroidRequirement(
    WardriveBackgroundRequirement requirement,
  ) async {
    if (!PlatformInfo.isAndroid) return true;
    switch (requirement) {
      case WardriveBackgroundRequirement.notifications:
        final notifications = NotificationService();
        if (await notifications.requestPermissions()) return true;
        await _openSettingsAndWait(notifications.openAppNotificationSettings);
        return notifications.areNotificationsEnabled();
      case WardriveBackgroundRequirement.locationServices:
        await _openSettingsAndWait(Geolocator.openLocationSettings);
        return Geolocator.isLocationServiceEnabled();
      case WardriveBackgroundRequirement.locationAlways:
        // "All the time" is granted on the app's permission screen; Android
        // asks for "while in use" first, in a prompt of its own.
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.always) return true;
        await _openSettingsAndWait(_openAppLocationPermissionSettings);
        return await Geolocator.checkPermission() == LocationPermission.always;
      case WardriveBackgroundRequirement.backgroundActivity:
        // The restriction is lifted on the app's own settings page, the one
        // entry every Android and OEM skin has.
        await _openSettingsAndWait(_openAppBackgroundSettings);
        return !await _isBackgroundRestricted();
      case WardriveBackgroundRequirement.batteryOptimization:
        await _openSettingsAndWait(_openBatteryOptimizationSettings);
        return _isIgnoringBatteryOptimizations();
    }
  }

  /// Runs [open], a system screen or dialog, and waits for the user to come
  /// back from it before the caller looks at the result.
  Future<void> _openSettingsAndWait(Future<void> Function() open) async {
    final waiter = _AppResumeWaiter();
    WidgetsBinding.instance.addObserver(waiter);
    try {
      await open();
      await Future<void>.delayed(const Duration(seconds: 1));
      if (waiter.leftApp) {
        await waiter.future.timeout(
          const Duration(minutes: 5),
          onTimeout: () {},
        );
        await Future<void>.delayed(_postSettingsRecheckDelay);
      } else {
        // Some Android settings actions, especially the battery optimization
        // exemption request, can appear as an in-place system dialog without
        // a full pause/resume lifecycle roundtrip. Give the user and the OS a
        // short window before rechecking, otherwise the caller can show a
        // message while the dialog is still being handled.
        await Future<void>.delayed(_inPlaceSettingsRecheckDelay);
      }
    } finally {
      WidgetsBinding.instance.removeObserver(waiter);
    }
  }

  Future<bool> _isBackgroundRestricted() async {
    if (!PlatformInfo.isAndroid) return false;
    return await _channel.invokeMethod<bool>('isBackgroundRestricted') ??
        false;
  }

  Future<void> _openAppBackgroundSettings() async {
    if (!PlatformInfo.isAndroid) return;
    await _channel.invokeMethod<void>('openAppBackgroundSettings');
  }

  Future<bool> _isIgnoringBatteryOptimizations() async {
    if (!PlatformInfo.isAndroid) return true;
    return await _channel.invokeMethod<bool>(
          'isIgnoringBatteryOptimizations',
        ) ??
        false;
  }

  Future<void> _openAppLocationPermissionSettings() async {
    if (!PlatformInfo.isAndroid) return;
    await _channel.invokeMethod<void>('openAppLocationPermissionSettings');
  }

  Future<void> _openBatteryOptimizationSettings() async {
    if (!PlatformInfo.isAndroid) return;
    await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
  }

  Future<void> start() async {
    if (!PlatformInfo.isAndroid) return;
    await _channel.invokeMethod<void>('start');
  }

  Future<void> stop() async {
    if (!PlatformInfo.isAndroid) return;
    await _channel.invokeMethod<void>('stop');
  }
}

class _AppResumeWaiter with WidgetsBindingObserver {
  final Completer<void> _completer = Completer<void>();
  var _leftApp = false;

  Future<void> get future => _completer.future;
  bool get leftApp => _leftApp;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _leftApp = true;
      return;
    }
    if (state == AppLifecycleState.resumed &&
        _leftApp &&
        !_completer.isCompleted) {
      _completer.complete();
    }
  }
}
