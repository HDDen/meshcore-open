import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/qr_bitmap.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  const link =
      'meshcore://channel/add?name=%23ping&secret=3cae16fd067ba9c32a98be22e9b98525';
  const quiet = QrBitmap.quietZoneModules;

  QrCode codeOf(String data) =>
      QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M);

  bool isBlack(QrBitmap bitmap, int x, int y) {
    final offset = (y * bitmap.size + x) * 4;
    return bitmap.rgba[offset] == 0 &&
        bitmap.rgba[offset + 1] == 0 &&
        bitmap.rgba[offset + 2] == 0;
  }

  test('a module is a whole number of pixels, as large as the target lets', () {
    final modules = codeOf(link).moduleCount + quiet * 2;
    final bitmap = QrBitmap.render(link);
    expect(bitmap.size % modules, 0);
    expect(bitmap.size, lessThanOrEqualTo(1024));
    expect(bitmap.size + modules, greaterThan(1024));
    expect(bitmap.rgba.length, bitmap.size * bitmap.size * 4);
  });

  test('draws exactly the modules of the code', () {
    final code = codeOf(link);
    final image = QrImage(code);
    final bitmap = QrBitmap.render(link, targetSize: 300);
    final scale = bitmap.size ~/ (code.moduleCount + quiet * 2);
    expect(scale, greaterThan(1));
    for (var row = 0; row < code.moduleCount; row++) {
      for (var column = 0; column < code.moduleCount; column++) {
        final left = (column + quiet) * scale;
        final top = (row + quiet) * scale;
        // Both corners of the module, so a short or shifted fill shows up.
        for (final (x, y) in [
          (left, top),
          (left + scale - 1, top + scale - 1),
        ]) {
          expect(
            isBlack(bitmap, x, y),
            image.isDark(row, column),
            reason: 'module $row,$column at $x,$y',
          );
        }
      }
    }
  });

  test('keeps the quiet zone white and every pixel opaque', () {
    final bitmap = QrBitmap.render(link, targetSize: 300);
    final scale = bitmap.size ~/ (codeOf(link).moduleCount + quiet * 2);
    final border = quiet * scale;
    var transparent = 0;
    var darkInQuietZone = 0;
    for (var y = 0; y < bitmap.size; y++) {
      for (var x = 0; x < bitmap.size; x++) {
        if (bitmap.rgba[(y * bitmap.size + x) * 4 + 3] != 0xFF) transparent++;
        final inside =
            x >= border &&
            y >= border &&
            x < bitmap.size - border &&
            y < bitmap.size - border;
        if (!inside && isBlack(bitmap, x, y)) darkInQuietZone++;
      }
    }
    expect(transparent, 0);
    expect(darkInQuietZone, 0);
    // The finder pattern starts right where the quiet zone ends.
    expect(isBlack(bitmap, border, border), isTrue);
  });

  test('a target smaller than the code still gives a pixel per module', () {
    final bitmap = QrBitmap.render(link, targetSize: 10);
    expect(bitmap.size, codeOf(link).moduleCount + quiet * 2);
  });
}
