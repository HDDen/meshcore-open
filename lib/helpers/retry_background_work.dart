import 'background_work_tracker.dart';

/// Ожидания очереди/ACK отдельно от реально незавершённых retry-попыток.
class RetryBackgroundWork {
  BackgroundWorkTracker? _tracker;
  final Map<String, BackgroundWorkLease> _waiting = {};
  bool _closed = false;

  void attach(BackgroundWorkTracker? tracker, Iterable<String> waitingIds) {
    if (!identical(_tracker, tracker)) {
      finishAll();
      _tracker = tracker;
    }
    synchronize(waitingIds);
  }

  void begin(String messageId) {
    final tracker = _tracker;
    if (_closed || tracker == null || tracker.isClosed ||
        _waiting.containsKey(messageId)) {
      return;
    }
    _waiting[messageId] = tracker.begin(BackgroundWorkKind.retry);
  }

  void synchronize(Iterable<String> waitingIds) {
    final ids = waitingIds.toSet();
    for (final id in ids) {
      begin(id);
    }
    for (final id in _waiting.keys.toList()) {
      if (!ids.contains(id)) {
        finish(id);
      }
    }
  }

  void finish(String messageId) => _waiting.remove(messageId)?.release();

  void finishAll() {
    final leases = _waiting.values.toList();
    _waiting.clear();
    for (final lease in leases) {
      lease.release();
    }
  }

  Future<void> run(Future<void> Function() operation) {
    final tracker = _tracker;
    // Rebind/pause/cancel снимают ожидания, а старый Future хранит свой lease.
    if (_closed || tracker == null || tracker.isClosed) {
      return operation();
    }
    return tracker.run(BackgroundWorkKind.retry, operation);
  }

  void close() {
    _closed = true;
    finishAll();
  }
}
