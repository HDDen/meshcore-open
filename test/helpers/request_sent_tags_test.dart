import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/request_sent_tags.dart';

final _now = DateTime(2026, 9, 27, 12);
const _estimate = Duration(seconds: 5);

void main() {
  group('RequestSentTags', () {
    test('an answer matches though another SENT came after its own', () {
      final tags = RequestSentTags()..start();
      tags.recordSent(0x11111111, _estimate, now: _now);
      tags.recordSent(0x22222222, _estimate, now: _now);

      expect(tags.matches(0x11111111), true);
    });

    test('an answer matches though another SENT came before its own', () {
      final tags = RequestSentTags()..start();
      tags.recordSent(0x22222222, _estimate, now: _now);
      tags.recordSent(0x11111111, _estimate, now: _now);

      expect(tags.matches(0x11111111), true);
      expect(tags.matches(0x33333333), false);
    });

    test('nothing is kept or matched outside a request', () {
      final tags = RequestSentTags();

      expect(tags.recordSent(0x11111111, _estimate, now: _now), isNull);
      expect(tags.matches(0x11111111), false);
      expect(tags.isWaiting, false);
    });

    test('the first estimate sets the deadline, later ones only extend', () {
      final tags = RequestSentTags()..start();
      expect(tags.hasDeadline, false);

      const direct = Duration(seconds: 3);
      const flood = Duration(seconds: 20);
      expect(tags.recordSent(1, direct, now: _now), direct);
      expect(tags.hasDeadline, true);
      expect(tags.recordSent(2, const Duration(seconds: 2), now: _now), isNull);
      expect(tags.recordSent(3, flood, now: _now), flood);
    });

    test('a new request forgets the tags and deadline of the last', () {
      final tags = RequestSentTags()..start();
      tags.recordSent(1, _estimate, now: _now);
      tags.clear();

      expect(tags.matches(1), false);
      expect(tags.isWaiting, false);

      tags.start();
      expect(tags.matches(1), false);
      expect(tags.hasDeadline, false);
    });
  });
}
