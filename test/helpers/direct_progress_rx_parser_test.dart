import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/direct_progress_rx_parser.dart';

void main() {
  test('Off parses every frame; On skips the callback only without trackers', () {
    var calls = 0;
    final frame = Uint8List.fromList([1, 2, 3]);
    final parser = DirectProgressRxParser<int>((input) {
      expect(identical(input, frame), isTrue);
      calls++;
      return 42;
    });
    expect(parser.parse(frame, hasTrackers: false), 42);
    expect(parser.parse(frame, hasTrackers: true), 42);
    expect(calls, 2);
    parser.setEnabled(true);
    expect(parser.parse(frame, hasTrackers: false), isNull);
    expect(calls, 2);
    expect(parser.parse(frame, hasTrackers: true), 42);
    expect(calls, 3);
    parser.setEnabled(true);
    expect(parser.parse(frame, hasTrackers: false), isNull);
    parser.setEnabled(false);
    expect(parser.parse(frame, hasTrackers: false), 42);
    expect(calls, 4);
    expect(frame, orderedEquals([1, 2, 3]));
  });

  test('skipping does not invoke a throwing parser; active and Off preserve its error', () {
    final frame = Uint8List(0);
    final parser = DirectProgressRxParser<int>((_) => throw StateError('synthetic'));
    expect(() => parser.parse(frame, hasTrackers: false), throwsStateError);
    parser.setEnabled(true);
    expect(parser.parse(frame, hasTrackers: false), isNull);
    expect(() => parser.parse(frame, hasTrackers: true), throwsStateError);
  });
}
