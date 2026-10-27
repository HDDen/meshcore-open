import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/uptime_heartbeat_monitor.dart';

Map<String, Object> _beat(int sequence, int uptime, {int generation = 3,
  bool monitor = true}) => {'sequence': sequence, 'uptimeMs': uptime,
    'generation': generation, 'monitor': monitor};

void main() {
  test('CPU sleep and wall-clock changes do not consume awake grace', () {
    final monitor = UptimeHeartbeatMonitor(generation: 3, startedAt: 1000);
    expect(monitor.receive({..._beat(1, 1000), 'timestampMs': 0}, 1000), isTrue);
    // Wall time can advance hours or move backwards; only native uptime is used.
    expect(monitor.expired(1001), isFalse);
    expect(monitor.receive({..._beat(2, 1001), 'timestampMs': -9999999}, 1001), isTrue);
    expect(monitor.expired(21000), isFalse);
    expect(monitor.expired(21001), isTrue);
  });

  test('startup persisted monitoring has twenty seconds of awake grace', () {
    final monitor = UptimeHeartbeatMonitor(generation: 3, startedAt: 100);
    monitor.restoreMonitoring(true);
    expect(monitor.expired(20099), isFalse);
    expect(monitor.expired(20100), isTrue);
  });

  test('old worker, duplicate, reordered and delayed heartbeats cannot revive state', () {
    final monitor = UptimeHeartbeatMonitor(generation: 3, startedAt: 0);
    expect(monitor.receive(_beat(5, 1000), 1000), isTrue);
    expect(monitor.receive(_beat(6, 1000, generation: 2), 2000), isFalse);
    expect(monitor.receive(_beat(4, 2000), 2000), isFalse);
    expect(monitor.receive(_beat(5, 2000), 2000), isFalse);
    expect(monitor.receive(_beat(6, 1000), 21000), isFalse);
    expect(monitor.expired(21000), isTrue);
    expect(monitor.receive(_beat(7, 21000), 21000), isTrue);
    expect(monitor.expired(21000), isFalse);
  });

  test('new disable applies even if delayed, old disable cannot cancel a new session', () {
    final monitor = UptimeHeartbeatMonitor(generation: 3, startedAt: 0);
    monitor.receive(_beat(1, 0), 0);
    expect(monitor.receive(_beat(2, 0, monitor: false), 30000), isTrue);
    expect(monitor.expired(100000), isFalse);
    expect(monitor.receive(_beat(3, 100000), 100000), isTrue);
    expect(monitor.receive(_beat(2, 100000, monitor: false), 100000), isFalse);
    expect(monitor.monitoring, isTrue);
  });

  test('malformed or future uptime never resets the deadline', () {
    final monitor = UptimeHeartbeatMonitor(generation: 3, startedAt: 0);
    monitor.restoreMonitoring(true);
    for (final data in [<String, Object>{}, _beat(1, -1), _beat(1, 201),
      {..._beat(1, 200), 'sequence': '1'}]) {
      expect(monitor.receive(data, 200), isFalse);
    }
    expect(monitor.expired(20000), isTrue);
  });

  test('new main session resets sequence, old session data cannot undo it', () {
    final monitor = UptimeHeartbeatMonitor(generation: 3, startedAt: 0);
    expect(monitor.receive({..._beat(100, 0), 'session': 1}, 0, session: 1), isTrue);
    expect(monitor.receive({..._beat(1, 100), 'session': 2}, 100, session: 2), isTrue);
    expect(monitor.receive({..._beat(101, 100), 'session': 1}, 100, session: 2), isFalse);
    expect(monitor.expired(20099), isFalse);
  });
}
