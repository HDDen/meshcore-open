import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/contact.dart';

const _allBytesHex =
    '000102030405060708090a0b0c0d0e0f'
    '101112131415161718191a1b1c1d1e1f'
    '202122232425262728292a2b2c2d2e2f'
    '303132333435363738393a3b3c3d3e3f'
    '404142434445464748494a4b4c4d4e4f'
    '505152535455565758595a5b5c5d5e5f'
    '606162636465666768696a6b6c6d6e6f'
    '707172737475767778797a7b7c7d7e7f'
    '808182838485868788898a8b8c8d8e8f'
    '909192939495969798999a9b9c9d9e9f'
    'a0a1a2a3a4a5a6a7a8a9aaabacadaeaf'
    'b0b1b2b3b4b5b6b7b8b9babbbcbdbebf'
    'c0c1c2c3c4c5c6c7c8c9cacbcccdcecf'
    'd0d1d2d3d4d5d6d7d8d9dadbdcdddedf'
    'e0e1e2e3e4e5e6e7e8e9eaebecedeeef'
    'f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff';

Contact _contact(Uint8List key, String name) => Contact(
  publicKey: key,
  name: name,
  type: advTypeChat,
  pathLength: -1,
  path: Uint8List(0),
  lastSeen: DateTime.utc(2026),
);

void main() {
  test('U10a baseline: every byte has fixed lowercase hex and leading zeros', () {
    final bytes = Uint8List.fromList(List<int>.generate(256, (i) => i));
    expect(pubKeyToHex(bytes), _allBytesHex);
    expect(bytes, List<int>.generate(256, (i) => i));
    expect(pubKeyToHex(Uint8List(0)), '');
    expect(pubKeyToHex(Uint8List.fromList([0, 1, 15, 16, 127, 128, 255])),
        '00010f107f80ff');
  });

  test('U10a baseline: a buffer view converts only its own bytes', () {
    final backing = Uint8List.fromList([0xee, 0, 0x0f, 0xa0, 0xff, 0xdd]);
    expect(pubKeyToHex(Uint8List.sublistView(backing, 1, 5)), '000fa0ff');
    expect(backing, [0xee, 0, 0x0f, 0xa0, 0xff, 0xdd]);
  });

  test('U10a baseline: six-byte prefixes and full keys retain their width', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final expected = _allBytesHex.substring(0, 64);
    expect(pubKeyToHex(key), expected);
    expect(pubKeyToHex(Uint8List.sublistView(key, 0, 6)), expected.substring(0, 12));
    expect(hexToPubKey(expected.toUpperCase()), key);
    expect(pubKeyToHex(hexToPubKey(expected)), expected);
  });

  test('U10a baseline: cached contact identity preserves equality and map lookup', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final original = _contact(key, 'Original');
    final renamed = _contact(Uint8List.fromList(key), 'Renamed');
    final different = _contact(Uint8List.fromList(key)..[31] = 255, 'Other');
    final cached = original.publicKeyHex;
    expect(cached, _allBytesHex.substring(0, 64));
    expect(identical(original.publicKeyHex, cached), isTrue);
    expect(original, renamed);
    expect(original.hashCode, renamed.hashCode);
    expect(original, isNot(different));
    expect({original: 'saved'}[renamed], 'saved');
    expect({original, renamed, different}, hasLength(2));
  });
}
