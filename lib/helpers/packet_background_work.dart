import 'background_work_tracker.dart';

/// Внешние async-границы; вложенные writer/ACK и message work независимы.
class PacketBackgroundWork {
  PacketBackgroundWork(this._tracker);

  final BackgroundWorkTracker _tracker;

  Future<void> dispatch(Future<void> Function() operation) =>
      _run(BackgroundWorkKind.frameDispatch, operation);

  Future<void> receive(Future<void> Function() operation) =>
      _run(BackgroundWorkKind.radioReceive, operation);

  Future<void> replay(Future<void> Function() operation) =>
      _run(BackgroundWorkKind.messageReplay, operation);

  Future<void> _run(BackgroundWorkKind kind, Future<void> Function() operation) {
    if (_tracker.isClosed) return operation();
    final lease = _tracker.begin(kind);
    try {
      // Не делать метод async: interceptor может бросать синхронно.
      return operation().whenComplete(lease.release);
    } catch (_) {
      lease.release();
      rethrow;
    }
  }
}
