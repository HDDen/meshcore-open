import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/advert_feature_fields.dart';

void main() {
  test('two little-endian feature fields are skipped before reading the name', () {
    for (final flags in [0, 0x20, 0x40, 0x60]) {
      final reader = BufferReader(Uint8List.fromList([
        if (flags & 0x20 != 0) ...[0, 0x12],
        if (flags & 0x40 != 0) ...[0, 0x34],
        ...'Node'.codeUnits, 0,
      ]));
      skipAdvertFeatureFields(reader, flags);
      expect(reader.readCString(), 'Node');
    }
  });

  test('a declared feature field must be complete', () {
    final reader = BufferReader(Uint8List.fromList([0]));
    expect(() => skipAdvertFeatureFields(reader, 0x20), throwsRangeError);
  });

  test('missing names retain a known name without replacing actual names', () {
    for (final missing in ['', '  ', '\t']) {
      expect(retainedAdvertName('Known', missing), 'Known');
    }
    expect(retainedAdvertName('Known', 'Renamed'), 'Renamed');
    expect(retainedAdvertName('Known', 'Unknown'), 'Unknown');
    expect(retainedAdvertName('', 'New'), 'New');
    expect(retainedAdvertName('', ''), '');
  });
}
