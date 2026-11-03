import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/saved_path_trace_result.dart';

void main() {
  final tag = Uint8List.fromList([1, 2, 3, 4]);
  for (final width in [1, 2, 4]) {
    test('cached TRACE requires full matching tag, route, flags and SNRs ($width)', () {
      final route = Uint8List.fromList(List<int>.generate(width * 2, (i) => i + 16));
      final frame = Uint8List.fromList([
        pushCodeTraceData, 0, route.length, width == 1 ? 0 : width == 2 ? 1 : 2,
        ...tag, 0, 0, 0, 0, ...route, 12, 16, 20,
      ]);
      bool matches(Uint8List value) => SavedPathTraceResult.matchesRequest(
        value, tag: tag, route: route, hashWidth: width,
      );
      expect(matches(frame), isTrue);
      final wrongTag = Uint8List.fromList(frame)..[4] = 99;
      final wrongRoute = Uint8List.fromList(frame)..[12] = 99;
      final wrongWidth = Uint8List.fromList(frame)..[3] = 3;
      expect(matches(wrongTag), isFalse);
      expect(matches(wrongRoute), isFalse);
      expect(matches(wrongWidth), isFalse);
      expect(matches(Uint8List.fromList(frame.sublist(0, frame.length - 1))), isFalse);
      expect(matches(Uint8List(0)), isFalse);
      final result = SavedPathTraceResult(frame: frame);
      frame[4] = 88;
      expect(result.frame[4], tag[0]);
      expect(() => result.observations.addAll([]), throwsUnsupportedError);
    });
  }
}
