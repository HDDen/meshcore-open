import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore_open/helpers/direct_progress_rx_parser.dart';

// Снимок DirectMessageEcho.tryParse и используемых операций BufferReader.
// Оригиналы зависят от Flutter. Соответствие снимка оригиналу проверяется
// test/services/rx_progress_power_baseline_test.dart на неизменном корпусе.
// Это цена parser/guard, не MessageRetryService целиком и не замер батареи.
// Неиспользуемый здесь rewind/lastPointer не воспроизведён; время приблизительное.
class LegacyRxProgressEcho {
  const LegacyRxProgressEcho({
    required this.destinationHash,
    required this.sourceHash,
    required this.pathHashWidth,
    required this.remainingHopCount,
    required this.remainingPath,
    required this.payload,
  });

  final int destinationHash;
  final int sourceHash;
  final int pathHashWidth;
  final int remainingHopCount;
  final Uint8List remainingPath;
  final Uint8List payload;
}

class _LegacyReader {
  _LegacyReader(Uint8List data) : _buffer = Uint8List.fromList(data);
  final Uint8List _buffer;
  int _pointer = 0;

  int get remaining => _buffer.length - _pointer;
  int readByte() => readBytes(1)[0];

  Uint8List readBytes(int count) {
    if (_pointer + count > _buffer.length) {
      throw RangeError(
        'Attempted to read $count bytes at offset $_pointer, but only $remaining bytes remaining in buffer of length ${_buffer.length}',
      );
    }
    final data = _buffer.sublist(_pointer, _pointer + count);
    _pointer += count;
    return data;
  }

  void skipBytes(int count) {
    if (_pointer + count > _buffer.length) {
      throw RangeError(
        'Attempted to skip $count bytes at offset $_pointer, but only $remaining bytes remaining in buffer of length ${_buffer.length}',
      );
    }
    _pointer += count;
  }

  Uint8List readRemainingBytes() => readBytes(remaining);
}

LegacyRxProgressEcho? parseLegacyRxProgressEcho(Uint8List frame) {
  try {
    final reader = _LegacyReader(frame);
    if (reader.readByte() != 0x88 || reader.remaining < 4) {
      return null;
    }
    reader.skipBytes(2);
    final header = reader.readByte();
    final routeType = header & 0x03;
    final payloadType = (header >> 2) & 0x0F;
    if ((routeType != 0x02 && routeType != 0x03) || payloadType != 0x02) {
      return null;
    }
    if (routeType == 0x03) {
      if (reader.remaining < 4) {
        return null;
      }
      reader.skipBytes(4);
    }
    final encodedPathLength = reader.readByte();
    final pathHashWidth = ((encodedPathLength >> 6) & 0x03) + 1;
    final remainingHopCount = encodedPathLength & 0x3F;
    final remainingPathBytes = remainingHopCount * pathHashWidth;
    if (reader.remaining < remainingPathBytes + 2) {
      return null;
    }
    final remainingPath = reader.readBytes(remainingPathBytes);
    final payload = reader.readRemainingBytes();
    return LegacyRxProgressEcho(
      destinationHash: payload[0],
      sourceHash: payload[1],
      pathHashWidth: pathHashWidth,
      remainingHopCount: remainingHopCount,
      remainingPath: Uint8List.fromList(remainingPath),
      payload: Uint8List.fromList(payload),
    );
  } on RangeError {
    return null;
  }
}

List<({String name, Uint8List frame})> rxProgressBenchmarkCorpus() {
  Uint8List direct(int width, {bool scoped = false}) => Uint8List.fromList([
    0x88, 32, 186, scoped ? 0x0b : 0x0a,
    if (scoped) ...[0x12, 0x34, 0x56, 0x78],
    ((width - 1) << 6) | 1,
    ...List<int>.generate(width, (i) => 0x21 + i),
    0xaa, 0x11,
    ...List<int>.generate(32, (i) => (i * 7 + width) & 255),
  ]);

  return [
    for (final width in [1, 2, 3, 4])
      (name: 'direct-width-$width', frame: direct(width)),
    (name: 'scoped-direct', frame: direct(2, scoped: true)),
    (name: 'direct-no-hops', frame: Uint8List.fromList([0x88, 32, 186, 0x0a, 0, 0xaa, 0x11])),
    (name: 'flood-text', frame: Uint8List.fromList([0x88, 32, 186, 0x09, 0, 0xaa, 0x11])),
    (name: 'channel-text', frame: Uint8List.fromList([0x88, 32, 186, 0x15, 0, 0xaa, 0x11])),
    (name: 'wrong-push', frame: Uint8List.fromList([0x80, 32, 186, 0x0a, 0, 0xaa, 0x11])),
    (name: 'empty', frame: Uint8List(0)),
    (name: 'short-header', frame: Uint8List.fromList([0x88, 32, 186, 0x0a])),
    (name: 'truncated-scope', frame: Uint8List.fromList([0x88, 32, 186, 0x0b, 1, 2])),
    (name: 'truncated-path', frame: Uint8List.fromList([0x88, 32, 186, 0x0a, 0x42, 0x21, 0xaa, 0x11])),
    (name: 'short-payload', frame: Uint8List.fromList([0x88, 32, 186, 0x0a, 0, 0xaa])),
  ];
}

