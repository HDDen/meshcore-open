import 'package:flutter/material.dart';

import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_palette.dart';

class MCOImageMessage extends StatelessWidget {
  final MCOImage image;
  final double maxSize;

  const MCOImageMessage({super.key, required this.image, this.maxSize = 200});

  static MCOImage? tryDecode(String text) {
    if (!text.startsWith(MCOImageCodec.prefix)) return null;
    try {
      return MCOImageCodec().decode(text);
    } on MCOImageCodecException {
      return null;
    }
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

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final colorIndex = image.pixels[y * image.width + x]
            .clamp(0, palette.length - 1)
            .toInt();
        paint.color = palette[colorIndex];
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
