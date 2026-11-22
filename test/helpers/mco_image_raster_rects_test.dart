import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mco_image_raster_rects.dart';
import 'package:meshcore_open/helpers/mcoimg_codec.dart';

void main() {
  test('reported four-byte image is valid white 256x256 and paints one rectangle', () {
    final bytes = Uint8List.fromList([0x82, 0x28, 0xff, 0xff]);
    final image = MCOImageCodec().decode(MCOImageCodec.textFromBinaryPayload(bytes));
    expect(image.width, 256);
    expect(image.height, 256);
    expect(image.pixels.every((pixel) => pixel == 0), isTrue);
    final rects = mcoImageRasterRects(image.pixels, image.width, image.height);
    expect(rects, [(x: 0, y: 0, width: 256, height: 256, color: 0)]);
    expect(MCOImageCodec.binaryPayloadFromText(MCOImageCodec.textFromBinaryPayload(bytes)), bytes);
  });

  test('rectangles preserve every pixel with no overlaps, including transparency', () {
    for (var width = 1; width <= 19; width++) {
      for (final transparent in [null, 0, 3]) {
        final pixels = List.generate(width * 11, (i) => (i * 17 + i ~/ width) % 5);
        final restored = List<int?>.filled(pixels.length, null);
        for (final rect in mcoImageRasterRects(pixels, width, 11,
            transparentColor: transparent)) {
          for (var y = rect.y; y < rect.y + rect.height; y++) {
            for (var x = rect.x; x < rect.x + rect.width; x++) {
              final index = y * width + x;
              expect(restored[index], isNull);
              restored[index] = rect.color;
            }
          }
        }
        expect(restored, [for (final pixel in pixels) pixel == transparent ? null : pixel]);
      }
    }
  });

  test('runs merge only across consecutive rows with identical bounds', () {
    final pixels = [1, 1, 2, 1, 1, 2, 1, 2, 2];
    final rects = mcoImageRasterRects(pixels, 3, 3);
    expect(rects.first, (x: 0, y: 0, width: 2, height: 2, color: 1));
    expect(mcoImageRasterRects(List.filled(20, 0), 4, 5, transparentColor: 0), isEmpty);
  });
}
