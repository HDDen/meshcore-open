import 'package:flutter/services.dart';

class CpuRuntimeClock {
  const CpuRuntimeClock(this.uptimeMs, this.generation, this.managed, this.session,
    {this.unconditional = false, this.supportsUnconditional = false});
  final int uptimeMs;
  final int generation;
  final bool managed;
  final int session;
  final bool unconditional;
  final bool supportsUnconditional;

  static CpuRuntimeClock? parse(Object? value) {
    if (value is! Map || value['schema'] != 1 ||
        value['uptimeMs'] is! int || value['generation'] is! int ||
        value['managed'] is! bool) {
      return null;
    }
    final uptime = value['uptimeMs'] as int;
    if (uptime < 0) return null;
    return CpuRuntimeClock(uptime, value['generation'] as int,
        value['managed'] as bool, value['session'] is int ? value['session'] as int : 0,
        unconditional: value['unconditional'] == true,
        supportsUnconditional: value['supportsUnconditional'] == true);
  }
}

/// Registered separately in the main and foreground-task engines on Android.
class AndroidCpuRuntime {
  static const channel = MethodChannel('mco_advanced/cpu_policy');

  static Future<CpuRuntimeClock?> clock({bool workerReady = false}) async =>
      CpuRuntimeClock.parse(await channel.invokeMethod<Object>(
        workerReady ? 'workerReady' : 'clock'));

  static Future<void> configure({required bool hold, required bool work,
    bool migrate = false, bool unconditional = false}) async {
    // An older APK must not silently accept a mode its native adapter ignores.
    if (unconditional && (await clock())?.supportsUnconditional != true) {
      throw StateError('Unconditional CPU sleep requires an updated native adapter');
    }
    final result = await channel.invokeMethod<bool>('configure', {
      'hold': hold, 'work': work, 'migrate': migrate,
      'unconditional': unconditional,
    });
    if (result != true) throw StateError('CPU policy native adapter unavailable');
  }

  static Future<void> diagnostic(bool enabled) =>
      channel.invokeMethod<void>('diagnostic', {'enabled': enabled});
  static Future<void> beginMainSession() => channel.invokeMethod<void>('mainSession');
  static Future<void> tickDone() => channel.invokeMethod<void>('tickDone');
  static Future<void> stopped() => channel.invokeMethod<void>('serviceStopped');
}
