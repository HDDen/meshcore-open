import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/platform_info.dart';
import 'notification_service.dart';

class WardriveForegroundService {
  static const MethodChannel _channel = MethodChannel(
    'mco_advanced/wardrive_foreground',
  );

  Future<bool> ensureAndroidRequirements() async {
    if (!PlatformInfo.isAndroid) return true;

    _WardriveAndroidRequirement? previousRequirement;
    var previousSettingsReturnedToApp = false;
    for (var attempt = 0; attempt < _maxSettingsPasses; attempt++) {
      final requirement = await _firstMissingAndroidRequirement();
      if (requirement == null) return true;
      if (requirement == previousRequirement) {
        await Future<void>.delayed(_postSettingsRecheckDelay);
        final refreshedRequirement = await _firstMissingAndroidRequirement();
        if (refreshedRequirement == null) return true;
        if (refreshedRequirement == previousRequirement) {
          if (!previousSettingsReturnedToApp) {
            throw const WardriveRequirementNotCompletedException();
          }
          throw StateError(refreshedRequirement.errorText);
        }
        previousRequirement = refreshedRequirement;
        previousSettingsReturnedToApp = await _openRequirementSettingsAndWait(
          refreshedRequirement,
        );
        continue;
      }
      previousRequirement = requirement;
      previousSettingsReturnedToApp = await _openRequirementSettingsAndWait(
        requirement,
      );
    }

    final requirement = await _firstMissingAndroidRequirement();
    if (requirement == null) return true;
    throw StateError(requirement.errorText);
  }

  static const int _maxSettingsPasses = 8;
  static const Duration _postSettingsRecheckDelay = Duration(milliseconds: 800);
  static const Duration _inPlaceSettingsRecheckDelay = Duration(seconds: 8);

  Future<_WardriveAndroidRequirement?> _firstMissingAndroidRequirement() async {
    final notificationService = NotificationService();
    var notificationsGranted = await notificationService
        .areNotificationsEnabled();
    if (!notificationsGranted) {
      notificationsGranted = await notificationService.requestPermissions();
    }
    if (!notificationsGranted) {
      return _WardriveAndroidRequirement.notifications;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return _WardriveAndroidRequirement.locationServices;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission != LocationPermission.always) {
      return _WardriveAndroidRequirement.locationAlways;
    }

    final batteryOptimizationIgnored = await _isIgnoringBatteryOptimizations();
    if (!batteryOptimizationIgnored) {
      return _WardriveAndroidRequirement.batteryOptimization;
    }

    return null;
  }

  Future<bool> _openRequirementSettingsAndWait(
    _WardriveAndroidRequirement requirement,
  ) async {
    final waiter = _AppResumeWaiter();
    WidgetsBinding.instance.addObserver(waiter);
    try {
      switch (requirement) {
        case _WardriveAndroidRequirement.notifications:
          await NotificationService().openAppNotificationSettings();
          break;
        case _WardriveAndroidRequirement.locationServices:
          await Geolocator.openLocationSettings();
          break;
        case _WardriveAndroidRequirement.locationAlways:
          await _openAppLocationPermissionSettings();
          break;
        case _WardriveAndroidRequirement.batteryOptimization:
          await _openBatteryOptimizationSettings();
          break;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      if (waiter.leftApp) {
        await waiter.future.timeout(
          const Duration(minutes: 5),
          onTimeout: () {},
        );
        await Future<void>.delayed(_postSettingsRecheckDelay);
        return true;
      } else {
        // Some Android settings actions, especially the battery optimization
        // exemption request, can appear as an in-place system dialog without a
        // full pause/resume lifecycle roundtrip. Give the user and the OS a
        // short window before rechecking, otherwise the caller can show an
        // error snackbar while the dialog is still being handled.
        await Future<void>.delayed(_inPlaceSettingsRecheckDelay);
        return false;
      }
    } finally {
      WidgetsBinding.instance.removeObserver(waiter);
    }
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

class WardriveRequirementNotCompletedException implements Exception {
  const WardriveRequirementNotCompletedException();
}

enum _WardriveAndroidRequirement {
  notifications('Notification permission is required for background wardrive'),
  locationServices('Phone location service is disabled'),
  locationAlways(
    'Allow all the time location is required for background wardrive',
  ),
  batteryOptimization(
    'Allow background activity and disable battery optimization for background wardrive',
  );

  const _WardriveAndroidRequirement(this.errorText);

  final String errorText;
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
