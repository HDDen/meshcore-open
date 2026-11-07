import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';
import 'package:koni_jxl_flutter/koni_jxl_flutter.dart';

import 'theme_media.dart';

const int _maxSelectedPictureBytes = 12 * 1024 * 1024;
const int _maxThemeIconSide = 128;

/// The picker can return the original file on desktop. Bound the read even
/// when its reported length changes during the operation.
Future<Uint8List> readThemePicture(XFile file) async {
  if (await file.length() > _maxSelectedPictureBytes) {
    throw const FormatException('Theme picture is too large');
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    if (bytes.length + chunk.length > _maxSelectedPictureBytes) {
      throw const FormatException('Theme picture is too large');
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

Future<ui.Image> decodeThemePicture(Uint8List bytes, int maxSide) async {
  if (bytes.isEmpty || bytes.length > _maxSelectedPictureBytes) {
    throw const FormatException('Invalid theme picture size');
  }
  if (looksLikeJxl(bytes)) {
    return decodeJxlToUiImage(bytes, cacheWidth: maxSide, cacheHeight: maxSide);
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (width, height) {
      final longest = width > height ? width : height;
      if (longest <= maxSide) {
        return ui.TargetImageSize(width: width, height: height);
      }
      final scale = maxSide / longest;
      return ui.TargetImageSize(
        width: math.max(1, (width * scale).round()),
        height: math.max(1, (height * scale).round()),
      );
    },
  );
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// Re-encodes a single frame and keeps the alpha channel for icon artwork.
Future<Uint8List?> shrinkThemeIconImage(Uint8List bytes) async {
  ui.Image? image;
  try {
    image = await decodeThemePicture(bytes, _maxThemeIconSide);
    final encoded = await encodeJxlFromUiImage(image);
    return encoded.length <= maxThemeIconBytes ? encoded : null;
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
  }
}
