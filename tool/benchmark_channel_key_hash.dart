import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meshcore_open/helpers/channel_key_hash_cache.dart';

// Синтетический микробенч, не приложение и не измерение батареи.
// Формула legacy соответствует _computeChannelHash коннектора: SHA256(psk)[0].
// Импортировать коннектор нельзя в чистом Dart: он зависит от Flutter.
// Корпус и границы таймера сохранены; теперь измеряется рабочий helper.
enum _Mode { legacy, snapshotCache }
enum _Scenario { stable, mutateInPlace, replaceObjects }

({Uint8List values, int calculations, int micros}) _run(
  _Mode mode,
  _Scenario scenario,
  int channels,
  int count,
) {
  // Создание одинакового корпуса и буфера результатов — вне таймера.
  final keys = List<Uint8List>.generate(channels, (channel) =>
      Uint8List.fromList(List<int>.generate(16, (i) => (channel * 17 + i * 7) & 255)));
  final values = Uint8List(count);
  var calculations = 0;
  int compute(Uint8List key) {
    calculations++;
    return crypto.sha256.convert(key).bytes[0];
  }
  final cache = ChannelKeyHashCache(compute: compute)..setEnabled(true);
  final watch = Stopwatch()..start();
  for (var i = 0; i < count; i++) {
    if (scenario == _Scenario.mutateInPlace && i % 256 == 0) {
      // Меняем исходные байты через alias, сохраняя identity самого PSK.
      final alias = Uint8List.sublistView(keys[(i ~/ 256) % channels]);
      alias[0] ^= 0x80;
    }
    final key = keys[i % channels];
    final input = scenario == _Scenario.replaceObjects
        ? Uint8List.fromList(key) : key;
    values[i] = mode == _Mode.legacy ? compute(input) : cache.hash(input);
  }
  watch.stop();
  return (values: values, calculations: calculations, micros: watch.elapsedMicroseconds);
}

void _check(
  ({Uint8List values, int calculations, int micros}) legacy,
  ({Uint8List values, int calculations, int micros}) cached,
  _Scenario scenario,
  int channels,
  int count,
) {
  // Проверка каждого результата вне таймера; checksum для этого недостаточен.
  for (var i = 0; i < count; i++) {
    if (legacy.values[i] != cached.values[i]) {
      throw StateError('Разные результаты: scenario=${scenario.name}, channels=$channels, index=$i');
    }
  }
  if (legacy.calculations != count) {
    throw StateError('Неверный счётчик legacy.');
  }
  if (scenario == _Scenario.stable && cached.calculations != channels) {
    throw StateError('Стабильный корпус вычислялся повторно.');
  }
  if (scenario == _Scenario.replaceObjects && cached.calculations != count) {
    throw StateError('Замена объектов должна давать cache miss.');
  }
  if (scenario == _Scenario.mutateInPlace &&
      (cached.calculations < channels || cached.calculations > channels + (count + 255) ~/ 256)) {
    throw StateError('Неверный счётчик после изменения ключей.');
  }
}

void main(List<String> args) {
  final count = args.isEmpty ? 100000 : int.parse(args.single);
  if (count < 32) {
    throw ArgumentError('Число обращений должно быть не меньше 32.');
  }
  stdout.writeln('Синтетический микробенч SHA256(psk)[0] и рабочего snapshot-cache.');
  stdout.writeln('lookups=$count; PSK=16 синтетических байт; мутация раз в 256 обращений.');
  stdout.writeln('1/8/32 — размеры корпуса, не заявленный предел каналов устройства.');
  stdout.writeln('Это не весь RX, AES, БД, сеть, Flutter или замер энергии.');
  for (final channels in [1, 8, 32]) {
    for (final scenario in _Scenario.values) {
      for (final mode in _Mode.values) {
        _run(mode, scenario, channels, 1024);
      }
      final legacy = _run(_Mode.legacy, scenario, channels, count);
      final cached = _run(_Mode.snapshotCache, scenario, channels, count);
      _check(legacy, cached, scenario, channels, count);
      stdout.writeln('scenario=${scenario.name}, channels=$channels: '
          'legacy elapsedUs=${legacy.micros}, SHA=${legacy.calculations}; '
          'snapshotCache elapsedUs=${cached.micros}, SHA=${cached.calculations}; values=equal');
    }
  }
}
