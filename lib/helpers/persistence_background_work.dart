import 'background_work_tracker.dart';

/// Общие записи истории с независимыми наблюдателями жизненного цикла UI.
class PersistenceBackgroundWork {
  final Set<BackgroundWorkTracker> _trackers = {};
  final Set<_PersistenceOperation> _operations = {};

  void attach(BackgroundWorkTracker tracker) {
    if (tracker.isClosed) return;
    _trackers.add(tracker);
    // Новый коннектор должен видеть также записи, начатые до его создания.
    for (final operation in _operations) {
      operation.track(tracker);
    }
  }

  void detach(BackgroundWorkTracker tracker) => _trackers.remove(tracker);

  // Снятие наблюдателя не завершает уже начатые записи и их leases.
  void detachAll() => _trackers.clear();

  Future<T> run<T>(Future<T> Function() operation) async {
    final pending = _PersistenceOperation();
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

class _PersistenceOperation {
  final Map<BackgroundWorkTracker, BackgroundWorkLease> _leases = {};

  void track(BackgroundWorkTracker tracker) {
    if (!tracker.isClosed && !_leases.containsKey(tracker)) {
      _leases[tracker] = tracker.begin(BackgroundWorkKind.persistence);
    }
  }

  void finish() {
    for (final lease in _leases.values) {
      lease.release();
    }
    _leases.clear();
  }
}
