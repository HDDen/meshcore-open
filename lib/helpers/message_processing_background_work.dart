import 'background_work_tracker.dart';

/// Удерживает обработку кадра вместе с ожидаемой ею записью истории.
class MessageProcessingBackgroundWork {
  MessageProcessingBackgroundWork(this._tracker);

  final BackgroundWorkTracker _tracker;

  Future<void> run(Future<void> Function() operation) {
    // Поздний callback выполняется по прежним правилам, даже после dispose.
    // Закрытый снимок не является полным учётом фоновой работы.
    if (_tracker.isClosed) {
      return operation();
    }
    return _tracker.run(BackgroundWorkKind.messageSync, operation);
  }
}
