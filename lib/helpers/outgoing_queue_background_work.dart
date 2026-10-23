import 'background_work_tracker.dart';

/// Учитывает исходные Future очередей, не меняя их таймеры и отмену.
class OutgoingQueueBackgroundWork {
  OutgoingQueueBackgroundWork(this._tracker);

  final BackgroundWorkTracker _tracker;

  Future<void> runRetry(Future<void> Function() operation) =>
      _run(BackgroundWorkKind.retry, operation);

  Future<void> runSend(Future<void> Function() operation) =>
      _run(BackgroundWorkKind.radioSend, operation);

  Future<void> _run(
    BackgroundWorkKind kind,
    Future<void> Function() operation,
  ) {
    // Dispose не завершает уже начатый Future. Поздний callback сохраняет
    // прежнее поведение без попытки зарегистрироваться в закрытом реестре.
    if (_tracker.isClosed) return operation();
    return _tracker.run(kind, operation);
  }
}
