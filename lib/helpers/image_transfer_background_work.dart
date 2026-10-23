import 'background_work_tracker.dart';

/// Исходная передача целиком: очередь канала, ACK, паузы и reset scope.
class ImageTransferBackgroundWork {
  ImageTransferBackgroundWork(this._tracker);

  final BackgroundWorkTracker _tracker;

  Future<T> run<T>(Future<T> Function() operation) {
    // Dispose не завершает начатую передачу; её finally снимет свой lease.
    // Поздний вызов после close сохраняет исходные результат и ошибки.
    if (_tracker.isClosed) return operation();
    return _tracker.run(BackgroundWorkKind.imageTransfer, operation);
  }
}
