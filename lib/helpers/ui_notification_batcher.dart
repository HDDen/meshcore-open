import 'dart:async';

/// Окно от первого события; поток событий не переносит уведомление бесконечно.
class UiNotificationBatcher {
  UiNotificationBatcher({required this.onNotify});

  static const minimum = Duration(milliseconds: 50);
  final void Function() onNotify;
  Duration _interval = minimum;
  Timer? _timer;
  Timer? _priorityTimer;
  bool _disposed = false;

  void setInterval(Duration value) {
    if (_disposed || value == _interval) return;
    assert(value >= minimum);
    final previous = _interval;
    _interval = value;
    if (value < previous && _timer != null) {
      // Уже накопленное выдаём следующим событием, не начиная новое ожидание.
      _cancelTimers();
      _timer = Timer(Duration.zero, _flush);
    }
  }

  void mark({bool priority = false}) {
    if (_disposed) return;
    _timer ??= Timer(_interval, _flush);
    if (priority && _interval > minimum) {
      // Оба одноразовых таймера сохраняются: выигрывает ближайший срок.
      _priorityTimer ??= Timer(minimum, _flush);
    }
  }

  void _flush() {
    if (_disposed) return;
    _cancelTimers();
    // Listener может снова вызвать mark: это уже следующее окно.
    onNotify();
  }

  void _cancelTimers() {
    _timer?.cancel();
    _priorityTimer?.cancel();
    _timer = null;
    _priorityTimer = null;
  }

  void dispose() {
    _disposed = true;
    _cancelTimers();
  }
}
