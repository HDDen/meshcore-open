/// Uses Android uptime (excludes deep sleep), never wall time or callback count.
class UptimeHeartbeatMonitor {
  UptimeHeartbeatMonitor({required this.generation, required int startedAt})
      : _anchor = startedAt;

  final int generation;
  int _anchor;
  int _sequence = -1;
  int? _session;
  bool monitoring = false;

  bool receive(Map data, int now, {int? session}) {
    if (session != null) {
      if (data['session'] != session) return false;
      if (_session != session) { _session = session; _sequence = -1; }
    }
    final sequence = data['sequence'];
    final uptime = data['uptimeMs'];
    if (data['monitor'] is! bool || data['generation'] != generation || sequence is! int ||
        sequence <= _sequence || uptime is! int || uptime < 0 ||
        uptime > now || (data['monitor'] == true && now - uptime >= 20000)) {
      return false;
    }
    _sequence = sequence;
    monitoring = data['monitor'] == true;
    _anchor = uptime;
    return true;
  }

  void restoreMonitoring(bool enabled) { monitoring = enabled; }

  bool expired(int now) => monitoring && now >= _anchor && now - _anchor >= 20000;
}
