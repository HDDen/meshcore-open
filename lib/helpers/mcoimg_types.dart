import 'dart:typed_data';

enum PaletteProfile {
  mono,
  master4,
  master8,
  master16,
  master32,
  master64,
  grayscale16,
  grayscale32,
  grayscale8,
  dynamicGlobal8,
  dynamicGlobal16,
  dynamicGlobal32,
  dynamicGlobal64,
  dynamicGlobal128,
  dynamicGlobal256,
  dynamicGlobal512,
}

enum ImageMode {
  rawGlobal,
  rawLocal,
  rleLocal,
  sparseBg,
  regionsBg,
  biColorMask,
  rowDelta,
  rowRepeat,
  extended,
}

enum ExtendedImageMode {
  wrappedBlock,
  solidRects,
  compactRle,
  compactSparse,
  lzPixels,
  quadtree,
  bitplanes,
  compactRowDelta,
}

enum ScanMode { h, v, s, sv }

enum DynamicPaletteReferenceEncoding {
  flat,
  banked8x64,
  sortedDelta,
  rangeRuns,
  profileBitmap,
  bankBitmaps,
}

enum MCOImageEncodingVersion { v1Legacy, v2, v3, v4 }

enum MCOImageOutputTarget { text, binary }

const int mcoImageCodecVersionV1 = 1;
const int mcoImageCodecVersionV2 = 2;
const int mcoImageCompressionLevelHigh = 0;
const int mcoImageCompressionLevelNormal = 1;
const int mcoImageCompressionLevelExtreme = 2;
const int mcoImageDefaultCompressionLevel = mcoImageCompressionLevelHigh;

extension PaletteProfileKind on PaletteProfile {
  bool get isDynamic {
    return switch (this) {
      PaletteProfile.dynamicGlobal8 ||
      PaletteProfile.dynamicGlobal16 ||
      PaletteProfile.dynamicGlobal32 ||
      PaletteProfile.dynamicGlobal64 ||
      PaletteProfile.dynamicGlobal128 ||
      PaletteProfile.dynamicGlobal256 ||
      PaletteProfile.dynamicGlobal512 => true,
      _ => false,
    };
  }

  bool get isFixed => !isDynamic;
}

class MCOImage {
  final int width;
  final int height;
  final PaletteProfile paletteProfile;
  final List<int> pixels;
  final int? transparentColor;
  final MCOImageEncodingVersion encodingVersion;

  MCOImage({
    required this.width,
    required this.height,
    required this.paletteProfile,
    required List<int> pixels,
    this.transparentColor,
    this.encodingVersion = MCOImageEncodingVersion.v2,
  }) : pixels = List.unmodifiable(pixels);
}

class MCOImagePayloadInfo {
  final int version;
  final String algorithm;
  final int binaryLength;

  const MCOImagePayloadInfo({
    required this.version,
    required this.algorithm,
    required this.binaryLength,
  });
}

class MCOImageBackgroundCandidate {
  final int color;
  final int rank;

  const MCOImageBackgroundCandidate({required this.color, required this.rank});
}

class EncodedMCOImage {
  final Uint8List payload;
  final String text;
  final ImageMode mode;
  final ScanMode scan;
  final int byteLength;
  final int charLength;
  final bool boundsPresent;
  final int? boundsX;
  final int? boundsY;
  final int? boundsWidth;
  final int? boundsHeight;
  final int? backgroundColor;
  final int? transparentColor;
  final int regionCount;
  final int backgroundRank;
  final int codecVersion;
  final DynamicPaletteReferenceEncoding? dynamicReferenceEncoding;
  final int? localPaletteSize;
  final int? usedBankCount;
  final int? bitsPerLocalPixel;
  final MCOImageEncodingVersion requestedEncodingVersion;
  final MCOImageEncodingVersion actualEncodingVersion;
  final String paletteKind;
  final String container;

  const EncodedMCOImage({
    required this.payload,
    required this.text,
    required this.mode,
    required this.scan,
    required this.byteLength,
    required this.charLength,
    this.boundsPresent = false,
    this.boundsX,
    this.boundsY,
    this.boundsWidth,
    this.boundsHeight,
    this.backgroundColor,
    this.transparentColor,
    this.regionCount = 0,
    this.backgroundRank = 0,
    this.codecVersion = mcoImageCodecVersionV2,
    this.dynamicReferenceEncoding,
    this.localPaletteSize,
    this.usedBankCount,
    this.bitsPerLocalPixel,
    this.requestedEncodingVersion = MCOImageEncodingVersion.v2,
    this.actualEncodingVersion = MCOImageEncodingVersion.v2,
    this.paletteKind = 'fixed',
    this.container = 'block',
  });
}

class MCOImageEncodeDiagnostics {
  final EncodedMCOImage result;
  final List<EncodedMCOImage> candidates;
  final int compressionLevel;

  const MCOImageEncodeDiagnostics({
    required this.result,
    required this.candidates,
    this.compressionLevel = mcoImageCompressionLevelHigh,
  });
}

class MCOImageCodecException implements Exception {
  final String message;

  const MCOImageCodecException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class MCOImageInvalidInputException extends MCOImageCodecException {
  const MCOImageInvalidInputException(super.message);
}

class MCOImageInvalidPayloadException extends MCOImageCodecException {
  const MCOImageInvalidPayloadException(super.message);
}

class MCOImageTooLargeException extends MCOImageCodecException {
  const MCOImageTooLargeException(super.message);
}
