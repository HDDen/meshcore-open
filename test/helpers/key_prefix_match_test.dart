import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/key_prefix_match.dart';

/// The string-based check the connector used before: both sides as upper-case
/// hex, then `startsWith`. The byte-wise version must agree with it on every
/// input.
bool _legacyHexStartsWith(String contactKeyHex, List<int> pubkeyPrefix) {
  final normalizedPrefixHex = pubkeyPrefix
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();
  return contactKeyHex.toUpperCase().startsWith(normalizedPrefixHex);
}

String _hex(List<int> bytes, {bool upper = false}) {
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return upper ? hex.toUpperCase() : hex;
}

void main() {
  test('agrees with the string check on random keys, widths and cases', () {
    final random = Random(7);
    for (var round = 0; round < 3000; round++) {
      final key = List<int>.generate(32, (_) => random.nextInt(256));
      final width = 1 + random.nextInt(4);
      // Half the time the prefix really is the key's start, so both answers
      // are exercised; the other half it is random, mostly a miss.
      final prefix = random.nextBool()
          ? key.sublist(0, width)
          : List<int>.generate(width, (_) => random.nextInt(256));
      final hex = _hex(key, upper: random.nextBool());
      final mixed = hex
          .split('')
          .map((c) => random.nextBool() ? c.toUpperCase() : c.toLowerCase())
          .join();

      expect(
        KeyPrefixMatch.hexStartsWith(hex, prefix),
        _legacyHexStartsWith(hex, prefix),
        reason: 'key $hex prefix $prefix',
      );
      expect(
        KeyPrefixMatch.hexStartsWith(mixed, prefix),
        _legacyHexStartsWith(mixed, prefix),
        reason: 'key $mixed prefix $prefix',
      );
      expect(
        KeyPrefixMatch.keyStartsWith(key, prefix),
        _legacyHexStartsWith(hex, prefix),
        reason: 'bytes of $hex prefix $prefix',
      );
    }
  });

  test('edge cases', () {
    expect(KeyPrefixMatch.hexStartsWith('ab12', const []), isTrue);
    expect(KeyPrefixMatch.keyStartsWith(const [0xAB, 0x12], const []), isTrue);
    expect(KeyPrefixMatch.hexStartsWith('ab', const [0xAB, 0x12]), isFalse);
    expect(KeyPrefixMatch.keyStartsWith(const [0xAB], const [0xAB, 0x12]), isFalse);
    expect(KeyPrefixMatch.hexStartsWith('AB12', const [0xAB, 0x12]), isTrue);
    expect(KeyPrefixMatch.hexStartsWith('aB12', const [0xAB, 0x12]), isTrue);
    expect(KeyPrefixMatch.hexStartsWith('ab13', const [0xAB, 0x12]), isFalse);
    expect(KeyPrefixMatch.hexStartsWith('zz12', const [0xAB, 0x12]), isFalse);
    expect(KeyPrefixMatch.hexStartsWith('', const [0x00]), isFalse);
  });
}
