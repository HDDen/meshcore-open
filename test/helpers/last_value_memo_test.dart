import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/last_value_memo.dart';

void main() {
  test('the same key hands back the last value without computing', () {
    final memo = LastValueMemo<int, String>();
    var computed = 0;
    String compute() => 'value ${++computed}';

    expect(memo.of(1, compute), 'value 1');
    expect(memo.of(1, compute), 'value 1');
    expect(computed, 1);
    expect(memo.hasValue, isTrue);
  });

  test('a different key computes anew and forgets the last one', () {
    final memo = LastValueMemo<int, String>();
    var computed = 0;
    String compute() => 'value ${++computed}';

    memo.of(1, compute);
    expect(memo.of(2, compute), 'value 2');
    expect(memo.of(1, compute), 'value 3');
    expect(computed, 3);
  });

  test('a list in the key counts by identity, as the samples list does', () {
    final memo = LastValueMemo<(List<int>, int), int>();
    final samples = [1, 2, 3];
    var computed = 0;
    int compute() => ++computed;

    memo.of((samples, 7), compute);
    memo.of((samples, 7), compute);
    expect(computed, 1, reason: 'the same list and the same precision');

    memo.of(([1, 2, 3], 7), compute);
    expect(computed, 2, reason: 'an equal list is a new list');

    memo.of(([1, 2, 3], 7), compute);
    expect(computed, 3, reason: 'and so is the next one');

    final again = [1, 2, 3];
    memo.of((again, 7), compute);
    memo.of((again, 8), compute);
    expect(computed, 5, reason: 'the precision is part of the key');
  });

  test('a cleared memo computes at the next ask', () {
    final memo = LastValueMemo<int, int>();
    var computed = 0;
    memo.of(1, () => ++computed);

    memo.clear();

    expect(memo.hasValue, isFalse);
    expect(memo.of(1, () => ++computed), 2);
  });
}
