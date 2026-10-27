import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Static experiment; takes precedence over the opt-in Android CPU policy.
const bool kDiagnosticCpuOff = bool.fromEnvironment('MCO_DIAGNOSTIC_CPU_OFF');

ForegroundTaskOptions backgroundTaskOptions({
  bool diagnosticCpuOff = kDiagnosticCpuOff,
  bool managedCpu = false,
}) => ForegroundTaskOptions(
  eventAction: ForegroundTaskEventAction.repeat(5000),
  autoRunOnBoot: false,
  allowWakeLock: !diagnosticCpuOff && !managedCpu,
  allowWifiLock: false,
);
