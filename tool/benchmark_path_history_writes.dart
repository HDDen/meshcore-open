import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Measures the actual DDL/upsert text from the application source in native
/// in-memory SQLite. `--ref <git-ref>` reads the earlier statement via git show.
/// This isolates SQL row changes; it is not the Drift pipeline or disk/fsync.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty &&
      (arguments.length != 2 || arguments.first != '--ref')) {
    throw ArgumentError('Usage: benchmark_path_history_writes.dart [--ref git-ref]');
  }
  final root = Directory.fromUri(Platform.script.resolve('../'));
  const path = 'lib/storage/message_history_database.dart';
  final String source;
  if (arguments.isEmpty) {
    source = await File.fromUri(Platform.script.resolve('../$path')).readAsString();
  } else {
    final result = await Process.run(
      'git', ['show', '${arguments[1]}:$path'], workingDirectory: root.path,
    );
    if (result.exitCode != 0) {
      throw StateError('Cannot read reference SQL: ${result.stderr}');
    }
    source = result.stdout as String;
  }
  final normalized = source.replaceAll('\r\n', '\n');
  final ddlStart = normalized.indexOf('CREATE TABLE IF NOT EXISTS contact_path_history (');
  final methodStart = normalized.indexOf('Future<void> writePathHistory({');
  if (ddlStart < 0 || methodStart < 0) {
    throw StateError('Path-history source changed; review SQL extraction');
  }
  final ddlEnd = normalized.indexOf("'''", ddlStart);
  final queryStart = normalized.indexOf("'''", methodStart);
  final queryEnd = normalized.indexOf("'''", queryStart + 3);
  if (ddlEnd < 0 || queryStart < 0 || queryEnd < 0) {
    throw StateError('Cannot locate the path-history SQL literals');
  }
  final ddl = normalized.substring(ddlStart, ddlEnd).trim();
  final sql = normalized.substring(queryStart + 3, queryEnd).trim();
  final database = sqlite3.openInMemory();
  try {
    database.execute(ddl);
    stdout.writeln('SQL source=${arguments.isEmpty ? 'working tree' : arguments[1]}');
    stdout.writeln('Fixed synthetic corpus; in-memory SQLite; not Drift, RX, disk/fsync or energy.');
    const saves = 1000;
    final nodeKey = 'aa' * 5;
    final contactKey = 'bb' * 32;
    int changes() => database.select('SELECT total_changes() AS n').single['n'] as int;
    for (final scenario in ['unchanged', 'changing', 'alternating']) {
      database.execute('DELETE FROM contact_path_history');
      database.execute(sql, [nodeKey, contactKey, _snapshot(0)]);
      final snapshots = [
        for (var i = 1; i <= saves; i++)
          _snapshot(scenario == 'unchanged' ? 0 : scenario == 'changing' ? i : i % 2),
      ];
      final before = changes();
      final timer = Stopwatch()..start();
      for (final snapshot in snapshots) {
        database.execute(sql, [nodeKey, contactKey, snapshot]);
      }
      timer.stop();
      final changedRows = changes() - before;
      final actual = database.select(
        'SELECT history_json FROM contact_path_history WHERE node_key = ? AND contact_key = ?',
        [nodeKey, contactKey],
      ).single['history_json'];
      if (actual != snapshots.last) {
        throw StateError('Final snapshot differs for $scenario');
      }
      stdout.writeln('scenario=$scenario saves=$saves changedRows=$changedRows '
          'elapsedUs=${timer.elapsedMicroseconds}; finalSnapshot=equal');
    }
  } finally {
    database.close();
  }
}

String _snapshot(int sequence) => jsonEncode({
  'recent_paths': [{
    'hop_count': 1,
    'trip_time_ms': 200 + sequence,
    'timestamp': '2026-01-01T00:00:00.000Z',
    'was_flood': false,
    'path_bytes': [23],
    'success_count': sequence + 1,
    'failure_count': 0,
    'route_weight': 1.0,
  }],
});
