import 'dart:async';

/// Orders native updates for each notification while unrelated IDs can post
/// in parallel. A radio-wide clear is a barrier between the old and new radio.
class NotificationConversationWork {
  final _updates = <int, Future<void>>{};
  Future<void>? _barrier;

  Future<void>? pendingFor(int id) => _updates[id] ?? _barrier;

  Future<void> run(int? id, Future<void> Function() operation) async {
    final predecessors = [
      ?_barrier,
      if (id == null) ..._updates.values else ?_updates[id],
    ];
    final done = Completer<void>();
    if (id == null) {
      _barrier = done.future;
    } else {
      _updates[id] = done.future;
    }
    try {
      if (predecessors.isNotEmpty) await Future.wait(predecessors);
      await operation();
    } finally {
      done.complete();
      if (id == null) {
        if (identical(_barrier, done.future)) _barrier = null;
      } else if (identical(_updates[id], done.future)) {
        _updates.remove(id);
      }
    }
  }
}

/// A single firmware-queue drain can issue one audible alert.
class NotificationQueueAlert {
  bool alerted = false;
}
