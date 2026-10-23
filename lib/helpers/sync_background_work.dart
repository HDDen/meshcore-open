import 'background_work_tracker.dart';

/// Ожидание sync-ответов отдельно от реально выполняющихся async-участков.
class SyncBackgroundWork {
  SyncBackgroundWork(this._tracker, this._kind);

  final BackgroundWorkTracker _tracker;
  final BackgroundWorkKind _kind;
  BackgroundWorkLease? _current;

  BackgroundWorkLease? get current => _current;

  BackgroundWorkLease? begin() {
    final next = _tracker.isClosed ? null : _tracker.begin(_kind);
    final previous = _current;
    _current = next;
    previous?.release();
    return next;
  }

  void ensureStarted() {
    if (_current == null) {
      begin();
    }
  }

  void finish(BackgroundWorkLease? phase) {
    // Старое завершение не снимает фазу, начатую из синхронного callback.
    if (phase == null || !identical(_current, phase)) {
      return;
    }
    _current = null;
    phase.release();
  }

  void finishCurrent() => finish(_current);

  Future<T> run<T>(Future<T> Function() operation) {
    // Reset/новая фаза снимают ожидание, но не завершают чужой async Future.
    // После dispose поздний callback сохраняет прежнее поведение без leases.
    if (_tracker.isClosed) {
      return operation();
    }
    return _tracker.run(_kind, operation);
  }
}
