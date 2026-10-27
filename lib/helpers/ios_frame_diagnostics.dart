/// Counts callbacks delivered to Dart, not frame requests or GPU submissions.
/// It neither schedules work nor changes the presentation policy.
class IosFrameDiagnostics {
  IosFrameDiagnostics({int Function()? nowMs}) : _nowMs = nowMs ?? _clock();

  static int Function() _clock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMilliseconds;
  }

  final int Function() _nowMs;
  bool _allowed = true;
  int _epoch = 0;
  int? _gatedAt;
  int _gatedElapsedMs = 0;
  int _begins = 0;
  int _warmUps = 0;
  int _draws = 0;
  int _suppressed = 0;
  int _gatedBegins = 0;
  int _gatedWarmUps = 0;
  int _gatedDraws = 0;
  int _gatedSuppressed = 0;

  void presentationChanged(bool allowed) {
    if (_allowed == allowed) {
      return;
    }
    if (allowed) {
      _gatedElapsedMs = _elapsed();
      _gatedAt = null;
    } else {
      _epoch++;
      _gatedAt = _nowMs();
      _gatedElapsedMs = 0;
      _gatedBegins = 0;
      _gatedWarmUps = 0;
      _gatedDraws = 0;
      _gatedSuppressed = 0;
    }
    _allowed = allowed;
  }

  void beginFrame({required bool warmUp}) {
    _begins++;
    if (warmUp) {
      _warmUps++;
    }
    if (!_allowed) {
      _gatedBegins++;
      if (warmUp) {
        _gatedWarmUps++;
      }
    }
  }

  void drawFrame({required bool suppressed}) {
    _draws++;
    if (suppressed) {
      _suppressed++;
    }
    if (!_allowed) {
      _gatedDraws++;
      if (suppressed) {
        _gatedSuppressed++;
      }
    }
  }

  int _elapsed() {
    final start = _gatedAt;
    if (start == null) {
      return _gatedElapsedMs;
    }
    final elapsed = _nowMs() - start;
    return elapsed < 0 ? 0 : elapsed;
  }

  Map<String, Object> get snapshot => <String, Object>{
    'frameSchema': 1,
    'gateEpoch': _epoch,
    'presentationAllowed': _allowed,
    'beginCallbacks': _begins,
    'warmUpCallbacks': _warmUps,
    'drawCallbacks': _draws,
    'pipelinePasses': _draws - _suppressed,
    'suppressedDraws': _suppressed,
    'gatedElapsedMs': _elapsed(),
    'gatedBeginCallbacks': _gatedBegins,
    'gatedWarmUpCallbacks': _gatedWarmUps,
    'gatedDrawCallbacks': _gatedDraws,
    'gatedSuppressedDraws': _gatedSuppressed,
  };

  String get summary => snapshot.entries.map((e) => '${e.key}=${e.value}').join(', ');
}
