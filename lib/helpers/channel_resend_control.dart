import 'dart:async';

/// Одна серия повторов. Отмена будит ожидание, а отменённая серия не может
/// ожить после позднего ACK или удалить состояние следующей серии сообщения.
class ChannelResendControl {
  ChannelResendControl({required this.minHops});

  final int minHops;
  DateTime? lastAttemptAt;
  bool get cancelled => _cancelled;
  bool _cancelled = false;
  Completer<void>? _wakeup;

  Future<void> wait(Duration delay) async {
    if (_cancelled || delay <= Duration.zero) { return; }
    final wakeup = Completer<void>();
    _wakeup = wakeup;
    final timer = Timer(delay, () {
      if (!wakeup.isCompleted) { wakeup.complete(); }
    });
    try {
      await wakeup.future;
    } finally {
      timer.cancel();
      if (identical(_wakeup, wakeup)) { _wakeup = null; }
    }
  }

  void wake() {
    final wakeup = _wakeup;
    if (wakeup != null && !wakeup.isCompleted) { wakeup.complete(); }
  }

  void cancel() {
    _cancelled = true;
    wake();
  }
}