enum _Mode { legacy, guarded }
enum _Scenario { idle, active, alternating }

bool _hasTrackers(_Scenario scenario, int index) => switch (scenario) {
  _Scenario.idle => false,
  _Scenario.active => true,
  _Scenario.alternating => (index ~/ 32).isOdd,
};

({List<LegacyRxProgressEcho?> values, int parses, int micros}) _run(
  _Mode mode,
  _Scenario scenario,
  List<({String name, Uint8List frame})> corpus,
  int count,
) {
  final values = List<LegacyRxProgressEcho?>.filled(count, null);
  var parses = 0;
  LegacyRxProgressEcho? parseFrame(Uint8List frame) {
    parses++;
    return parseLegacyRxProgressEcho(frame);
  }
  final guarded = DirectProgressRxParser(parseFrame)..setEnabled(true);
  final watch = Stopwatch()..start();
  for (var i = 0; i < count; i++) {
    final frame = corpus[i % corpus.length].frame;
    final hasTrackers = _hasTrackers(scenario, i);
    // Корпус и границы таймера сохранены; guard теперь из рабочего helper.
    LegacyRxProgressEcho? echo;
    if (mode == _Mode.legacy) {
      parses++;
      echo = parseLegacyRxProgressEcho(frame);
    } else {
      echo = guarded.parse(frame, hasTrackers: hasTrackers);
    }
    if (echo == null || !hasTrackers) {
      continue;
    }
    values[i] = echo;
  }
  watch.stop();
  return (values: values, parses: parses, micros: watch.elapsedMicroseconds);
}

bool _sameBytes(Uint8List a, Uint8List b) {
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

void _check(
  List<LegacyRxProgressEcho?> legacy,
  List<LegacyRxProgressEcho?> guarded,
) {
  for (var i = 0; i < legacy.length; i++) {
    final a = legacy[i];
    final b = guarded[i];
    if (a == null && b == null) {
      continue;
    }
    if (a == null || b == null ||
        a.destinationHash != b.destinationHash || a.sourceHash != b.sourceHash ||
        a.pathHashWidth != b.pathHashWidth || a.remainingHopCount != b.remainingHopCount ||
        !_sameBytes(a.remainingPath, b.remainingPath) || !_sameBytes(a.payload, b.payload)) {
      throw StateError('Разные результаты при index=$i');
    }
  }
}

void main(List<String> args) {
  final count = args.isEmpty ? 100000 : int.parse(args.single);
  final corpus = rxProgressBenchmarkCorpus();
  if (count < corpus.length) {
    throw ArgumentError('Число обращений должно быть не меньше ${corpus.length}.');
  }
  stdout.writeln('Синтетический микробенч guard/parser прогресса direct-доставки.');
  stdout.writeln('lookups=$count; corpus=${corpus.length} синтетических кадров; alternating — блоки по 32.');
  stdout.writeln('Измеряется рабочий guard со снимком парсера, не весь сервис: Flutter-зависимости исключены.');
  stdout.writeln('Это не полный RX, сопоставление трекеров, AES, БД, сеть, Flutter или замер энергии.');
  for (final scenario in _Scenario.values) {
    for (final mode in _Mode.values) {
      _run(mode, scenario, corpus, 1024);
    }
    final legacy = _run(_Mode.legacy, scenario, corpus, count);
    final guarded = _run(_Mode.guarded, scenario, corpus, count);
    _check(legacy.values, guarded.values);
    var expectedParses = 0;
    for (var i = 0; i < count; i++) {
      if (_hasTrackers(scenario, i)) {
        expectedParses++;
      }
    }
    if (legacy.parses != count || guarded.parses != expectedParses) {
      throw StateError('Неверные счётчики parser для ${scenario.name}');
    }
    stdout.writeln('scenario=${scenario.name}: legacy elapsedUs=${legacy.micros}, parses=${legacy.parses}; '
        'guarded elapsedUs=${guarded.micros}, parses=${guarded.parses}; values=equal');
  }
}
