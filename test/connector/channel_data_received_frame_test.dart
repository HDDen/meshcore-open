import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

/// [code][snr*4][reserved x2][channelIndex][pathByte][dataType LE][dataLength][payload]
Uint8List _frame({required int pathByte, int channelIndex = 3}) {
  return Uint8List.fromList(<int>[
    respCodeChannelDataRecv,
    0x28, // SNR 10.0 dB
    0x00,
    0x00,
    channelIndex,
    pathByte,
    0x20, // data_type 0x0120, little-endian
    0x01,
    0x02,
    0xAA,
    0xBB,
  ]);
}

void main() {
  group('parseChannelDataReceivedFrame path byte', () {
    test('unpacks hash width and hop count like the V3 text frame', () {
      // 0x45 = 01 000101: 2-byte hashes, 5 hops. Read raw it was 69 hops.
      final frame = parseChannelDataReceivedFrame(_frame(pathByte: 0x45));

      expect(frame, isNotNull);
      expect(frame!.pathLength, 5);
      expect(frame.pathHashWidth, 2);
      expect(frame.channelIndex, 3);
      expect(frame.dataType, 0x0120);
      expect(frame.payload, <int>[0xAA, 0xBB]);
      expect(frame.snr, 10.0);
    });

    test('reads every hash width', () {
      expect(parseChannelDataReceivedFrame(_frame(pathByte: 0x03))!.pathHashWidth, 1);
      expect(parseChannelDataReceivedFrame(_frame(pathByte: 0x85))!.pathHashWidth, 3);
      expect(parseChannelDataReceivedFrame(_frame(pathByte: 0xC5))!.pathHashWidth, 4);
      expect(parseChannelDataReceivedFrame(_frame(pathByte: 0xC5))!.pathLength, 5);
    });

    test('a zero-hop flood keeps its width and reports no hops', () {
      final frame = parseChannelDataReceivedFrame(_frame(pathByte: 0x40))!;
      expect(frame.pathLength, 0);
      expect(frame.pathHashWidth, 2);
    });

    test('0xFF is no path: -1 and no hash width', () {
      final frame = parseChannelDataReceivedFrame(_frame(pathByte: 0xFF))!;
      expect(frame.pathLength, -1);
      expect(frame.pathHashWidth, isNull);
    });

    test('a truncated payload is rejected', () {
      final frame = _frame(pathByte: 0x45);
      expect(
        parseChannelDataReceivedFrame(Uint8List.sublistView(frame, 0, frame.length - 1)),
        isNull,
      );
    });
  });
}
