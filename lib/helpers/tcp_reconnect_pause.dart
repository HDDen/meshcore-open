/// A process-local cooldown shared by all automatic TCP entry points.
/// A successful initial sync clears consecutive incomplete attempts, but only
/// a minute without repeated losses clears the rolling disconnect history.
class TcpReconnectPause {
  TcpReconnectPause({Duration Function()? now}) : _clock = now;

  static const failureLimit = 5;
  static const lossWindow = Duration(minutes: 1);
  static const pause = Duration(seconds: 30);
  final Duration Function()? _clock;
  final Stopwatch _uptime = Stopwatch()..start();
  final List<Duration> _losses = [];
  String? _endpoint;
  bool _attemptActive = false;
  bool _synchronized = false;
  int _incomplete = 0;
  Duration? _pausedUntil;

  Duration get _now => _clock?.call() ?? _uptime.elapsed;
  Duration get remaining {
    final until = _pausedUntil;
    if (until == null) return Duration.zero;
    final left = until - _now;
    return left > Duration.zero ? left : Duration.zero;
  }

  bool get isPaused => remaining > Duration.zero;

  void beginAttempt(String endpoint) {
    if (_endpoint != endpoint) {
      _endpoint = endpoint;
      _incomplete = 0;
      _losses.clear();
    }
    _attemptActive = true;
    _synchronized = false;
  }

  void markSynchronized() {
    if (!_attemptActive || _synchronized) return;
    _synchronized = true;
    _incomplete = 0;
  }

  /// Returns true only when this loss begins a new cooldown. Explicit user
  /// disconnects, duplicate teardown callbacks and losses during a cooldown
  /// cannot extend it. A manual dial does not clear an existing cooldown.
  bool endAttempt({required bool manual}) {
    if (!_attemptActive) return false;
    _attemptActive = false;
    if (manual) {
      _incomplete = 0;
      return false;
    }
    if (isPaused) return false;
    final now = _now;
    if (_synchronized) {
      _incomplete = 0;
    } else {
      _incomplete++;
    }
    _losses.removeWhere((at) => now - at >= lossWindow);
    _losses.add(now);
    if (_incomplete < failureLimit && _losses.length < failureLimit) return false;
    _pausedUntil = now + pause;
    _incomplete = 0;
    _losses.clear();
    return true;
  }
}
