import 'background_work_tracker.dart';
import 'radio_stats_send_polling.dart';

/// Общий учёт активной отправки вместе с прежним владельцем опроса.
class RadioSendBackgroundWork {
  RadioSendBackgroundWork(this._tracker, this._polling);

  final BackgroundWorkTracker _tracker;
  final RadioStatsSendPolling _polling;

  Future<void> run(Future<void> Function() operation) {
    // Удерживаем подготовку до первого writer и всё прежнее ожидание send.
    // После close поздний вызов сохраняет прежний порядок и polling.
    if (_tracker.isClosed) {
      return _polling.run(operation);
    }
    return _tracker.run(
      BackgroundWorkKind.radioSend,
      () => _polling.run(operation),
    );
  }
}
