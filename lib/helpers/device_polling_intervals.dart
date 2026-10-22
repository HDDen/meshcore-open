import '../models/power_saving_settings.dart';

/// Общие интервалы ноды и связанный с батарейным опросом контроль тишины.
class DevicePollingIntervals {
  const DevicePollingIntervals({
    this.battery = const Duration(seconds: PowerSavingOptions.minBatteryInterval),
    this.gps = const Duration(seconds: PowerSavingOptions.minGpsInterval),
  });

  factory DevicePollingIntervals.fromOptions(PowerSavingOptions? options) =>
      DevicePollingIntervals(
        battery: Duration(seconds: options?.batteryIntervalSeconds ??
            PowerSavingOptions.minBatteryInterval),
        gps: Duration(seconds: options?.gpsIntervalSeconds ??
            PowerSavingOptions.minGpsInterval),
      );

  static const watchdogCheck = Duration(seconds: 60);
  final Duration battery;
  final Duration gps;

  Duration get watchdogSilence => battery * 2 + watchdogCheck;
}
