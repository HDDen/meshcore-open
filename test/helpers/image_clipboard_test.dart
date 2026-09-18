import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/image_clipboard_io.dart';

void main() {
  group('ImageClipboard.windowsDib', () {
    // Two by two: red and green on top, blue and a half-transparent grey below.
    final rgba = Uint8List.fromList([
      255, 0, 0, 255, 0, 255, 0, 255, //
      0, 0, 255, 255, 10, 20, 30, 128,
    ]);

    test('writes a 40-byte BITMAPINFOHEADER for 32-bit BI_RGB', () {
      final dib = ImageClipboard.windowsDib(2, 2, rgba);
      final header = ByteData.sublistView(dib, 0, 40);
      expect(dib.length, 40 + 16);
      expect(header.getUint32(0, Endian.little), 40);
      expect(header.getInt32(4, Endian.little), 2);
      // Positive height: the rows run from the bottom one up.
      expect(header.getInt32(8, Endian.little), 2);
      expect(header.getUint16(12, Endian.little), 1);
      expect(header.getUint16(14, Endian.little), 32);
      expect(header.getUint32(16, Endian.little), 0);
      expect(header.getUint32(20, Endian.little), 16);
      expect(dib.sublist(24, 40), everyElement(0));
    });

    test('stores BGRA rows bottom-up and always opaque', () {
      final dib = ImageClipboard.windowsDib(2, 2, rgba);
      expect(dib.sublist(40), [
        255, 0, 0, 255, 30, 20, 10, 255, // bottom row: blue, grey
        0, 0, 255, 255, 0, 255, 0, 255, // top row: red, green
      ]);
    });

    test('refuses a buffer that is not width by height pixels', () {
      expect(
        () => ImageClipboard.windowsDib(3, 2, rgba),
        throwsArgumentError,
      );
    });
  });
}
