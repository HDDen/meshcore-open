import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/cli_history_writes.dart';

// Изолированные очереди microtasks воспроизводят границу тестовых FakeAsync
// зон без native I/O, ожиданий по времени и дополнительных зависимостей.
class _Microtasks {
  final _callbacks = <void Function()>[];

  void run(void Function() operation) => runZoned(operation,
    zoneSpecification: ZoneSpecification(scheduleMicrotask: (self, parent, zone, callback) {
      _callbacks.add(() => zone.run(callback));
    }));

  void flush() {
    var count = 0;
    while (_callbacks.isNotEmpty) {
      if (++count > 1000) {
        fail('Microtask queue did not settle');
      }
      _callbacks.removeAt(0)();
    }
  }

  bool get isEmpty => _callbacks.isEmpty;
}

void main() {
  for (final failFirst in [false, true]) {
    test('an idle CLI queue leaves its former zone after success/failure=$failFirst', () {
      final first = _Microtasks();
      final second = _Microtasks();
      var firstDone = false;
      var firstFailed = false;
      var secondDone = false;
      first.run(() {
        unawaited(CliHistoryWrites.ordered<void>(() async {
          if (failFirst) {
            throw StateError('Synthetic first-zone failure');
          }
        }).then<void>((_) { firstDone = true; }, onError: (Object error, StackTrace stack) {
          firstFailed = true;
          firstDone = true;
        }));
      });
      first.flush();
      expect(firstDone, isTrue);
      expect(firstFailed, failFirst);

      // Больше не обслуживаем первую зону, как после завершения widget test.
      second.run(() {
        unawaited(CliHistoryWrites.ordered<void>(() async {}).then<void>((_) { secondDone = true; }));
      });
      second.flush();
      expect(secondDone, isTrue);
      expect(first.isEmpty, isTrue);
      expect(second.isEmpty, isTrue);
    });
  }
}
