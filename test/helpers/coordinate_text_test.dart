import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/coordinate_text.dart';

CoordinateSegment? _firstCoordinate(String text) {
  for (final segment in CoordinateText.split(text)) {
    if (segment.isCoordinate) return segment;
  }
  return null;
}

void main() {
  group('CoordinateText', () {
    test('finds a pair written inside a sentence', () {
      final found = _firstCoordinate('Я здесь 45.0,38.9 всем привет');
      expect(found, isNotNull);
      expect(found!.latitude, 45.0);
      expect(found.longitude, 38.9);
      expect(found.text, '45.0,38.9');
    });

    test('keeps the surrounding text as plain runs', () {
      final segments = CoordinateText.split('Я здесь 45.0,38.9 всем привет');
      expect(
        segments.map((s) => s.text).join(),
        'Я здесь 45.0,38.9 всем привет',
      );
      expect(segments.where((s) => s.isCoordinate).length, 1);
    });

    test('accepts spacing, a trailing sentence dot and a whole message', () {
      expect(_firstCoordinate('45.073207,38.932829'), isNotNull);
      expect(_firstCoordinate('координаты 45.0, 38.9, приезжай'), isNotNull);
      expect(_firstCoordinate('Я здесь 45.0,38.9.'), isNotNull);
      expect(_firstCoordinate('(45.0,38.9)'), isNotNull);
      expect(_firstCoordinate('-45.0,-38.9 юг'), isNotNull);
    });

    test('ignores numbers that only look like a pair', () {
      expect(_firstCoordinate('Стоит 1,5 рубля'), isNull);
      expect(_firstCoordinate('пункты 1,2,3'), isNull);
      expect(_firstCoordinate('версия 1.2.3,4.5 вышла'), isNull);
      expect(_firstCoordinate('v45.0,38.9'), isNull);
    });

    test('rejects out-of-range values', () {
      expect(_firstCoordinate('95.5,38.9'), isNull);
      expect(_firstCoordinate('45.0,381.9'), isNull);
    });

    test('has() agrees with split()', () {
      expect(CoordinateText.has('Я здесь 45.0,38.9 всем привет'), isTrue);
      expect(CoordinateText.has('Стоит 1,5 рубля'), isFalse);
      expect(CoordinateText.has('без чисел'), isFalse);
    });
  });
}
