import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/contact.dart';

Contact _contact(int lastByte) => Contact(
  publicKey: Uint8List.fromList([
    0x00,
    0x0F,
    0xB2,
    ...List<int>.filled(28, 0x44),
    lastByte,
  ]),
  name: 'Synthetic key identity',
  type: advTypeRepeater,
  pathLength: 1,
  path: Uint8List.fromList([0xAA, 0xBB, 0xCC]),
  pathHashWidth: 3,
  lastSeen: DateTime.utc(2026),
);

void main() {
  test('U06a2 baseline: the complete key retains leading zeros and is cached', () {
    final contact = _contact(0x01);
    final key = contact.publicKeyHex;
    expect(key, '000fb2${'44' * 28}01');
    expect(key.length, 64);
    expect(identical(contact.publicKeyHex, key), isTrue);
  });

  test('U06a2 baseline: equal routing prefixes do not merge contact identity', () {
    final first = _contact(0x01);
    final second = _contact(0x02);
    final renamed = first.copyWith(name: 'Renamed', pathHashWidth: 2);
    expect(first, isNot(second));
    expect(renamed, first);
    expect(renamed.hashCode, first.hashCode);
    expect(renamed.publicKeyHex, first.publicKeyHex);
    expect({first, second, renamed}, hasLength(2));
  });
}
