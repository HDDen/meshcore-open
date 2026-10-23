import 'background_work_tracker.dart';

/// Уведомления singleton-сервиса с независимыми наблюдателями коннектора.
class NotificationBackgroundWork {
  final Set<BackgroundWorkTracker> _trackers = {};
  final Set<_NotificationOperation> _operations = {};

  void attach(BackgroundWorkTracker tracker) {
    if (tracker.isClosed) return;
    _trackers.add(tracker);
    // Новый коннектор принимает также ещё не завершённые уведомления.
    for (final operation in _operations) {
      operation.track(tracker);
    }
  }

  void detach(BackgroundWorkTracker tracker) => _trackers.remove(tracker);

  // Снятие наблюдателя не завершает native show/cancel и их leases.
  void detachAll() => _trackers.clear();

  Future<T> run<T>(Future<T> Function() operation) async {
    final pending = _NotificationOperation();
    _operations.add(pending);
    _trackers.removeWhere((tracker) => tracker.isClosed);
    for (final tracker in _trackers) {
      pending.track(tracker);
    }
    try {
      return await operation();
    } finally {
      _operations.remove(pending);
      pending.finish();
    }
  }
}

class _NotificationOperation {
  final Map<BackgroundWorkTracker, BackgroundWorkLease> _leases = {};

  void track(BackgroundWorkTracker tracker) {
    if (!tracker.isClosed && !_leases.containsKey(tracker)) {
      _leases[tracker] = tracker.begin(BackgroundWorkKind.notification);
    }
  }

  void finish() {
    for (final lease in _leases.values) {
      lease.release();
    }
    _leases.clear();
  }
}
