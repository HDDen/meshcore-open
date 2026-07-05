import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart';

/// Timeline state for the packet-flow animation on the path map.
///
/// The packet travels each segment over [segmentMs] (scaled by [speed]),
/// then dwells at the reached hop for [dwellMs] so the hop visibly lights up.
/// Overlay layers listen to this controller directly; [activeSegment] only
/// fires when the segment index changes so list highlights rebuild cheaply.
class PathPlaybackController extends ChangeNotifier {
  static const double segmentMs = 1100;
  static const double dwellMs = 380;
  static const List<double> speedSteps = [0.5, 1.0, 2.0];

  late final Ticker _ticker;
  List<LatLng> _points = const [];
  double _timelineMs = 0;
  Duration _lastTick = Duration.zero;
  bool _playing = false;
  bool _started = false;
  double _speed = 1.0;

  /// Segment currently being traveled (clamped to the last segment), or -1
  /// while the animation has not been started — listeners use this for
  /// hop-list highlighting without rebuilding every tick.
  final ValueNotifier<int> activeSegment = ValueNotifier(-1);

  PathPlaybackController(TickerProvider vsync) {
    _ticker = vsync.createTicker(_onTick);
  }

  List<LatLng> get points => _points;
  bool get hasPath => _points.length >= 2;
  int get segmentCount => hasPath ? _points.length - 1 : 0;
  bool get playing => _playing;
  double get speed => _speed;

  /// True once the user has started or stepped the animation; the packet
  /// overlay renders only in this state.
  bool get started => _started;

  double get _slotMs => segmentMs + dwellMs;
  double get _totalMs => segmentCount * _slotMs;
  bool get isComplete => hasPath && _timelineMs >= _totalMs;

  int get currentSegment {
    if (!hasPath) return 0;
    return (_timelineMs / _slotMs).floor().clamp(0, segmentCount - 1);
  }

  /// Travel progress through [currentSegment]; 1.0 while dwelling at its end.
  double get segmentProgress {
    if (!hasPath) return 0;
    final within = _timelineMs - currentSegment * _slotMs;
    return (within / segmentMs).clamp(0.0, 1.0);
  }

  /// Dwell progress (0..1) at the reached hop, or null while traveling.
  double? get dwellProgress {
    if (!hasPath || isComplete) return null;
    final within = _timelineMs - currentSegment * _slotMs;
    if (within < segmentMs) return null;
    return ((within - segmentMs) / dwellMs).clamp(0.0, 1.0);
  }

  /// Index of the point the packet has most recently reached.
  int get reachedPointIndex {
    if (!hasPath) return 0;
    if (isComplete) return _points.length - 1;
    return segmentProgress >= 1.0 ? currentSegment + 1 : currentSegment;
  }

  LatLng get position {
    if (!hasPath) return const LatLng(0, 0);
    final seg = currentSegment;
    final a = _points[seg];
    final b = _points[seg + 1];
    final t = segmentProgress;
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  /// Replaces the path and resets the animation to the start.
  void setPath(List<LatLng> points) {
    _ticker.stop();
    _points = List.unmodifiable(points);
    _timelineMs = 0;
    _playing = false;
    _started = false;
    activeSegment.value = -1;
    notifyListeners();
  }

  void play() {
    if (!hasPath) return;
    if (isComplete) _timelineMs = 0;
    _started = true;
    _playing = true;
    activeSegment.value = currentSegment;
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
    notifyListeners();
  }

  void pause() {
    _ticker.stop();
    _playing = false;
    notifyListeners();
  }

  void togglePlay() => _playing ? pause() : play();

  void replay() {
    if (!hasPath) return;
    _timelineMs = 0;
    activeSegment.value = 0;
    play();
  }

  /// Stops playback and hides the packet overlay.
  void stop() {
    _ticker.stop();
    _playing = false;
    _started = false;
    _timelineMs = 0;
    activeSegment.value = -1;
    notifyListeners();
  }

  void stepForward() => _jumpToPoint(reachedPointIndex + 1);

  void stepBack() => _jumpToPoint(reachedPointIndex - 1);

  void cycleSpeed() {
    final index = speedSteps.indexOf(_speed);
    _speed = speedSteps[(index + 1) % speedSteps.length];
    notifyListeners();
  }

  void _jumpToPoint(int index) {
    if (!hasPath) return;
    _ticker.stop();
    _playing = false;
    _started = true;
    final clamped = index.clamp(0, _points.length - 1);
    // Land at the start of the dwell window so the hop pulse plays.
    _timelineMs = clamped == 0 ? 0 : (clamped - 1) * _slotMs + segmentMs;
    activeSegment.value = currentSegment;
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    final dtMs = (elapsed - _lastTick).inMicroseconds / 1000.0;
    _lastTick = elapsed;
    _timelineMs = (_timelineMs + dtMs * _speed).clamp(0.0, _totalMs);
    if (_timelineMs >= _totalMs) {
      _ticker.stop();
      _playing = false;
    }
    if (activeSegment.value != currentSegment) {
      activeSegment.value = currentSegment;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    activeSegment.dispose();
    super.dispose();
  }
}
