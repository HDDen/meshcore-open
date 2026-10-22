import 'dart:async';

/// Индекс считается до увеличения счётчика; первые шесть пауз неизменны.
int reconnectDelayMs(
  int attemptIndex, {
  bool background = false,
  int backgroundIntervalSeconds = 30,
}) {
  if (background && attemptIndex >= 6) {
    return backgroundIntervalSeconds * 1000;
  }
  final attempt = attemptIndex < 6 ? attemptIndex : 6;
  final delayMs = 1000 * (1 << attempt);
  return delayMs > 30000 ? 30000 : delayMs;
}

/// Пересчёт паузы сохраняет прошедшее время и не расходует новую попытку.
class ReconnectWait {
  ReconnectWait({
    required this.attemptIndex,
    required Duration delay,
    required void Function() onElapsed,
    Duration Function()? now,
  }) : _delay = delay, _onElapsed = onElapsed {
    final stopwatch = Stopwatch()..start();
    _now = now ?? (() => stopwatch.elapsed);
    _startedAt = _now();
    _arm(delay);
  }

  final int attemptIndex;
  final void Function() _onElapsed;
  late final Duration Function() _now;
  late final Duration _startedAt;
  Duration _delay;
  Timer? _timer;
  bool _cancelled = false;

  bool get isActive => _timer?.isActive ?? false;

  void updateDelay(Duration delay) {
    if (_cancelled || !isActive || delay == _delay) {
      return;
    }
    _delay = delay;
    _timer?.cancel();
    final remaining = delay - (_now() - _startedAt);
    // Даже просроченная пауза завершается асинхронно, без reentrant connect.
    _arm(remaining.isNegative ? Duration.zero : remaining);
  }

  void _arm(Duration delay) {
    _timer = Timer(delay, _onElapsed);
  }

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
  }
}
