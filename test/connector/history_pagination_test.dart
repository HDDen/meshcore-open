import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/history_page_loads.dart';

void main() {
  test('concurrent cursor requests read and apply one page', () async {
    final loads = HistoryPageLoads<int>();
    final gate = Completer<List<int>>();
    var reads = 0;
    var applies = 0;
    Future<List<int>> request() => loads.load(
      key: ('node', 'chat', 'before', 3), current: () => true,
      read: () { reads++; return gate.future; },
      apply: (_) => applies++,
    );
    final first = request();
    final second = request();
    expect(reads, 1);
    gate.complete([1, 2]);
    expect(await first, [1, 2]);
    expect(await second, [1, 2]);
    expect(applies, 1);
  });

  test('arrivals while reading remain in the live conversation', () async {
    final loads = HistoryPageLoads<int>();
    final gate = Completer<List<int>>();
    var window = [3];
    final pending = loads.load(
      key: 'before-3', current: () => window.first == 3,
      read: () => gate.future,
      apply: (page) => window = [...page, ...window],
    );
    window = [...window, 4];
    gate.complete([1, 2]);
    await pending;
    expect(window, [1, 2, 3, 4]);
  });

  for (final reason in ['radio switch', 'history clear', 'channel replacement', 'dispose']) {
    test('$reason discards an in-flight page', () async {
      final loads = HistoryPageLoads<int>();
      final gate = Completer<List<int>>();
      var current = true;
      var applied = false;
      final pending = loads.load(
        key: 'old-history', current: () => current,
        read: () => gate.future, apply: (_) => applied = true,
      );
      current = false;
      gate.complete([1]);
      expect(await pending, isEmpty);
      expect(applied, isFalse);
    });
  }

  test('a failed page can be retried and does not block another history', () async {
    final loads = HistoryPageLoads<int>();
    await expectLater(loads.load(
      key: 'a', current: () => true,
      read: () => Future<List<int>>.error(StateError('read failed')),
      apply: (_) {},
    ), throwsStateError);
    Future<List<int>> request(String key, int value) => loads.load(
      key: key, current: () => true,
      read: () async => [value], apply: (_) {},
    );
    expect(await request('a', 1), [1]);
    expect(await request('b', 2), [2]);
  });
}
