import 'background_work_tracker.dart';

/// Логическое ожидание ответа SYNC_NEXT, отдельно от writer и обработки кадра.
class QueuedMessageRequestBackgroundWork {
  QueuedMessageRequestBackgroundWork(this._tracker);

  final BackgroundWorkTracker _tracker;
  BackgroundWorkLease? _current;

  BackgroundWorkLease? begin() {
    // Новый запрос замещает прежнее ожидание, но не его незавершённый I/O.
    final next = _tracker.isClosed
        ? null
        : _tracker.begin(BackgroundWorkKind.queuedMessageRequest);
    final previous = _current;
    _current = next;
    previous?.release();
    return next;
  }

  void finish(BackgroundWorkLease? request) {
    if (request == null || !identical(_current, request)) {
      return;
    }
    _current = null;
    request.release();
  }

  /// Прежний алгоритм получил ответ, остановил очередь или сбросил её состояние.
  void finishCurrent() => finish(_current);
}
