import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:qr_flutter/qr_flutter.dart';

/// A QR code as plain pixels: black modules on an opaque white square, with the
/// quiet zone the standard asks for, so the picture still scans after it has
/// been pasted onto any background.
///
/// Built straight from the module matrix rather than painted: every module is
/// a whole number of pixels, which keeps the edges sharp at any size.
class QrBitmap {
  const QrBitmap._(this.size, this.rgba);

  /// Light modules every side of a QR code has to keep clear.
  static const int quietZoneModules = 4;

  /// Width and height in pixels.
  final int size;

  /// `size * size` opaque pixels, four bytes each, rows from the top.
  final Uint8List rgba;

  /// The same code `QrImageView` draws for [data]: automatic version, the mask
  /// the `qr` package scores best. [targetSize] is an upper bound — the side
  /// is the largest whole number of pixels per module that fits into it.
  ///
  /// Throws what `QrCode.fromData` throws when [data] is too long for a code.
  static QrBitmap render(
    String data, {
    int targetSize = 1024,
    int errorCorrectionLevel = QrErrorCorrectLevel.M,
  }) {
    final code = QrCode.fromData(
      data: data,
      errorCorrectLevel: errorCorrectionLevel,
    );
    final image = QrImage(code);
    final modules = code.moduleCount + quietZoneModules * 2;
    final scale = targetSize < modules ? 1 : targetSize ~/ modules;
    final size = modules * scale;
    final rgba = Uint8List(size * size * 4)
      ..fillRange(0, size * size * 4, 0xFF);

    for (var row = 0; row < code.moduleCount; row++) {
      for (var column = 0; column < code.moduleCount; column++) {
        if (!image.isDark(row, column)) continue;
        final top = (row + quietZoneModules) * scale;
        final left = (column + quietZoneModules) * scale;
        for (var y = top; y < top + scale; y++) {
          var offset = (y * size + left) * 4;
          for (var x = 0; x < scale; x++) {
            // Alpha keeps the 0xFF the buffer was filled with.
            rgba[offset] = 0;
            rgba[offset + 1] = 0;
            rgba[offset + 2] = 0;
            offset += 4;
          }
        }
      }
    }
    return QrBitmap._(size, rgba);
  }

  Future<Uint8List> toPng() async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      size,
      size,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Failed to encode the QR code');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image.dispose();
    }
  }
}
