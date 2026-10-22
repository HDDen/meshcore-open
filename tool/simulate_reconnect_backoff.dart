import 'dart:io';

import 'package:meshcore_open/helpers/reconnect_backoff.dart';

// Снимок _nextReconnectDelayMs: индекс до увеличения счётчика.
// Соответствие реальному connector проверяет reconnect_power_baseline_test.
int legacyReconnectDelayMs(int attemptIndex) {
  final attempt = attemptIndex < 6 ? attemptIndex : 6;
  final delayMs = 1000 * (1 << attempt);
  return delayMs > 30000 ? 30000 : delayMs;
}

// Рабочая функция политики; legacy-снимок и корпус сценариев сохранены.
int proposedReconnectDelayMs(
  int attemptIndex, {
  required bool background,
  required int backgroundIntervalSeconds,
}) {
  return reconnectDelayMs(attemptIndex, background: background,
      backgroundIntervalSeconds: backgroundIntervalSeconds);
}

int _countAttemptStarts({
  required int windowSeconds,
  required int connectDurationSeconds,
  required int Function(int) delayMs,
}) {
  var nowMs = 0;
  var count = 0;
  while (true) {
    final nextStartMs = nowMs + delayMs(count);
    if (nextStartMs > windowSeconds * 1000) {
      return count;
    }
    count++;
    nowMs = nextStartMs + connectDurationSeconds * 1000;
  }
}

void main(List<String> args) {
  final windowSeconds = args.isEmpty ? 3600 : int.parse(args.single);
  if (windowSeconds <= 0) {
    throw ArgumentError('Окно моделирования должно быть положительным.');
  }
  stdout.writeln('Синтетическая модель числа стартов reconnect, окно=$windowSeconds с.');
  stdout.writeln('proposed использует рабочую функцию reconnectDelayMs; legacy — прежний снимок.');
  stdout.writeln('Длительность попытки 0/15 с — условные входные данные, не замер BLE/TCP.');
  stdout.writeln('Состояние экрана постоянно внутри сценария; первая серия пауз 1/2/4/8/16/30 с.');
  stdout.writeln('Редкая пауза только в фоне, начиная с седьмого планирования.');
  stdout.writeln('Это не ОС/Doze, не autoConnect, не handshake, не расход батареи и не время восстановления реальной ноды.');
  for (final connectSeconds in [0, 15]) {
    final legacy = _countAttemptStarts(
      windowSeconds: windowSeconds, connectDurationSeconds: connectSeconds,
      delayMs: legacyReconnectDelayMs,
    );
    for (final background in [false, true]) {
      for (final interval in [30, 60, 180, 600]) {
        final proposed = _countAttemptStarts(
          windowSeconds: windowSeconds, connectDurationSeconds: connectSeconds,
          delayMs: (attempt) => proposedReconnectDelayMs(attempt,
              background: background, backgroundIntervalSeconds: interval),
        );
        if ((!background || interval == 30) && proposed != legacy) {
          throw StateError('Исходное расписание не совпало.');
        }
        if (proposed > legacy) {
          throw StateError('Редкое расписание увеличило число попыток.');
        }
        stdout.writeln('background=$background, pause=$interval s, connectDuration=$connectSeconds s: '
            'legacy starts=$legacy; proposed starts=$proposed');
      }
    }
  }
}
