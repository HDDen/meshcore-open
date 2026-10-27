import 'package:flutter_test/flutter_test.dart';

import 'package:meshcore_open/helpers/delivery_observation_write_plan.dart';

List<String> _apply(List<String> previous, DeliveryObservationWritePlan plan) => [
  ...previous.skip(plan.removePrefixCount),
  ...plan.append,
];

List<List<String>> _smallLists() {
  final result = <List<String>>[[]];
  for (var length = 1; length <= 4; length++) {
    for (var bits = 0; bits < (1 << length); bits++) {
      result.add(List.generate(length, (i) => (bits & (1 << i)) == 0 ? 'A' : 'B'));
    }
  }
  return result;
}

void main() {
  test('unchanged data needs no changes, append keeps the old records', () {
    final unchanged = planDeliveryObservationWrite(['A', 'B'], ['A', 'B']);
    expect(unchanged.removePrefixCount, 0);
    expect(unchanged.append, isEmpty);
    expect(unchanged.changedRows, 0);

    final append = planDeliveryObservationWrite(['A', 'B'], ['A', 'B', 'C']);
    expect(append.removePrefixCount, 0);
    expect(append.append, ['C']);
    expect(_apply(['A', 'B'], append), ['A', 'B', 'C']);
  });

  test('sliding window removes only the expired prefix and adds its new tail', () {
    final plan = planDeliveryObservationWrite(['A', 'B', 'C'], ['B', 'C', 'D']);
    expect(plan.removePrefixCount, 1);
    expect(plan.append, ['D']);
    expect(plan.changedRows, 2);
    expect(_apply(['A', 'B', 'C'], plan), ['B', 'C', 'D']);
  });

  test('empty inputs, clearing, replacements and reordering keep exact values', () {
    for (final (previous, next) in <(List<String>, List<String>)>[
      ([], []),
      ([], ['A']),
      (['A'], []),
      (['A', 'B'], ['X', 'Y']),
      (['A', 'B'], ['B', 'A']),
      (['A', 'B', 'C'], ['A', 'X', 'C']),
      (['A', 'A', 'B'], ['A', 'B', 'A']),
      (['A', 'A'], ['A', 'A', 'A']),
    ]) {
      final plan = planDeliveryObservationWrite(previous, next);
      expect(_apply(previous, plan), next);
    }
  });

  test('all pairs of short duplicate-rich lists reconstruct exactly', () {
    final corpus = _smallLists();
    for (final previous in corpus) {
      for (final next in corpus) {
        final before = List<String>.of(previous);
        final after = List<String>.of(next);
        final plan = planDeliveryObservationWrite(previous, next);
        expect(plan.removePrefixCount, inInclusiveRange(0, previous.length));
        expect(_apply(previous, plan), next, reason: '$previous -> $next');
        expect(plan.changedRows, lessThanOrEqualTo(previous.length + next.length));
        expect(previous, before);
        expect(next, after);
      }
    }
  });

  test('the plan owns its append list and preserves opaque JSON', () {
    final next = ['{"value":"А"}', '{"value":"A"}', '{"value":"A"}'];
    final plan = planDeliveryObservationWrite([], next);
    next.clear();
    expect(plan.append, ['{"value":"А"}', '{"value":"A"}', '{"value":"A"}']);
    expect(() => plan.append.add('other'), throwsUnsupportedError);
  });
}
