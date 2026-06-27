import 'dart:typed_data';

import '../helpers/mcoimg_codec.dart';

class MCOImageGalleryItem {
  final String id;
  final DateTime createdAt;
  final Uint8List binaryPayload;
  final Uint8List pngBytes;
  final int width;
  final int height;
  final int byteLength;
  final int usedColorCount;
  final PaletteProfile paletteProfile;
  final bool showPngFallback;

  const MCOImageGalleryItem({
    required this.id,
    required this.createdAt,
    required this.binaryPayload,
    required this.pngBytes,
    required this.width,
    required this.height,
    required this.byteLength,
    required this.usedColorCount,
    required this.paletteProfile,
    this.showPngFallback = false,
  });

  MCOImageGalleryItem copyWith({
    bool? showPngFallback,
  }) {
    return MCOImageGalleryItem(
      id: id,
      createdAt: createdAt,
      binaryPayload: binaryPayload,
      pngBytes: pngBytes,
      width: width,
      height: height,
      byteLength: byteLength,
      usedColorCount: usedColorCount,
      paletteProfile: paletteProfile,
      showPngFallback: showPngFallback ?? this.showPngFallback,
    );
  }

  String get textPayload => MCOImageCodec.textFromBinaryPayload(binaryPayload);

  MCOImage? tryDecodeImage() {
    try {
      return MCOImageCodec().decode(textPayload);
    } on MCOImageCodecException {
      return null;
    }
  }
}
