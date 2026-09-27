import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

void main() {
  // Frame layout per the doc comment on buildUpdateContactPathFrame:
  //   [cmd][pub_key x32][type][flags][path_len][path x64][name x32]
  //   [last_advert x4][Lat? x4, Lon? x4][lastmod? x4]
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

    int lastAdvertField(Uint8List frame) => ByteData.sublistView(
      frame,
      baseFrameLength - 4,
      baseFrameLength,
    ).getUint32(0, Endian.little);

    test('writes the contact advert timestamp, not the phone clock', () {
      final advert = DateTime.utc(2025, 6, 1, 12);
      final frame = buildUpdateContactPathFrame(
        pubKey,
        path,
        path.length,
        lastAdvert: advert,
        lastModified: DateTime.utc(2026, 1, 2),
      );

      expect(lastAdvertField(frame), advert.millisecondsSinceEpoch ~/ 1000);
      expect(
        ByteData.sublistView(
          frame,
          baseFrameLength + 8,
        ).getUint32(0, Endian.little),
        DateTime.utc(2026, 1, 2).millisecondsSinceEpoch ~/ 1000,
      );
    });

    test('writes 0 for last advert when unknown', () {
      final frame = buildUpdateContactPathFrame(pubKey, path, path.length);
      expect(lastAdvertField(frame), 0);
    });
  });

  group('auto-add / repeat freq frames', () {
    test('SET_AUTOADD_CONFIG appends max hops only when given', () {
      final withoutHops = buildSetAutoAddConfigFrame(
        autoAddChat: true,
        autoAddRepeater: false,
        autoAddRoomServer: false,
        autoAddSensor: false,
        overwriteOldest: true,
      );
      expect(withoutHops, [
        cmdSetAutoAddConfig,
        autoAddChatFlag | autoAddOverwriteOldestFlag,
      ]);

      final withHops = buildSetAutoAddConfigFrame(
        autoAddChat: false,
        autoAddRepeater: false,
        autoAddRoomServer: false,
        autoAddSensor: false,
        overwriteOldest: false,
        maxHops: 3,
      );
      expect(withHops, [cmdSetAutoAddConfig, 0, 3]);
    });

    test('parses RESP_ALLOWED_REPEAT_FREQ ranges', () {
      final data = ByteData(1 + 16);
      data.setUint8(0, respCodeAllowedRepeatFreq);
      data.setUint32(1, 433000, Endian.little);
      data.setUint32(5, 433000, Endian.little);
      data.setUint32(9, 869495, Endian.little);
      data.setUint32(13, 869600, Endian.little);
      final ranges = parseAllowedRepeatFreqFrame(data.buffer.asUint8List());
      expect(ranges, [
        (lowKHz: 433000, highKHz: 433000),
        (lowKHz: 869495, highKHz: 869600),
      ]);
      expect(buildGetAllowedRepeatFreqFrame(), [cmdGetAllowedRepeatFreq]);
    });
  });
}
