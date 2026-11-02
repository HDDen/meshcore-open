import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/usb_serial_frame_codec.dart';

// Native serial callbacks may split or combine reads differently after the
// flserial update. The companion frames must stay byte-identical in either case.
Uint8List _rxFrame(List<int> payload) => Uint8List.fromList([
  0x3e,
  payload.length & 0xff,
  payload.length >> 8,
  ...payload,
]);

void _expectPayloads(
  List<UsbSerialDecodedPacket> actual,
  List<List<int>> expected,
) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i].isRxFrame, isTrue, reason: 'frame $i');
    expect(actual[i].payload, orderedEquals(expected[i]), reason: 'frame $i');
  }
}

void main() {
  test('baseline: every callback split preserves a full binary RX frame', () {
    final payload = List<int>.generate(
      usbSerialMaxRxPayloadLength,
      (i) => [0x00, 0xff, 0x3c, 0x3e, 0x80, 0x17][i % 6],
    );
    final following = [0x08, 0x00, 0xff];
    final wire = Uint8List.fromList([
      ..._rxFrame(payload),
      ..._rxFrame(following),
    ]);

    for (var split = 0; split <= wire.length; split++) {
      final decoder = UsbSerialFrameDecoder();
      final decoded = [
        ...decoder.ingest(Uint8List.sublistView(wire, 0, split)),
        ...decoder.ingest(Uint8List.sublistView(wire, split)),
      ];
      _expectPayloads(decoded, [payload, following]);
    }
  });

  test('baseline: long bursts have the same frames at every read size', () {
    final payloads = <List<int>>[];
    for (var i = 0; i < 48; i++) {
      final length = [0, 1, 2, 7, 64, usbSerialMaxRxPayloadLength][i % 6];
      payloads.add(List<int>.generate(length, (j) => (i * 13 + j) & 0xff));
    }
    final wire = Uint8List.fromList([
      // Noise before the first valid header must not become a companion frame.
      0x00, 0xff, 0x7f,
      for (final payload in payloads) ..._rxFrame(payload),
    ]);

    for (final readSize in [1, 2, 3, 17, 512, wire.length]) {
      final decoder = UsbSerialFrameDecoder();
      final decoded = <UsbSerialDecodedPacket>[];
      for (var offset = 0; offset < wire.length; offset += readSize) {
        final limit = offset + readSize;
        final end = limit < wire.length ? limit : wire.length;
        decoded.addAll(
          decoder.ingest(Uint8List.sublistView(wire, offset, end)),
        );
      }
      _expectPayloads(decoded, payloads);
    }
  });

  test('baseline: reusing a callback buffer cannot mutate received bytes', () {
    final decoder = UsbSerialFrameDecoder();
    final buffer = Uint8List.fromList([0x3e, 0x04, 0x00, 0x17, 0x00]);
    expect(decoder.ingest(buffer), isEmpty);
    buffer.fillRange(0, buffer.length, 0xff);

    buffer.setAll(0, [0x3c, 0x3e]);
    final decoded = decoder.ingest(Uint8List.sublistView(buffer, 0, 2));
    buffer.fillRange(0, buffer.length, 0x00);
    _expectPayloads(decoded, [
      [0x17, 0x00, 0x3c, 0x3e],
    ]);
  });

  test('baseline: reconnect drops the old partial body and keeps new frames', () {
    final decoder = UsbSerialFrameDecoder();
    expect(
      decoder.ingest(Uint8List.fromList([0x3e, 0x04, 0x00, 0x17, 0xff])),
      isEmpty,
    );

    decoder.reset();

    _expectPayloads(
      decoder.ingest(_rxFrame([0x05, 0x00, 0x80])),
      [
        [0x05, 0x00, 0x80],
      ],
    );
  });
}
