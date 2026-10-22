import 'background_work_tracker.dart';

/// Учёт исходной записи и логической команды без изменения их timeout/ошибок.
class FrameBackgroundWork {
  FrameBackgroundWork(this._tracker);

  final BackgroundWorkTracker _tracker;

  Future<void> write(Future<void> Function() operation) =>
      _run(BackgroundWorkKind.transportWrite, operation);

  Future<void> command({
    required bool awaitsReply,
    required Future<void> Function() operation,
  }) => awaitsReply ? _run(BackgroundWorkKind.commandReply, operation) : operation();

  Future<void> _run(BackgroundWorkKind kind, Future<void> Function() operation) {
    // Закрытие учёта не добавляет ошибок в поздние callbacks старого connector.
    // Уже начатые операции освобождают прежние leases через свой finally.
    if (_tracker.isClosed) return operation();
    return _tracker.run(kind, operation);
  }
}
