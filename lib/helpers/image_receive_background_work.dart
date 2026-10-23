import 'background_work_tracker.dart';

/// Фактическая обработка принятых изображений, без пассивной очереди чанков.
class ImageReceiveBackgroundWork {
  final Set<BackgroundWorkTracker> _trackers = {};
  final Set<_ImageReceiveOperation> _operations = {};

  void attach(BackgroundWorkTracker tracker) {
    if (tracker.isClosed) return;
    _trackers.add(tracker);
    // Store может начать сохранение/декодирование до привязки коннектора.
    for (final operation in _operations) {
      operation.track(tracker);
    }
  }

  void detach(BackgroundWorkTracker tracker) => _trackers.remove(tracker);

  // Смена владельца не завершает выполняющийся callback.
  void detachAll() => _trackers.clear();

  Future<T> run<T>(Future<T> Function() operation) async {
    final pending = _ImageReceiveOperation();
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

class _ImageReceiveOperation {
  final Map<BackgroundWorkTracker, BackgroundWorkLease> _leases = {};

  void track(BackgroundWorkTracker tracker) {
    if (!tracker.isClosed && !_leases.containsKey(tracker)) {
      _leases[tracker] = tracker.begin(BackgroundWorkKind.receiveAssembly);
    }
  }

  void finish() {
    for (final lease in _leases.values) {
      lease.release();
    }
    _leases.clear();
  }
}
