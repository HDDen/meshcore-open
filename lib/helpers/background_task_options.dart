import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Static Android experiment; ordinary builds retain the plugin CPU lock.
const bool kDiagnosticCpuOff = bool.fromEnvironment('MCO_DIAGNOSTIC_CPU_OFF');

ForegroundTaskOptions backgroundTaskOptions({
  bool diagnosticCpuOff = kDiagnosticCpuOff,
}) => ForegroundTaskOptions(
  eventAction: ForegroundTaskEventAction.repeat(5000),
  autoRunOnBoot: false,
  allowWakeLock: !diagnosticCpuOff,
  allowWifiLock: false,
);
