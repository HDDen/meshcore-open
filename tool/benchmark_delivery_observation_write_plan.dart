import 'dart:convert';
import 'dart:io';

import 'package:meshcore_open/helpers/delivery_observation_write_plan.dart';

enum _Scenario { unchanged, append, slidingWindow, replaceAll, duplicates }

typedef _Input = ({List<String> previous, List<String> next});

List<_Input> _corpus(_Scenario scenario, int length, int count) {
  String value(int index) => jsonEncode({
    'contact_key': 'synthetic',
    'delivery_ms': 200 + index,
    'timestamp': index,
  });
  final strings = List.generate(count + length + 1, value);
  return List.generate(count, (i) {
    final base = strings.sublist(i, i + length);
    return switch (scenario) {
      _Scenario.unchanged => (previous: base, next: List<String>.of(base)),
      _Scenario.append =>
        (previous: base.sublist(0, length - 1), next: List<String>.of(base)),
      _Scenario.slidingWindow =>
        (previous: base, next: strings.sublist(i + 1, i + length + 1)),
      _Scenario.replaceAll =>
        (previous: base, next: [for (final text in base) jsonEncode({'changed': text})]),
      _Scenario.duplicates => (
        previous: List.generate(length, (j) => strings[j % 2]),
        next: List.generate(length, (j) => strings[(j + 1) % 2]),
      ),
    };
  });
}

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

({int micros, int rows}) _run(List<_Input> corpus, {required bool prototype}) {
  final plans = List<DeliveryObservationWritePlan?>.filled(corpus.length, null);
  var rows = 0;
  final watch = Stopwatch()..start();
  for (var i = 0; i < corpus.length; i++) {
    final input = corpus[i];
    // legacy моделирует DELETE всех строк + INSERT каждой новой строки.
    final plan = prototype
        ? planDeliveryObservationWrite(input.previous, input.next)
        : DeliveryObservationWritePlan(
            removePrefixCount: input.previous.length,
            append: List<String>.of(input.next),
          );
    plans[i] = plan;
    rows += plan.changedRows;
  }
  watch.stop();
  // Проверка всех снимков за пределами таймера, не только последнего.
  for (var i = 0; i < corpus.length; i++) {
    final input = corpus[i];
    final plan = plans[i]!;
    final result = [
      ...input.previous.skip(plan.removePrefixCount),
      ...plan.append,
    ];
    if (!_same(result, input.next)) {
      throw StateError('Snapshot mismatch at $i, prototype=$prototype');
    }
  }
  return (micros: watch.elapsedMicroseconds, rows: rows);
}

void main() {
  const count = 5000;
  stdout.writeln('Синтетическая модель плана записи delivery observations.');
  stdout.writeln('plans=$count; размеры списка 16/100; данные синтетические.');
  stdout.writeln('100 — текущий лимит статистики приложения, не лимит сообщений ноды.');
  stdout.writeln('legacy — модель DELETE+INSERT; prototype использует рабочий planner, не SQL-путь.');
  stdout.writeln('elapsedUs — только план в памяти; changedRows — расчёт модели.');
  stdout.writeln('Это не SQLite, SELECT, transaction/commit, fsync, диск, весь RX или энергия.');
  for (final length in [16, 100]) {
    for (final scenario in _Scenario.values) {
      final corpus = _corpus(scenario, length, count);
      final warmup = corpus.take(32).toList();
      _run(warmup, prototype: false);
      _run(warmup, prototype: true);
      final legacy = _run(corpus, prototype: false);
      final prototype = _run(corpus, prototype: true);
      stdout.writeln('scenario=${scenario.name}, size=$length: '
          'legacy elapsedUs=${legacy.micros}, changedRows=${legacy.rows}; '
          'prototype elapsedUs=${prototype.micros}, changedRows=${prototype.rows}; '
          'allSnapshots=equal');
    }
  }
}
