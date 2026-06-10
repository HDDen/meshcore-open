import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_palette.dart';

class MCOImageDecodeMetadata {
  final MCOImage? image;
  final int? unsupportedVersion;
  final int currentMaxSupportedVersion;

  const MCOImageDecodeMetadata({
    required this.image,
    required this.unsupportedVersion,
    required this.currentMaxSupportedVersion,
  });

  bool get isImage => image != null;
  bool get isUnsupportedVersion => unsupportedVersion != null;
}

class MCOImageMessage extends StatelessWidget {
  final MCOImage image;
  final double maxSize;

  const MCOImageMessage({super.key, required this.image, this.maxSize = 200});

  static MCOImageDecodeMetadata decodeMetadata(String text) {
    final current = MCOImageCodec.maxSupportedVersion;
    if (!text.startsWith(MCOImageCodec.prefix)) {
      return MCOImageDecodeMetadata(
        image: null,
        unsupportedVersion: null,
        currentMaxSupportedVersion: current,
      );
    }

    final received = MCOImageCodec.decodeHeaderVersion(text);
    if (received != null && received > current) {
      return MCOImageDecodeMetadata(
        image: null,
        unsupportedVersion: received,
        currentMaxSupportedVersion: current,
      );
    }

    try {
      return MCOImageDecodeMetadata(
        image: MCOImageCodec().decode(text),
        unsupportedVersion: null,
        currentMaxSupportedVersion: current,
      );
    } on MCOImageCodecException {
      return MCOImageDecodeMetadata(
        image: null,
        unsupportedVersion: null,
        currentMaxSupportedVersion: current,
      );
    }
  }

  static MCOImage? tryDecode(String text) {
    return decodeMetadata(text).image;
  }

  static Future<Uint8List> renderPngBytes(
    MCOImage image, {
    int cellSize = 16,
  }) async {
    final palette = MCOImagePalette.colorsFor(image.paletteProfile);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..isAntiAlias = false;

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.pixels[y * image.width + x];
        if (image.transparentColor != null && pixel == image.transparentColor) {
          continue;
        }
        paint.color = _colorForPixelValue(image.paletteProfile, pixel, palette);
        canvas.drawRect(
          ui.Rect.fromLTWH(
            (x * cellSize).toDouble(),
            (y * cellSize).toDouble(),
            cellSize.toDouble(),
            cellSize.toDouble(),
          ),
          paint,
        );
      }
    }

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(
      image.width * cellSize,
      image.height * cellSize,
    );
    final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    picture.dispose();
    if (png == null) {
      throw const MCOImageInvalidInputException('Cannot render PNG');
    }
    return png.buffer.asUint8List();
  }

  static Color _colorForPixelValue(
    PaletteProfile profile,
    int colorValue,
    List<Color> palette,
  ) {
    if (profile.isDynamic) {
      if (colorValue < 0 ||
          colorValue >= MCOImageDynamicPalette.global512.length ||
          MCOImageDynamicPalette.profileColorIdForGlobalIndex(
                profile,
                colorValue,
              ) ==
              null) {
        final whiteIndex = MCOImagePalette.whiteIndexFor(profile);
        return MCOImageDynamicPalette.global512[whiteIndex];
      }
      return MCOImageDynamicPalette.global512[colorValue];
    }

    final colorIndex = colorValue.clamp(0, palette.length - 1).toInt();
    return palette[colorIndex];
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = image.width / image.height;
    final displayWidth = aspectRatio >= 1 ? maxSize : maxSize * aspectRatio;
    final displayHeight = aspectRatio >= 1 ? maxSize / aspectRatio : maxSize;
    final palette = MCOImagePalette.colorsFor(image.paletteProfile);

    return CustomPaint(
      size: Size(displayWidth, displayHeight),
      painter: _MCOImagePainter(image: image, palette: palette),
    );
  }
}

class _MCOImagePainter extends CustomPainter {
  final MCOImage image;
  final List<Color> palette;

  const _MCOImagePainter({required this.image, required this.palette});

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / image.width;
    final cellHeight = size.height / image.height;
    final paint = Paint()..isAntiAlias = false;
    final transparentColor = image.transparentColor;

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.pixels[y * image.width + x];
        if (transparentColor != null && pixel == transparentColor) {
          continue;
        }
        paint.color = MCOImageMessage._colorForPixelValue(
          image.paletteProfile,
          pixel,
          palette,
        );
        canvas.drawRect(
          Rect.fromLTWH(x * cellWidth, y * cellHeight, cellWidth, cellHeight),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MCOImagePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.palette != palette;
  }
}
