import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/cayenne_lpp.dart';

// Synthetic wire data representing the fields shown in the bug-report image.
// This is not a captured response from the tester's node.
Uint8List _reportedFields() => Uint8List.fromList([
  2, 103, 0x01, 0x1C, // AHT temperature: 28.4 C
  2, 104, 0x5F, // Humidity: 47.5%
  3, 103, 0x01, 0x2B, // BMP temperature: 29.9 C
  3, 115, 0x27, 0xFE, // Pressure: 1023.8 hPa
  3, 121, 0xFF, 0xA9, // Altitude: -87 m
  4, 116, 0x01, 0x80, // Voltage: 3.84 V
  4, 117, 0xFF, 0xF5, // Current: -0.011 A
  4, 128, 0x00, 0x00, // Transmitted power: 0 W (integer-watt field)
]);

void main() {
  group('Cayenne LPP telemetry baseline', () {
    test('separate AHT, BMP and electrical channels retain all reported fields', () {
      expect(CayenneLpp.parseByChannel(_reportedFields()), [
        {
          'channel': 2,
          'values': {'temperature': 28.4, 'humidity': 47.5},
        },
        {
          'channel': 3,
          'values': {
            'temperature': 29.9,
            'pressure': 1023.8,
            'altitude': -87,
          },
        },
        {
          'channel': 4,
          'values': {'voltage': 3.84, 'current': -0.011, 'power': 0},
        },
      ]);
    });

    test('flat decoding retains pressure, signed current and integer power', () {
      expect(CayenneLpp.parse(_reportedFields()), [
        {'channel': 2, 'type': 103, 'value': 28.4},
        {'channel': 2, 'type': 104, 'value': 47.5},
        {'channel': 3, 'type': 103, 'value': 29.9},
        {'channel': 3, 'type': 115, 'value': 1023.8},
        {'channel': 3, 'type': 121, 'value': -87},
        {'channel': 4, 'type': 116, 'value': 3.84},
        {'channel': 4, 'type': 117, 'value': -0.011},
        {'channel': 4, 'type': 128, 'value': 0},
      ]);
    });

    test('transmitted power is preserved rather than replaced with voltage times current', () {
      final payload = Uint8List.fromList([
        4, 116, 0x01, 0x80, // 3.84 V
        4, 117, 0x01, 0xF4, // 0.5 A
        4, 128, 0x00, 0x0D, // 13 W, deliberately different from U * I
      ]);
      expect(CayenneLpp.parseByChannel(payload), [
        {
          'channel': 4,
          'values': {'voltage': 3.84, 'current': 0.5, 'power': 13},
        },
      ]);
    });

    test('interleaved fields on one channel keep pressure beside humidity', () {
      final payload = Uint8List.fromList([
        2, 103, 0x01, 0x1C,
        4, 116, 0x01, 0x80,
        2, 104, 0x5F,
        2, 115, 0x27, 0xFE,
      ]);
      expect(CayenneLpp.parseByChannel(payload), [
        {
          'channel': 2,
          'values': {
            'temperature': 28.4,
            'humidity': 47.5,
            'pressure': 1023.8,
          },
        },
        {
          'channel': 4,
          'values': {'voltage': 3.84},
        },
      ]);
    });

    test('missing pressure and power are not synthesized by the decoder', () {
      final payload = Uint8List.fromList([
        2, 103, 0x01, 0x1C,
        2, 104, 0x5F,
        4, 116, 0x01, 0x80,
        4, 117, 0xFF, 0xF5,
      ]);
      expect(CayenneLpp.parseByChannel(payload), [
        {
          'channel': 2,
          'values': {'temperature': 28.4, 'humidity': 47.5},
        },
        {
          'channel': 4,
          'values': {'voltage': 3.84, 'current': -0.011},
        },
      ]);
    });

    test('an unknown type stops parsing before a later pressure field', () {
      final payload = Uint8List.fromList([
        2, 103, 0x01, 0x1C,
        2, 0xFE, 0x00, // Unknown type: its payload length cannot be inferred.
        3, 115, 0x27, 0xFE,
      ]);
      expect(CayenneLpp.parseByChannel(payload), [
        {
          'channel': 2,
          'values': {'temperature': 28.4},
        },
      ]);
    });

    test('pressure decoded before an unknown type is retained', () {
      final payload = Uint8List.fromList([
        3, 115, 0x27, 0xFE,
        3, 0xFE, 0x00,
      ]);
      expect(CayenneLpp.parseByChannel(payload), [
        {
          'channel': 3,
          'values': {'pressure': 1023.8},
        },
      ]);
    });
  });
}
