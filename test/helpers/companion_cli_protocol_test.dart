import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/companion_cli_protocol.dart';

void main() {
  test('new local CLI golden is distinct from remote text messages', () {
    expect(buildCompanionCliFrame('ver', 'A1'), [66, 65, 49, 124, 118, 101, 114]);
    final frame = Uint8List.fromList([29, 65, 49, 124, ...utf8.encode('Тест')]);
    expect(companionCliReplyMatches(frame, 'A1'), isTrue);
    expect(companionCliReplyMatches(frame, 'B2'), isFalse);
    expect(companionCliReplyText(frame), 'Тест');
    expect(companionCliReplyText(Uint8List.fromList([29, 65, 49, 124])), '');
  });

  test('limits use UTF-8 bytes and reject truncation control characters and radio overflow', () {
    expect(buildCompanionCliFrame('я' * 86, 'A1').length, 176);
    for (final text in ['я' * 87, 'set radio ${'1' * 132}']) {
      expect(() => buildCompanionCliFrame(text, 'A1'), throwsA(
        isA<CompanionCliException>().having((e) => e.code, 'code', 'tooLong')));
    }
    for (final text in ['', 'x', 'ver\n', 'ver\r', 'ver\u0000']) {
      expect(() => buildCompanionCliFrame(text, 'A1'), throwsA(isA<CompanionCliException>()));
    }
    expect(buildCompanionCliFrame('  set name Synthetic ', 'A1').sublist(4),
      utf8.encode('set name Synthetic '));
  });

  test('local identifiers are never reused and exhaustion fails before sending', () {
    final tags = CompanionCliTags();
    final allocated = <String>{};
    for (var i = 0; i < 62 * 62; i++) {
      final tag = tags.allocate();
      expect(tag.length, 2);
      expect(allocated.add(tag), isTrue);
    }
    expect(tags.allocate, throwsA(isA<CompanionCliException>()));
  });
}
