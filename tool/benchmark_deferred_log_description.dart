import 'dart:io';

import 'package:meshcore_open/helpers/deferred_log_description.dart';

// Микробенч политики строк на одном синтетическом корпусе, без Flutter/транспорта.
// Не измеряет весь formatter сервиса, батарею, native logs или реальные RX.
// Держит заданный корпус целиком, а не моделирует кольцевой буфер на 500 записей.
const _corpus = <(String, String, int?, String)>[
  ('RX RESP_CODE_BATT_AND_STORAGE', ' • ', 4200, 'mV'),
  ('RX PUSH_CODE_LOG_RX_DATA', '', null, ''),
  ('TX CMD_SIGN_DATA', ' • chunk=', 3, 'B'),
  ('RX RESP_CODE_SENT', ' • timeout=', 3210, 'ms'),
];

String _format(int index) {
  final row = _corpus[index % _corpus.length];
  return row.$3 == null ? row.$1 : '${row.$1}${row.$2}${row.$3}${row.$4}';
}

enum _Mode { original, eager, deferred }

({int builds, int checksum, int micros}) _run(_Mode mode, int reads, int count) {
  var builds = 0;
  var checksum = 0;
  final watch = Stopwatch()..start();
  final originals = <String>[];
  final cached = <DeferredLogDescription>[];
  for (var i = 0; i < count; i++) {
    if (mode == _Mode.original) {
      builds++;
      originals.add(_format(i));
    } else if (mode == _Mode.eager) {
      builds++;
      cached.add(DeferredLogDescription.eager(_format(i)));
    } else {
      final index = i;
      cached.add(DeferredLogDescription.lazy(() {
        builds++;
        return _format(index);
      }));
    }
  }
  for (var i = 0; i < count; i++) {
    if (i % 100 >= reads) continue;
    // Два чтения одной записи позволяют проверить повторное использование строки.
    for (var read = 0; read < 2; read++) {
      final value = mode == _Mode.original ? originals[i] : cached[i].value;
      checksum += value.length;
    }
  }
  watch.stop();
  return (builds: builds, checksum: checksum, micros: watch.elapsedMicroseconds);
}

void main(List<String> args) {
  final count = args.isEmpty ? 100000 : int.parse(args.single);
  if (count <= 0 || count % 100 != 0) {
    throw ArgumentError('Число записей должно быть положительным и кратным 100.');
  }
  stdout.writeln('Синтетический микробенч политики строк; это не замер приложения/энергии.');
  stdout.writeln('records=$count; repeated reads per viewed entry=2');
  for (final reads in [0, 10, 100]) {
    // Одинаковый прогрев для всех вариантов, результаты прогрева не выводятся.
    for (final mode in _Mode.values) {
      _run(mode, reads, 1000);
    }
    int? expectedChecksum;
    for (final mode in _Mode.values) {
      final result = _run(mode, reads, count);
      expectedChecksum ??= result.checksum;
      final expectedBuilds = mode == _Mode.deferred ? count ~/ 100 * reads : count;
      if (result.checksum != expectedChecksum || result.builds != expectedBuilds) {
        throw StateError('Результаты/число форматирований расходятся для ${mode.name}.');
      }
      stdout.writeln('mode=${mode.name} viewed=$reads% builds=${result.builds} '
          'elapsedUs=${result.micros} checksum=${result.checksum}');
    }
  }
}
