import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/manual_trace_input.dart';
import 'package:meshcore_open/models/contact.dart';

Contact _relay(int fourthByte) => Contact(
  publicKey: Uint8List.fromList([0xA1, 0xB2, 0xC3, fourthByte, ...List.filled(28, 0)]),
  name: 'Relay',
  type: advTypeRepeater,
  pathLength: -1,
  path: Uint8List(0),
  lastSeen: DateTime.utc(2026),
);

void main() {
  test('explicit separators declare width and continuous input uses radio width', () {
    final separated = parseManualTrace('0xa1b2 → C3D4 / E5F6', 1)!;
    expect(separated.width, 2);
    expect(separated.bytes, [0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6]);
    final continuous = parseManualTrace('0XA1B2C3D4E5F6', 3)!;
    expect(continuous.width, 3);
    expect(continuous.bytes, separated.bytes);
  });

  test('malformed or mixed-width text does not drop hops silently', () {
    for (final text in ['', 'A1, BBBB', 'A1, Z1', 'A', 'A1, B', 'AABBCCDD, EEFF0011']) {
      expect(parseManualTrace(text, 1), isNull, reason: text);
    }
  });

  test('the fourth byte requires a unique known relay', () {
    final input = parseManualTrace('A1B2C3', 3)!;
    final first = _relay(4);
    final second = _relay(5);
    expect(resolveManualTraceContacts(input, []), isNull);
    expect(resolveManualTraceContacts(input, [first, _relay(4)]), [first]);
    expect(resolveManualTraceContacts(input, [first, second]), isNull);
    expect(resolveManualTraceContacts(parseManualTrace('A1,B2', 1)!, []), isEmpty);
  });
}
