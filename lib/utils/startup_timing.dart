import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

/// How long each step of the startup took, appended to [fileName] next to
/// the executable when the app is started with [argument]: a slow step shows
/// up in one run, without a debugger. Off, every call returns at once.
abstract final class StartupTiming {
  static const String argument = '--loading-timing';
  static const String fileName = 'loading_timing.txt';

  static final Stopwatch _clock = Stopwatch();
  static final List<(String, Duration)> _marks = [];
  static List<String> _arguments = const [];
  static DateTime? _startedAt;
  static bool _enabled = false;
  static bool _written = false;

  static bool get enabled => _enabled;

  /// Starts the clock when [args] ask for timings; the first call in `main`.
  static void start(List<String> args) {
    _enabled = !kIsWeb && args.contains(argument);
    if (!_enabled) return;
    _arguments = List.of(args);
    _startedAt = DateTime.now();
    _clock.start();
    mark('main');
  }

  /// The step named [label] starts now, and the one before it ends.
  static void mark(String label) {
    if (_enabled) _marks.add((label, _clock.elapsed));
  }

  /// Ends the last step at [label] and appends this run to the file. Once
  /// per run; the process start is looked up only now, after the startup.
  static Future<void> finish(String label) async {
    if (!_enabled || _written) return;
    _written = true;
    mark(label);
    final startedAt = _startedAt!;
    final buffer = StringBuffer()
      ..writeln('=== ${startedAt.toIso8601String()}  ${_arguments.join(' ')}');
    final processStart = await _processStart();
    if (processStart != null) {
      final beforeMain = startedAt.difference(processStart).inMilliseconds;
      buffer.writeln('process start to main: $beforeMain ms');
    }
    for (var i = 0; i < _marks.length; i++) {
      final (name, at) = _marks[i];
      final took = i + 1 < _marks.length
          ? '${(_marks[i + 1].$2 - at).inMilliseconds} ms'
          : '';
      final seconds = (at.inMicroseconds / 1e6).toStringAsFixed(3);
      buffer.writeln('${'$seconds s'.padLeft(10)}  ${took.padLeft(9)}  $name');
    }
    buffer.writeln();
    try {
      await File(
        p.join(p.dirname(Platform.resolvedExecutable), fileName),
      ).writeAsString(buffer.toString(), mode: FileMode.append, flush: true);
    } on FileSystemException {
      // A diagnostic: a folder that cannot be written loses it, nothing else.
    }
  }

  /// When this process started, where the system says so cheaply.
  static Future<DateTime?> _processStart() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '(Get-Process -Id $pid).StartTime.ToUniversalTime().ToString("o")',
        ]);
        return DateTime.tryParse('${result.stdout}'.trim())?.toLocal();
      }
      if (Platform.isLinux) {
        // Field 22 of /proc/self/stat is the start in clock ticks since
        // boot, at the usual 100 a second; /proc/uptime is seconds since boot.
        final stat = await File('/proc/self/stat').readAsString();
        final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
        final startTicks = int.parse(fields[19]);
        final uptime = double.parse(
          (await File('/proc/uptime').readAsString()).split(' ').first,
        );
        final age = Duration(
          microseconds: ((uptime - startTicks / 100) * 1e6).round(),
        );
        return DateTime.now().subtract(age);
      }
    } on Object {
      // Unknown, and left out of the file.
    }
    return null;
  }
}
