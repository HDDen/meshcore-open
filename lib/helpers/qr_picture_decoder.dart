import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:zxing2/qrcode.dart';

/// Reads the QR code in a picture with zxing2, the pure Dart port of ZXing:
/// what the gallery scan falls back to where mobile_scanner cannot read
/// pictures (Windows, Linux, the web) or read nothing. The engine decodes the
/// picture (`dart:ui`), scaled down to [maxSide] on its longer side, since a
/// code in a screenshot or a photo stays readable far below that, and the
/// pixels go to a background isolate for the search. Null for a picture the
/// engine cannot decode or one without a code.
Future<String?> decodeQrPicture(Uint8List bytes, {int maxSide = 1600}) async {
  final picture = await _rgbaOf(bytes, maxSide: maxSide);
  if (picture == null) return null;
  return compute(_decodeRgba, picture);
}

/// A picture as opaque RGBA pixels, four bytes each, rows from the top.
class RgbaPicture {
  const RgbaPicture(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;
}

String? _decodeRgba(RgbaPicture picture) => decodeQrFromRgba(
  width: picture.width,
  height: picture.height,
  rgba: picture.rgba,
);

/// The text of the QR code in [rgba] ([width] by [height] pixels, four bytes
/// each), or null when none is found: ZXing's two binarizers over the picture
/// as it is and inverted, each with the try-harder hint.
String? decodeQrFromRgba({
  required int width,
  required int height,
  required Uint8List rgba,
}) {
  // RGBLuminanceSource reads a pixel as 0x00RRGGBB.
  final pixels = Int32List(width * height);
  for (var i = 0, p = 0; i < pixels.length; i++, p += 4) {
    pixels[i] = (rgba[p] << 16) | (rgba[p + 1] << 8) | rgba[p + 2];
  }
  final source = RGBLuminanceSource(width, height, pixels);
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);
  final reader = QRCodeReader();
  for (final candidate in [source, source.invert()]) {
    for (final bitmap in [
      BinaryBitmap(HybridBinarizer(candidate)),
      BinaryBitmap(GlobalHistogramBinarizer(candidate)),
    ]) {
      try {
        return reader.decode(bitmap, hints: hints).text;
      } catch (_) {
        // NotFoundException and its siblings: nothing readable this way.
        continue;
      }
    }
  }
  return null;
}

Future<RgbaPicture?> _rgbaOf(Uint8List bytes, {required int maxSide}) async {
  final ui.ImmutableBuffer buffer;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  } catch (_) {
    return null;
  }
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final longest = math.max(descriptor.width, descriptor.height);
      final scale = longest > maxSide ? maxSide / longest : 1.0;
      final codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round(),
        targetHeight: (descriptor.height * scale).round(),
      );
      try {
        final image = (await codec.getNextFrame()).image;
        try {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (data == null) return null;
          return RgbaPicture(
            image.width,
            image.height,
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } catch (_) {
    // Not a picture the engine decodes.
    return null;
  } finally {
    buffer.dispose();
  }
}
