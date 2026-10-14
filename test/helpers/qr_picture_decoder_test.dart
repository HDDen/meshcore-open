import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/qr_bitmap.dart';
import 'package:meshcore_open/helpers/qr_picture_decoder.dart';

// The pure Dart half of the gallery scan: a QR code the share screen draws,
// as pixels, comes back as its text, upright and inverted alike, and a
// picture without a code answers nothing.

const _link =
    'meshcore://channel/add?name=%23ping&secret=3cae16fd067ba9c32a98be22e9b98525';

void main() {
  test('reads the code the share screen draws', () {
    final bitmap = QrBitmap.render(_link, targetSize: 300);
    expect(
      decodeQrFromRgba(
        width: bitmap.size,
        height: bitmap.size,
        rgba: bitmap.rgba,
      ),
      _link,
    );
  });

  test('reads a code pasted onto a dark page, light on dark', () {
    final bitmap = QrBitmap.render(_link, targetSize: 300);
    final inverted = Uint8List.fromList(bitmap.rgba);
    for (var p = 0; p < inverted.length; p += 4) {
      inverted[p] = 255 - inverted[p];
      inverted[p + 1] = 255 - inverted[p + 1];
      inverted[p + 2] = 255 - inverted[p + 2];
    }
    expect(
      decodeQrFromRgba(width: bitmap.size, height: bitmap.size, rgba: inverted),
      _link,
    );
  });

  test('a code with a margin of page around it still reads', () {
    final bitmap = QrBitmap.render(_link, targetSize: 200);
    const margin = 60;
    final side = bitmap.size + margin * 2;
    final page = Uint8List(side * side * 4)..fillRange(0, side * side * 4, 0xF0);
    for (var y = 0; y < bitmap.size; y++) {
      page.setRange(
        ((y + margin) * side + margin) * 4,
        ((y + margin) * side + margin + bitmap.size) * 4,
        bitmap.rgba,
        y * bitmap.size * 4,
      );
    }
    expect(decodeQrFromRgba(width: side, height: side, rgba: page), _link);
  });

  test('a blank picture holds no code', () {
    final blank = Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, 0xFF);
    expect(decodeQrFromRgba(width: 64, height: 64, rgba: blank), isNull);
  });
}
