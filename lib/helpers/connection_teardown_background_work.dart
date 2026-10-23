import 'background_work_tracker.dart';

/// Сам teardown и фактический cleanup после истечения времени ожидания.
class ConnectionTeardownBackgroundWork {
  ConnectionTeardownBackgroundWork(this._tracker);

  final BackgroundWorkTracker _tracker;

  Future<T> run<T>(Future<T> Function() operation) {
    if (_tracker.isClosed) return operation();
    return _tracker.run(BackgroundWorkKind.transportTeardown, operation);
  }

  Future<void>? cleanup(Future<void>? Function() action) {
    if (_tracker.isClosed) return action();
    final lease = _tracker.begin(BackgroundWorkKind.transportTeardown);
    try {
      final pending = action();
      if (pending == null) {
        lease.release();
        return null;
      }
      // Этот Future находится ниже timeout: позднее завершение снимает
      // только своё удержание, не возобновляя прежний teardown.
      return pending.whenComplete(lease.release);
    } catch (_) {
      lease.release();
      rethrow;
    }
  }
}
