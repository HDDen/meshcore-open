import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

void main() {
  // Frame layout per the doc comment on buildUpdateContactPathFrame:
  //   [cmd][pub_key x32][type][flags][path_len][path x64][name x32]
  //   [timestamp x4][Lat? x4, Lon? x4][timestamp? x4]
  //
  // Base (mandatory) bytes:
  //   1 cmd + 32 pubKey + 1 type + 1 flags + 1 pathLen + 64 path
  //   + 32 name + 4 timestamp = 136 bytes
  const int baseFrameLength = 136;

  final pubKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final path = Uint8List.fromList([0xAA, 0xBB]);

  group('buildUpdateContactPathFrame', () {
    test('omits lat/lon and timestamp tail when neither is provided', () {
      final frame = buildUpdateContactPathFrame(
        pubKey,
        path,
        path.length,
        name: 'Alice',
      );

      // Should be exactly the base frame, no optional tail.
      expect(frame.length, baseFrameLength);
    });

    test('appends only an 8-byte lat/lon tail when location is provided', () {
      final frame = buildUpdateContactPathFrame(
        pubKey,
        path,
        path.length,
        lat: 49.123456,
        lon: -123.123456,
      );

      expect(frame.length, baseFrameLength + 8);
    });

    test(
      'appends 8 bytes lat/lon + 4 bytes timestamp when both are provided',
      () {
        final frame = buildUpdateContactPathFrame(
          pubKey,
          path,
          path.length,
          lat: 49.0,
          lon: -123.0,
          lastModified: DateTime.utc(2026, 1, 2, 3, 4, 5),
        );

        expect(frame.length, baseFrameLength + 8 + 4);
      },
    );

    test('zero-fills the lat/lon slots and appends timestamp when only '
        'lastModified is provided', () {
      final frame = buildUpdateContactPathFrame(
        pubKey,
        path,
        path.length,
        lastModified: DateTime.utc(2026, 1, 2, 3, 4, 5),
      );

      // 8 zero bytes for lat/lon + 4 bytes timestamp
      expect(frame.length, baseFrameLength + 8 + 4);

      // Verify the lat/lon slot is actually zero — guards against a
      // regression where the function writes garbage into those bytes.
      final tailStart = baseFrameLength;
      for (var i = tailStart; i < tailStart + 8; i++) {
        expect(frame[i], 0, reason: 'byte $i in lat/lon slot must be 0');
      }
    });

    test('encodes positive lat/lon as little-endian fixed-point (×1e6)', () {
      final frame = buildUpdateContactPathFrame(
        pubKey,
        path,
        path.length,
        lat: 49.123456,
        lon: -123.123456,
      );

      // Latitude is the first 4 bytes of the optional tail.
      final latBytes = ByteData.sublistView(
        frame,
        baseFrameLength,
        baseFrameLength + 4,
      );
      final lonBytes = ByteData.sublistView(
        frame,
        baseFrameLength + 4,
        baseFrameLength + 8,
      );

      expect(latBytes.getInt32(0, Endian.little), (49.123456 * 1e6).round());
      expect(lonBytes.getInt32(0, Endian.little), (-123.123456 * 1e6).round());
    });
  });
}
