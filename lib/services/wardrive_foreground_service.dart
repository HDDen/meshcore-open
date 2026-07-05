import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/platform_info.dart';
import 'notification_service.dart';

class WardriveForegroundService {
  static const MethodChannel _channel = MethodChannel(
    'mco_advanced/wardrive_foreground',
  );

  Future<bool> ensureAndroidRequirements() async {
    if (!PlatformInfo.isAndroid) return true;

    final notificationsGranted = await NotificationService()
        .requestPermissions();
    if (!notificationsGranted) {
      throw StateError(
        'Notification permission is required for background wardrive',
      );
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw StateError('Phone location service is disabled');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw StateError('Phone location permission was denied');
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError('Phone location permission is permanently denied');
    }
    if (permission != LocationPermission.always) {
      // Android grants background location from system settings on modern
      // versions, so do not silently enable a background mode that cannot
      // provide fresh GPS fixes after the app is minimized.
      await Geolocator.openAppSettings();
      throw StateError(
        'Allow all the time location is required for background wardrive',
      );
    }

    final batteryOptimizationIgnored = await _isIgnoringBatteryOptimizations();
    if (!batteryOptimizationIgnored) {
      await _openAppBackgroundSettings();
      throw StateError(
        'Allow background activity and disable battery optimization for background wardrive',
      );
    }
    return true;
  }

  Future<bool> _isIgnoringBatteryOptimizations() async {
    if (!PlatformInfo.isAndroid) return true;
    return await _channel.invokeMethod<bool>(
          'isIgnoringBatteryOptimizations',
        ) ??
        false;
  }

  Future<void> _openAppBackgroundSettings() async {
    if (!PlatformInfo.isAndroid) return;
    await _channel.invokeMethod<void>('openAppBackgroundSettings');
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
