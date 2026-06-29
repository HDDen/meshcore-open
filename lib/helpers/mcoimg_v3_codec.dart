import 'dart:math' as math;
import 'dart:typed_data';

import 'channel_app_data_helper.dart';
import 'mcoimg_palette.dart';
import 'mcoimg_types.dart';

/// Binary-only MCOimg v3 container kind.
///
/// Unlike v2, this is an explicit field in the v3 body grammar. v2 had to reuse
/// combinations such as regions + extended mode + scan bits as escape markers
/// after the extended submode space became full. v3 should not inherit those
/// escape combinations: each top-level image layout gets its own container id.
enum MCOImageV3Container {
  block,
  boundsBlock,
  regions,
  compactRegionsStream,
  solidBackground,
  solidRects,
}

/// Binary-only MCOimg v3 block algorithm.
///
/// This keeps block algorithms separate from container variants. In v3 the
/// region stream can point directly at one of these algorithms for each region.
enum MCOImageV3BlockAlgorithm {
  rawGlobal,
  rawLocal,
  rleLocal,
  sparseBackground,
  biColorMask,
  rowDelta,
  rowRepeat,
  compactRle,
  compactSparse,
  lzPixels,
  quadtree,
  bitplanes,
  compactRowDelta,
  wrappedBlock,
}

class EncodedMCOImageV3 {
  final Uint8List body;
  final int byteLength;
  final int subtypeVersion;
  final EncodedMCOImage encodedCandidate;

  const EncodedMCOImageV3({
    required this.body,
    required this.byteLength,
    required this.encodedCandidate,
    this.subtypeVersion = ChannelAppDataHelper.mcoImageV3SubtypeVersion,
  });

  Uint8List toAppPayloadWithoutSender() {
    return ChannelAppDataHelper.appPayloadWithoutSender(
      subtypeVersion: subtypeVersion,
      body: body,
    );
  }
}

class MCOImageV3Codec {
  MCOImageV3Codec();

  static const int subtypeVersion =
      ChannelAppDataHelper.mcoImageV3SubtypeVersion;
  static const int _formatMarker = 0x30;
  static const int _transparentFlag = 0x80;
  static const int _profileMask = 0x0f;
  static const int _containerAlgorithmContainerShift = 5;
  static const int _containerAlgorithmAlgorithmMask = 0x1f;
  static const int _minSize = 1;
  static const int _maxSize = 256;
  static const int _maxRegions = 32;
  static const int _minLzMatchLength = 3;
  static const int _maxLzMatchCandidates = 48;

  EncodedMCOImageV3 encode(
    MCOImage image, {
    int? backgroundColor,
    MCOImageOutputTarget outputTarget = MCOImageOutputTarget.binary,
    int compressionLevel = mcoImageDefaultCompressionLevel,
  }) {
    if (outputTarget != MCOImageOutputTarget.binary) {
      throw const MCOImageInvalidInputException(
        'MCOimg v3 supports binary output only',
      );
    }
    _validateImage(image);
    final result = _encodeNative(image, backgroundColor: backgroundColor);
    return EncodedMCOImageV3(
      body: result.payload,
      byteLength: result.payload.length,
      encodedCandidate: result,
    );
  }

  MCOImage decodeBody(Uint8List body) {
    if (body.length < 5) {
      throw const MCOImageInvalidPayloadException('MCOimg v3 payload too short');
    }
    final header = body[0];
    if ((header & 0x70) != _formatMarker) {
      throw const MCOImageInvalidPayloadException('Invalid MCOimg v3 marker');
    }
    final hasTransparentColor = (header & _transparentFlag) != 0;
    final profile = _profileFromId(header & _profileMask);
    final width = body[1] + 1;
    final height = body[2] + 1;
    _validateDimensions(width, height, payload: true);
    final containerAlgorithm = body[3];
    final container = _containerFromId(
      containerAlgorithm >> _containerAlgorithmContainerShift,
    );
    final algorithm = _algorithmFromId(
      containerAlgorithm & _containerAlgorithmAlgorithmMask,
    );
    final scan = _scanFromId(body[4]);
    final reader = _V3BitReader(body, byteIndex: 5);
    final transparentColor = hasTransparentColor
        ? _readColorRef(reader, profile)
        : null;
    final pixels = switch (container) {
      MCOImageV3Container.block => _fromScanOrder(
        _decodeBlockBody(
          reader,
          width,
          height,
          profile,
          algorithm,
          scan,
        ),
        width,
        height,
        scan,
      ),
      MCOImageV3Container.boundsBlock => _decodeBoundsBlockBody(
        reader,
        width,
        height,
        profile,
        algorithm,
        scan,
      ),
      MCOImageV3Container.regions => _decodeRegionsBody(
        reader,
        width,
        height,
        profile,
        compactGeometry: false,
      ),
      MCOImageV3Container.compactRegionsStream => _decodeRegionsBody(
        reader,
        width,
        height,
        profile,
        compactGeometry: true,
      ),
      MCOImageV3Container.solidBackground => List<int>.filled(
        width * height,
        _readColorRef(reader, profile),
      ),
      _ => throw const MCOImageInvalidPayloadException(
        'Unsupported MCOimg v3 container',
      ),
    };
    reader.finish();
    return MCOImage(
      width: width,
      height: height,
      paletteProfile: profile,
      pixels: pixels,
      transparentColor: transparentColor,
      encodingVersion: MCOImageEncodingVersion.v3,
    );
  }

  MCOImage decodeAppPayloadWithoutSender(Uint8List payload) {
    final appPayload =
        ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(payload);
    if (appPayload == null) {
      throw const MCOImageInvalidPayloadException(
        'Invalid MCOimg v3 app payload',
      );
    }
    if (appPayload.subtypeVersion != subtypeVersion) {
      throw MCOImageInvalidPayloadException(
        'Unsupported MCOimg app subtype/version '
        '0x${appPayload.subtypeVersion.toRadixString(16)}',
      );
    }
    return decodeBody(appPayload.body);
  }

  EncodedMCOImage _encodeNative(
    MCOImage image, {
    int? backgroundColor,
  }) {
    final candidates = <EncodedMCOImage>[];
    final preferredBackground =
        backgroundColor ?? MCOImagePalette.whiteIndexFor(image.paletteProfile);
    final usedColors = image.pixels.toSet().toList()..sort();
    final backgroundCandidates = <int>{
      if (_isColorValid(preferredBackground, image.paletteProfile))
        preferredBackground,
      ...usedColors,
    }.toList(growable: false);
    final solidCandidate = _tryBuildSolidBackgroundCandidate(image);
    if (solidCandidate != null) candidates.add(solidCandidate);

    for (final bg in backgroundCandidates) {
      final regionsCandidate = _tryBuildRegionsCandidate(
        image,
        bg,
        compactGeometry: false,
      );
      if (regionsCandidate != null) candidates.add(regionsCandidate);
      final compactRegionsCandidate = _tryBuildRegionsCandidate(
        image,
        bg,
        compactGeometry: true,
      );
      if (compactRegionsCandidate != null) {
        candidates.add(compactRegionsCandidate);
      }

      final bounds = _boundsForBackground(image, bg);
      if (bounds == null ||
          bounds.width == image.width && bounds.height == image.height) {
        continue;
      }
      for (final scan in ScanMode.values) {
        final cropped = _extractBoundsPixels(image, bounds);
        final linear = _toScanOrder(cropped, bounds.width, bounds.height, scan);
        for (final algorithm in const [
          MCOImageV3BlockAlgorithm.rawGlobal,
          MCOImageV3BlockAlgorithm.rawLocal,
          MCOImageV3BlockAlgorithm.rleLocal,
          MCOImageV3BlockAlgorithm.compactRle,
          MCOImageV3BlockAlgorithm.lzPixels,
          MCOImageV3BlockAlgorithm.quadtree,
          MCOImageV3BlockAlgorithm.rowRepeat,
          MCOImageV3BlockAlgorithm.sparseBackground,
          MCOImageV3BlockAlgorithm.biColorMask,
        ]) {
          final candidate = _tryBuildBoundsBlockCandidate(
            image,
            bounds,
            linear,
            algorithm,
            scan,
            backgroundColor: bg,
          );
          if (candidate != null) candidates.add(candidate);
        }
      }
    }

    for (final scan in ScanMode.values) {
      final linear = _toScanOrder(image.pixels, image.width, image.height, scan);
      for (final algorithm in const [
        MCOImageV3BlockAlgorithm.rawGlobal,
        MCOImageV3BlockAlgorithm.rawLocal,
        MCOImageV3BlockAlgorithm.rleLocal,
        MCOImageV3BlockAlgorithm.compactRle,
        MCOImageV3BlockAlgorithm.lzPixels,
        MCOImageV3BlockAlgorithm.quadtree,
        MCOImageV3BlockAlgorithm.rowRepeat,
      ]) {
        final candidate = _tryBuildCandidate(
          image,
          linear,
          algorithm,
          scan,
          backgroundColor: preferredBackground,
        );
        if (candidate != null) candidates.add(candidate);
      }
      for (final bg in backgroundCandidates) {
        for (final algorithm in const [
          MCOImageV3BlockAlgorithm.sparseBackground,
          MCOImageV3BlockAlgorithm.compactSparse,
          MCOImageV3BlockAlgorithm.biColorMask,
        ]) {
          final candidate = _tryBuildCandidate(
            image,
            linear,
            algorithm,
            scan,
            backgroundColor: bg,
          );
          if (candidate != null) candidates.add(candidate);
        }
      }
    }
    if (candidates.isEmpty) {
      throw const MCOImageInvalidInputException('No MCOimg v3 candidate');
    }
    candidates.sort((a, b) {
      final byBytes = a.byteLength.compareTo(b.byteLength);
      if (byBytes != 0) return byBytes;
      return _modeTieRank(a.mode).compareTo(_modeTieRank(b.mode));
    });
    return candidates.first;
  }

  EncodedMCOImage? _tryBuildSolidBackgroundCandidate(MCOImage image) {
    if (image.pixels.isEmpty) return null;
    final color = image.pixels.first;
    for (final pixel in image.pixels) {
      if (pixel != color) return null;
    }

    final writer = _V3BitWriter();
    writer.writeAlignedByte(
      _formatMarker |
          (image.transparentColor != null ? _transparentFlag : 0) |
          _profileId(image.paletteProfile),
    );
    const container = MCOImageV3Container.solidBackground;
    writer
      ..writeAlignedByte(image.width - 1)
      ..writeAlignedByte(image.height - 1)
      ..writeAlignedByte(
        _containerAlgorithmByte(
          container,
          MCOImageV3BlockAlgorithm.rawGlobal,
        ),
      )
      ..writeAlignedByte(ScanMode.h.index);
    if (image.transparentColor != null) {
      _writeColorRef(writer, image.paletteProfile, image.transparentColor!);
    }
    _writeColorRef(writer, image.paletteProfile, color);

    final payload = writer.toBytes();
    return EncodedMCOImage(
      payload: payload,
      text: '',
      mode: ImageMode.rawGlobal,
      scan: ScanMode.h,
      byteLength: payload.length,
      charLength: 0,
      backgroundColor: color,
      transparentColor: image.transparentColor,
      codecVersion: ChannelAppDataHelper.mcoImageV3Version,
      localPaletteSize: 1,
      bitsPerLocalPixel: 0,
      requestedEncodingVersion: MCOImageEncodingVersion.v3,
      actualEncodingVersion: MCOImageEncodingVersion.v3,
      paletteKind: image.paletteProfile.isDynamic ? 'dynamic' : 'fixed',
      container: container.name,
    );
  }

  EncodedMCOImage? _tryBuildRegionsCandidate(
    MCOImage image,
    int backgroundColor, {
    required bool compactGeometry,
  }) {
    final regions = _componentBoundsForBackground(image, backgroundColor);
    if (regions.length < 2 || regions.length > _maxRegions) return null;
    if (!_regionsDoNotOverlap(regions)) return null;

    final regionBlocks = <_V3RegionBlock>[];
    for (final region in regions) {
      final block = _bestRegionBlock(image, region, backgroundColor);
      if (block == null) return null;
      regionBlocks.add(block);
    }

    final writer = _V3BitWriter();
    writer.writeAlignedByte(
      _formatMarker |
          (image.transparentColor != null ? _transparentFlag : 0) |
          _profileId(image.paletteProfile),
    );
    final container = compactGeometry
        ? MCOImageV3Container.compactRegionsStream
        : MCOImageV3Container.regions;
    writer
      ..writeAlignedByte(image.width - 1)
      ..writeAlignedByte(image.height - 1)
      ..writeAlignedByte(
        _containerAlgorithmByte(
          container,
          MCOImageV3BlockAlgorithm.rawGlobal,
        ),
      )
      ..writeAlignedByte(ScanMode.h.index);
    if (image.transparentColor != null) {
      _writeColorRef(writer, image.paletteProfile, image.transparentColor!);
    }

    final bodyStartBits = writer.bitLength;
    try {
      _writeColorRef(writer, image.paletteProfile, backgroundColor);
      writer.writeBitVarUint(regionBlocks.length);
      for (final block in regionBlocks) {
        _writeRegionGeometry(
          writer,
          block.bounds,
          image.width,
          image.height,
          compactGeometry: compactGeometry,
        );
        writer
          ..writeBits(block.algorithm.index, 5)
          ..writeBits(block.scan.index, 2);
        _writeBlockBody(
          writer,
          block.linear,
          image.paletteProfile,
          block.algorithm,
          backgroundColor: backgroundColor,
          rowLength: _rowLengthForScan(
            block.scan,
            block.bounds.width,
            block.bounds.height,
          ),
        );
      }
    } on MCOImageCodecException {
      return null;
    }
    if (writer.bitLength == bodyStartBits) return null;
    final payload = writer.toBytes();
    return EncodedMCOImage(
      payload: payload,
      text: '',
      mode: ImageMode.regionsBg,
      scan: ScanMode.h,
      byteLength: payload.length,
      charLength: 0,
      backgroundColor: backgroundColor,
      transparentColor: image.transparentColor,
      regionCount: regionBlocks.length,
      codecVersion: ChannelAppDataHelper.mcoImageV3Version,
      requestedEncodingVersion: MCOImageEncodingVersion.v3,
      actualEncodingVersion: MCOImageEncodingVersion.v3,
      paletteKind: image.paletteProfile.isDynamic ? 'dynamic' : 'fixed',
      container: container.name,
    );
  }

  _V3RegionBlock? _bestRegionBlock(
    MCOImage image,
    _V3Bounds bounds,
    int backgroundColor,
  ) {
    final cropped = _extractBoundsPixels(image, bounds);
    _V3RegionBlock? best;
    for (final scan in ScanMode.values) {
      final linear = _toScanOrder(cropped, bounds.width, bounds.height, scan);
      for (final algorithm in const [
        MCOImageV3BlockAlgorithm.rawGlobal,
        MCOImageV3BlockAlgorithm.rawLocal,
        MCOImageV3BlockAlgorithm.rleLocal,
        MCOImageV3BlockAlgorithm.compactRle,
        MCOImageV3BlockAlgorithm.lzPixels,
        MCOImageV3BlockAlgorithm.quadtree,
        MCOImageV3BlockAlgorithm.rowRepeat,
        MCOImageV3BlockAlgorithm.sparseBackground,
        MCOImageV3BlockAlgorithm.compactSparse,
        MCOImageV3BlockAlgorithm.biColorMask,
      ]) {
        if (algorithm == MCOImageV3BlockAlgorithm.quadtree &&
            scan != ScanMode.h) {
          continue;
        }
        final writer = _V3BitWriter();
        try {
          _writeBlockBody(
            writer,
            linear,
            image.paletteProfile,
            algorithm,
            backgroundColor: backgroundColor,
            rowLength: _rowLengthForScan(scan, bounds.width, bounds.height),
          );
        } on MCOImageCodecException {
          continue;
        }
        final bits = writer.bitLength;
        if (bits == 0) continue;
        if (best == null ||
            bits < best.bitLength ||
            bits == best.bitLength &&
                _modeTieRank(_imageModeForAlgorithm(algorithm)) <
                    _modeTieRank(_imageModeForAlgorithm(best.algorithm))) {
          best = _V3RegionBlock(
            bounds: bounds,
            algorithm: algorithm,
            scan: scan,
            linear: linear,
            bitLength: bits,
          );
        }
      }
    }
    return best;
  }

  EncodedMCOImage? _tryBuildBoundsBlockCandidate(
    MCOImage image,
    _V3Bounds bounds,
    List<int> linear,
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan, {
    required int backgroundColor,
  }) {
    final writer = _V3BitWriter();
    if (algorithm == MCOImageV3BlockAlgorithm.quadtree &&
        scan != ScanMode.h) {
      return null;
    }
    writer.writeAlignedByte(
      _formatMarker |
          (image.transparentColor != null ? _transparentFlag : 0) |
          _profileId(image.paletteProfile),
    );
    const container = MCOImageV3Container.boundsBlock;
    writer
      ..writeAlignedByte(image.width - 1)
      ..writeAlignedByte(image.height - 1)
      ..writeAlignedByte(_containerAlgorithmByte(container, algorithm))
      ..writeAlignedByte(scan.index);
    if (image.transparentColor != null) {
      _writeColorRef(writer, image.paletteProfile, image.transparentColor!);
    }

    final bodyStartBits = writer.bitLength;
    try {
      _writeColorRef(writer, image.paletteProfile, backgroundColor);
      writer
        ..writeBits(bounds.x, 8)
        ..writeBits(bounds.y, 8)
        ..writeBits(bounds.width - 1, 8)
        ..writeBits(bounds.height - 1, 8);
      _writeBlockBody(
        writer,
        linear,
        image.paletteProfile,
        algorithm,
        backgroundColor: backgroundColor,
        rowLength: _rowLengthForScan(scan, bounds.width, bounds.height),
      );
    } on MCOImageCodecException {
      return null;
    }
    if (writer.bitLength == bodyStartBits) return null;
    final payload = writer.toBytes();
    return EncodedMCOImage(
      payload: payload,
      text: '',
      mode: _imageModeForAlgorithm(algorithm),
      scan: scan,
      byteLength: payload.length,
      charLength: 0,
      backgroundColor: backgroundColor,
      transparentColor: image.transparentColor,
      codecVersion: ChannelAppDataHelper.mcoImageV3Version,
      localPaletteSize: _localPaletteSizeFor(
        linear,
        algorithm,
        backgroundColor,
      ),
      bitsPerLocalPixel: _bitsPerLocalPixelFor(
        linear,
        algorithm,
        backgroundColor,
      ),
      requestedEncodingVersion: MCOImageEncodingVersion.v3,
      actualEncodingVersion: MCOImageEncodingVersion.v3,
      paletteKind: image.paletteProfile.isDynamic ? 'dynamic' : 'fixed',
      container: container.name,
      boundsPresent: true,
      boundsX: bounds.x,
      boundsY: bounds.y,
      boundsWidth: bounds.width,
      boundsHeight: bounds.height,
    );
  }

  EncodedMCOImage? _tryBuildCandidate(
    MCOImage image,
    List<int> linear,
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan, {
    required int backgroundColor,
  }) {
    if (algorithm == MCOImageV3BlockAlgorithm.quadtree &&
        scan != ScanMode.h) {
      return null;
    }
    final writer = _V3BitWriter();
    writer.writeAlignedByte(
      _formatMarker |
          (image.transparentColor != null ? _transparentFlag : 0) |
          _profileId(image.paletteProfile),
    );
    const container = MCOImageV3Container.block;
    writer
      ..writeAlignedByte(image.width - 1)
      ..writeAlignedByte(image.height - 1)
      ..writeAlignedByte(_containerAlgorithmByte(container, algorithm))
      ..writeAlignedByte(scan.index);
    if (image.transparentColor != null) {
      _writeColorRef(writer, image.paletteProfile, image.transparentColor!);
    }

    final bodyStartBits = writer.bitLength;
    try {
      _writeBlockBody(
        writer,
        linear,
        image.paletteProfile,
        algorithm,
        backgroundColor: backgroundColor,
        rowLength: _rowLengthForScan(scan, image.width, image.height),
      );
    } on MCOImageCodecException {
      return null;
    }
    if (writer.bitLength == bodyStartBits) return null;
    final payload = writer.toBytes();
    return EncodedMCOImage(
      payload: payload,
      text: '',
      mode: _imageModeForAlgorithm(algorithm),
      scan: scan,
      byteLength: payload.length,
      charLength: 0,
      backgroundColor: backgroundColor,
      transparentColor: image.transparentColor,
      codecVersion: ChannelAppDataHelper.mcoImageV3Version,
      localPaletteSize: _localPaletteSizeFor(linear, algorithm, backgroundColor),
      bitsPerLocalPixel: _bitsPerLocalPixelFor(
        linear,
        algorithm,
        backgroundColor,
      ),
      requestedEncodingVersion: MCOImageEncodingVersion.v3,
      actualEncodingVersion: MCOImageEncodingVersion.v3,
      paletteKind: image.paletteProfile.isDynamic ? 'dynamic' : 'fixed',
      container: container.name,
    );
  }

  List<int> _decodeBoundsBlockBody(
    _V3BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan,
  ) {
    final background = _readColorRef(reader, profile);
    final x = reader.readBits(8);
    final y = reader.readBits(8);
    final boundsWidth = reader.readBits(8) + 1;
    final boundsHeight = reader.readBits(8) + 1;
    if (x >= width ||
        y >= height ||
        boundsWidth <= 0 ||
        boundsHeight <= 0 ||
        x + boundsWidth > width ||
        y + boundsHeight > height) {
      throw const MCOImageInvalidPayloadException('Invalid v3 bounds block');
    }
    final croppedLinear = _decodeBlockBody(
      reader,
      boundsWidth,
      boundsHeight,
      profile,
      algorithm,
      scan,
    );
    final cropped = _fromScanOrder(
      croppedLinear,
      boundsWidth,
      boundsHeight,
      scan,
    );
    final pixels = List<int>.filled(width * height, background);
    for (var row = 0; row < boundsHeight; row++) {
      final srcStart = row * boundsWidth;
      final dstStart = (y + row) * width + x;
      for (var col = 0; col < boundsWidth; col++) {
        pixels[dstStart + col] = cropped[srcStart + col];
      }
    }
    return pixels;
  }

  List<int> _decodeRegionsBody(
    _V3BitReader reader,
    int width,
    int height,
    PaletteProfile profile, {
    required bool compactGeometry,
  }) {
    final background = _readColorRef(reader, profile);
    final regionCount = reader.readBitVarUint();
    if (regionCount <= 0 || regionCount > _maxRegions) {
      throw const MCOImageInvalidPayloadException('Invalid v3 region count');
    }
    final pixels = List<int>.filled(width * height, background);
    for (var i = 0; i < regionCount; i++) {
      final bounds = _readRegionGeometry(
        reader,
        width,
        height,
        compactGeometry: compactGeometry,
      );
      final algorithm = _algorithmFromId(reader.readBits(5));
      final scan = _scanFromId(reader.readBits(2));
      final linear = _decodeBlockBody(
        reader,
        bounds.width,
        bounds.height,
        profile,
        algorithm,
        scan,
      );
      final regionPixels = _fromScanOrder(
        linear,
        bounds.width,
        bounds.height,
        scan,
      );
      for (var row = 0; row < bounds.height; row++) {
        final srcStart = row * bounds.width;
        final dstStart = (bounds.y + row) * width + bounds.x;
        for (var col = 0; col < bounds.width; col++) {
          pixels[dstStart + col] = regionPixels[srcStart + col];
        }
      }
    }
    return pixels;
  }

  void _writeBlockBody(
    _V3BitWriter writer,
    List<int> linear,
    PaletteProfile profile,
    MCOImageV3BlockAlgorithm algorithm, {
    required int backgroundColor,
    required int rowLength,
  }) {
    switch (algorithm) {
      case MCOImageV3BlockAlgorithm.rawGlobal:
        for (final color in linear) {
          _writeColorRef(writer, profile, color);
        }
        break;
      case MCOImageV3BlockAlgorithm.rawLocal:
        final palette = _localPalette(linear);
        _writeLocalPalette(writer, profile, palette);
        final map = _localIndexMap(palette);
        final bits = _localBits(palette.length);
        for (final color in linear) {
          writer.writeBits(map[color]!, bits);
        }
        break;
      case MCOImageV3BlockAlgorithm.rleLocal:
        final palette = _localPalette(linear);
        _writeLocalPalette(writer, profile, palette);
        final map = _localIndexMap(palette);
        final bits = _localBits(palette.length);
        final runs = _buildRuns(linear);
        writer.writeBitVarUint(runs.length);
        for (final run in runs) {
          writer
            ..writeBits(map[run.color]!, bits)
            ..writeBitVarUint(run.length);
        }
        break;
      case MCOImageV3BlockAlgorithm.compactRle:
        final palette = _localPalette(linear);
        _writeLocalPalette(writer, profile, palette);
        final map = _localIndexMap(palette);
        final bits = _localBits(palette.length);
        for (final run in _buildRuns(linear)) {
          writer
            ..writeBits(map[run.color]!, bits)
            ..writeCompactUint(run.length - 1);
        }
        break;
      case MCOImageV3BlockAlgorithm.lzPixels:
        final palette = _localPalette(linear);
        _writeLocalPalette(writer, profile, palette);
        final map = _localIndexMap(palette);
        final bits = _localBits(palette.length);
        final localPixels = linear.map((color) => map[color]!).toList();
        final tokens = _buildGreedyLzPixelTokens(localPixels, bits);
        for (final token in tokens) {
          if (token.isMatch) {
            writer
              ..writeBits(1, 1)
              ..writeCompactUint(token.distance - 1)
              ..writeCompactUint(token.length - _minLzMatchLength);
          } else {
            writer
              ..writeBits(0, 1)
              ..writeCompactUint(token.literals.length - 1);
            for (final color in token.literals) {
              writer.writeBits(color, bits);
            }
          }
        }
        break;
      case MCOImageV3BlockAlgorithm.quadtree:
        if (rowLength <= 0 ||
            rowLength != linear.length && linear.length % rowLength != 0) {
          throw const MCOImageInvalidInputException(
            'Invalid quadtree geometry',
          );
        }
        final palette = _localPalette(linear);
        _writeLocalPalette(writer, profile, palette);
        final map = _localIndexMap(palette);
        final bits = _localBits(palette.length);
        final localPixels = linear.map((color) => map[color]!).toList();
        _writeQuadtreeNode(
          writer,
          localPixels,
          rowLength,
          0,
          0,
          rowLength,
          linear.length ~/ rowLength,
          bits,
        );
        break;
      case MCOImageV3BlockAlgorithm.sparseBackground:
        _writeColorRef(writer, profile, backgroundColor);
        final nonBg = linear
            .where((color) => color != backgroundColor)
            .toSet()
            .toList()
          ..sort();
        if (nonBg.isEmpty) {
          throw const MCOImageInvalidInputException('Empty sparse body');
        }
        _writeLocalPalette(writer, profile, nonBg);
        final map = _localIndexMap(nonBg);
        final bits = _localBits(nonBg.length);
        final segments = _buildSparseSegments(linear, backgroundColor);
        writer.writeBitVarUint(segments.length);
        var pos = 0;
        for (final segment in segments) {
          writer
            ..writeBitVarUint(segment.start - pos)
            ..writeBits(map[segment.color]!, bits)
            ..writeBitVarUint(segment.length);
          pos = segment.start + segment.length;
        }
        break;
      case MCOImageV3BlockAlgorithm.compactSparse:
        _writeColorRef(writer, profile, backgroundColor);
        final segments = _buildSparseSegments(linear, backgroundColor);
        if (segments.isEmpty) {
          throw const MCOImageInvalidInputException(
            'Empty compact sparse body',
          );
        }
        final nonBg = linear
            .where((color) => color != backgroundColor)
            .toSet()
            .toList()
          ..sort();
        if (nonBg.isEmpty) {
          throw const MCOImageInvalidInputException(
            'Empty compact sparse palette',
          );
        }
        _writeLocalPalette(writer, profile, nonBg);
        final map = _localIndexMap(nonBg);
        final bits = _localBits(nonBg.length);
        writer.writeCompactUint(segments.length - 1);
        var pos = 0;
        for (final segment in segments) {
          writer
            ..writeCompactUint(segment.start - pos)
            ..writeBits(map[segment.color]!, bits)
            ..writeCompactUint(segment.length - 1);
          pos = segment.start + segment.length;
        }
        break;
      case MCOImageV3BlockAlgorithm.biColorMask:
        final foreground = _biColorForeground(linear, backgroundColor);
        if (foreground == null) {
          throw const MCOImageInvalidInputException('Not a bi-color image');
        }
        _writeColorRef(writer, profile, backgroundColor);
        _writeColorRef(writer, profile, foreground);
        for (final color in linear) {
          writer.writeBits(color == foreground ? 1 : 0, 1);
        }
        break;
      case MCOImageV3BlockAlgorithm.rowRepeat:
        final palette = _localPalette(linear);
        _writeLocalPalette(writer, profile, palette);
        final map = _localIndexMap(palette);
        final bits = _localBits(palette.length);
        final localPixels = linear.map((color) => map[color]!).toList();
        _writeRowRepeat(writer, localPixels, rowLength, bits);
        break;
      case MCOImageV3BlockAlgorithm.rowDelta:
      case MCOImageV3BlockAlgorithm.bitplanes:
      case MCOImageV3BlockAlgorithm.compactRowDelta:
      case MCOImageV3BlockAlgorithm.wrappedBlock:
        throw const MCOImageInvalidInputException(
          'MCOimg v3 algorithm is not implemented yet',
        );
    }
  }

  List<int> _decodeBlockBody(
    _V3BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan,
  ) {
    final count = width * height;
    switch (algorithm) {
      case MCOImageV3BlockAlgorithm.rawGlobal:
        return List<int>.generate(count, (_) => _readColorRef(reader, profile));
      case MCOImageV3BlockAlgorithm.rawLocal:
        final palette = _readLocalPalette(reader, profile);
        final bits = _localBits(palette.length);
        return List<int>.generate(count, (_) {
          final index = reader.readBits(bits);
          if (index >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'Local color index out of range',
            );
          }
          return palette[index];
        });
      case MCOImageV3BlockAlgorithm.rleLocal:
        final palette = _readLocalPalette(reader, profile);
        final bits = _localBits(palette.length);
        final runCount = reader.readBitVarUint();
        final result = <int>[];
        for (var i = 0; i < runCount; i++) {
          final colorIndex = reader.readBits(bits);
          if (colorIndex >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'RLE color index out of range',
            );
          }
          final length = reader.readBitVarUint();
          if (length <= 0 || result.length + length > count) {
            throw const MCOImageInvalidPayloadException('Invalid RLE length');
          }
          result.addAll(List<int>.filled(length, palette[colorIndex]));
        }
        if (result.length != count) {
          throw const MCOImageInvalidPayloadException('Invalid RLE size');
        }
        return result;
      case MCOImageV3BlockAlgorithm.compactRle:
        final palette = _readLocalPalette(reader, profile);
        final bits = _localBits(palette.length);
        final result = <int>[];
        while (result.length < count) {
          final colorIndex = reader.readBits(bits);
          if (colorIndex >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'Compact RLE color index out of range',
            );
          }
          final length = reader.readCompactUint() + 1;
          if (result.length + length > count) {
            throw const MCOImageInvalidPayloadException(
              'Compact RLE exceeds pixel count',
            );
          }
          result.addAll(List<int>.filled(length, palette[colorIndex]));
        }
        return result;
      case MCOImageV3BlockAlgorithm.lzPixels:
        final palette = _readLocalPalette(reader, profile);
        final bits = _localBits(palette.length);
        final result = <int>[];
        while (result.length < count) {
          final isMatch = reader.readBits(1) != 0;
          if (isMatch) {
            final distance = reader.readCompactUint() + 1;
            final length = reader.readCompactUint() + _minLzMatchLength;
            if (distance <= 0 ||
                distance > result.length ||
                result.length + length > count) {
              throw const MCOImageInvalidPayloadException(
                'Invalid LZ pixel match',
              );
            }
            for (var i = 0; i < length; i++) {
              result.add(result[result.length - distance]);
            }
          } else {
            final length = reader.readCompactUint() + 1;
            if (result.length + length > count) {
              throw const MCOImageInvalidPayloadException(
                'Invalid LZ pixel literal length',
              );
            }
            for (var i = 0; i < length; i++) {
              final colorIndex = reader.readBits(bits);
              if (colorIndex >= palette.length) {
                throw const MCOImageInvalidPayloadException(
                  'LZ pixel color index out of range',
                );
              }
              result.add(palette[colorIndex]);
            }
          }
        }
        return result;
      case MCOImageV3BlockAlgorithm.quadtree:
        if (scan != ScanMode.h) {
          throw const MCOImageInvalidPayloadException(
            'Quadtree requires horizontal scan',
          );
        }
        final palette = _readLocalPalette(reader, profile);
        final result = List<int>.filled(count, palette.first);
        _readQuadtreeNode(
          reader,
          result,
          width,
          0,
          0,
          width,
          height,
          palette,
          _localBits(palette.length),
        );
        return result;
      case MCOImageV3BlockAlgorithm.sparseBackground:
        final background = _readColorRef(reader, profile);
        final palette = _readLocalPalette(reader, profile);
        final bits = _localBits(palette.length);
        final result = List<int>.filled(count, background);
        final segmentCount = reader.readBitVarUint();
        var pos = 0;
        for (var i = 0; i < segmentCount; i++) {
          pos += reader.readBitVarUint();
          final colorIndex = reader.readBits(bits);
          if (colorIndex >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'Sparse color index out of range',
            );
          }
          final length = reader.readBitVarUint();
          if (length <= 0 || pos + length > count) {
            throw const MCOImageInvalidPayloadException('Invalid sparse run');
          }
          for (var j = 0; j < length; j++) {
            result[pos + j] = palette[colorIndex];
          }
          pos += length;
        }
        return result;
      case MCOImageV3BlockAlgorithm.compactSparse:
        final background = _readColorRef(reader, profile);
        final palette = _readLocalPalette(reader, profile);
        if (palette.contains(background)) {
          throw const MCOImageInvalidPayloadException(
            'Compact sparse palette contains background',
          );
        }
        final bits = _localBits(palette.length);
        final result = List<int>.filled(count, background);
        final segmentCount = reader.readCompactUint() + 1;
        if (segmentCount <= 0 || segmentCount > count) {
          throw const MCOImageInvalidPayloadException(
            'Invalid compact sparse segment count',
          );
        }
        var pos = 0;
        for (var i = 0; i < segmentCount; i++) {
          pos += reader.readCompactUint();
          final colorIndex = reader.readBits(bits);
          if (colorIndex >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'Compact sparse color index out of range',
            );
          }
          final length = reader.readCompactUint() + 1;
          if (pos >= count || pos + length > count) {
            throw const MCOImageInvalidPayloadException(
              'Invalid compact sparse segment',
            );
          }
          for (var j = 0; j < length; j++) {
            result[pos + j] = palette[colorIndex];
          }
          pos += length;
        }
        return result;
      case MCOImageV3BlockAlgorithm.biColorMask:
        final background = _readColorRef(reader, profile);
        final foreground = _readColorRef(reader, profile);
        return List<int>.generate(
          count,
          (_) => reader.readBits(1) != 0 ? foreground : background,
        );
      case MCOImageV3BlockAlgorithm.rowRepeat:
        final palette = _readLocalPalette(reader, profile);
        final bits = _localBits(palette.length);
        final localPixels = _readRowRepeat(
          reader,
          count,
          _rowLengthForScan(scan, width, height),
          bits,
        );
        return localPixels.map((index) {
          if (index >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'Row-repeat color index out of range',
            );
          }
          return palette[index];
        }).toList(growable: false);
      case MCOImageV3BlockAlgorithm.rowDelta:
      case MCOImageV3BlockAlgorithm.bitplanes:
      case MCOImageV3BlockAlgorithm.compactRowDelta:
      case MCOImageV3BlockAlgorithm.wrappedBlock:
        throw const MCOImageInvalidPayloadException(
          'Unsupported MCOimg v3 algorithm',
        );
    }
  }

  static MCOImageV3BlockAlgorithm _algorithmFromId(int value) {
    if (value < 0 || value >= MCOImageV3BlockAlgorithm.values.length) {
      throw MCOImageInvalidPayloadException(
        'Unknown MCOimg v3 algorithm $value',
      );
    }
    return MCOImageV3BlockAlgorithm.values[value];
  }

  static MCOImageV3Container _containerFromId(int value) {
    if (value < 0 || value >= MCOImageV3Container.values.length) {
      throw MCOImageInvalidPayloadException(
        'Unknown MCOimg v3 container $value',
      );
    }
    return MCOImageV3Container.values[value];
  }

  static int _containerAlgorithmByte(
    MCOImageV3Container container,
    MCOImageV3BlockAlgorithm algorithm,
  ) {
    if (container.index >= (1 << 3)) {
      throw const MCOImageInvalidInputException(
        'MCOimg v3 container id does not fit',
      );
    }
    if (algorithm.index > _containerAlgorithmAlgorithmMask) {
      throw const MCOImageInvalidInputException(
        'MCOimg v3 algorithm id does not fit',
      );
    }
    return (container.index << _containerAlgorithmContainerShift) |
        algorithm.index;
  }

  static ScanMode _scanFromId(int value) {
    if (value < 0 || value >= ScanMode.values.length) {
      throw MCOImageInvalidPayloadException('Unknown MCOimg v3 scan $value');
    }
    return ScanMode.values[value];
  }

  static ImageMode _imageModeForAlgorithm(MCOImageV3BlockAlgorithm algorithm) {
    return switch (algorithm) {
      MCOImageV3BlockAlgorithm.rawGlobal => ImageMode.rawGlobal,
      MCOImageV3BlockAlgorithm.rawLocal => ImageMode.rawLocal,
      MCOImageV3BlockAlgorithm.rleLocal => ImageMode.rleLocal,
      MCOImageV3BlockAlgorithm.sparseBackground => ImageMode.sparseBg,
      MCOImageV3BlockAlgorithm.biColorMask => ImageMode.biColorMask,
      MCOImageV3BlockAlgorithm.rowDelta => ImageMode.rowDelta,
      MCOImageV3BlockAlgorithm.rowRepeat => ImageMode.rowRepeat,
      _ => ImageMode.extended,
    };
  }

  static int _modeTieRank(ImageMode mode) {
    return switch (mode) {
      ImageMode.biColorMask => 0,
      ImageMode.sparseBg => 1,
      ImageMode.rowRepeat => 2,
      ImageMode.rleLocal => 3,
      ImageMode.rawLocal => 4,
      ImageMode.rawGlobal => 5,
      ImageMode.extended => 6,
      ImageMode.rowDelta => 7,
      ImageMode.regionsBg => 8,
    };
  }

  static int? _localPaletteSizeFor(
    List<int> linear,
    MCOImageV3BlockAlgorithm algorithm,
    int backgroundColor,
  ) {
    return switch (algorithm) {
      MCOImageV3BlockAlgorithm.rawLocal ||
      MCOImageV3BlockAlgorithm.rleLocal ||
      MCOImageV3BlockAlgorithm.compactRle ||
      MCOImageV3BlockAlgorithm.lzPixels ||
      MCOImageV3BlockAlgorithm.quadtree ||
      MCOImageV3BlockAlgorithm.rowRepeat => linear.toSet().length,
      MCOImageV3BlockAlgorithm.sparseBackground ||
      MCOImageV3BlockAlgorithm.compactSparse =>
        linear.where((color) => color != backgroundColor).toSet().length,
      MCOImageV3BlockAlgorithm.biColorMask => 2,
      _ => null,
    };
  }

  static int? _bitsPerLocalPixelFor(
    List<int> linear,
    MCOImageV3BlockAlgorithm algorithm,
    int backgroundColor,
  ) {
    final paletteSize = _localPaletteSizeFor(
      linear,
      algorithm,
      backgroundColor,
    );
    return paletteSize == null || paletteSize <= 0
        ? null
        : _localBits(paletteSize);
  }

  static List<_V3LzPixelToken> _buildGreedyLzPixelTokens(
    List<int> pixels,
    int localBits,
  ) {
    final tokens = <_V3LzPixelToken>[];
    final pendingLiterals = <int>[];
    final positionsByKey = <int, List<int>>{};

    void flushLiterals() {
      if (pendingLiterals.isEmpty) return;
      tokens.add(_V3LzPixelToken.literal(List<int>.of(pendingLiterals)));
      pendingLiterals.clear();
    }

    var position = 0;
    while (position < pixels.length) {
      var bestLength = 0;
      var bestDistance = 0;
      if (position + _minLzMatchLength <= pixels.length) {
        final key = _lzPixelKey(pixels, position, localBits);
        final candidates = positionsByKey[key];
        if (candidates != null) {
          for (var i = candidates.length - 1; i >= 0; i--) {
            final previous = candidates[i];
            final distance = position - previous;
            var length = _minLzMatchLength;
            while (position + length < pixels.length &&
                pixels[previous + length] == pixels[position + length]) {
              length++;
            }
            if (length > bestLength ||
                length == bestLength &&
                    (bestDistance == 0 || distance < bestDistance)) {
              bestLength = length;
              bestDistance = distance;
            }
          }
        }
      }

      final matchBits = bestLength >= _minLzMatchLength
          ? 1 +
                _compactUintBitLength(bestDistance - 1) +
                _compactUintBitLength(bestLength - _minLzMatchLength)
          : 0;
      final literalBits = bestLength >= _minLzMatchLength
          ? 1 +
                _compactUintBitLength(bestLength - 1) +
                bestLength * localBits
          : 0;
      if (bestLength >= _minLzMatchLength && matchBits < literalBits) {
        flushLiterals();
        tokens.add(_V3LzPixelToken.match(bestDistance, bestLength));
        for (var i = 0; i < bestLength; i++) {
          _addLzPixelPosition(
            positionsByKey,
            pixels,
            position + i,
            localBits,
          );
        }
        position += bestLength;
      } else {
        pendingLiterals.add(pixels[position]);
        _addLzPixelPosition(positionsByKey, pixels, position, localBits);
        position++;
      }
    }
    flushLiterals();
    return tokens;
  }

  static int _lzPixelKey(List<int> pixels, int position, int localBits) {
    return (pixels[position] << (localBits * 2)) |
        (pixels[position + 1] << localBits) |
        pixels[position + 2];
  }

  static void _addLzPixelPosition(
    Map<int, List<int>> positionsByKey,
    List<int> pixels,
    int position,
    int localBits,
  ) {
    if (position + _minLzMatchLength > pixels.length) return;
    final positions = positionsByKey.putIfAbsent(
      _lzPixelKey(pixels, position, localBits),
      () => <int>[],
    );
    positions.add(position);
    if (positions.length > _maxLzMatchCandidates) {
      positions.removeAt(0);
    }
  }

  static int _compactUintBitLength(int value) {
    if (value < 0) {
      throw const MCOImageInvalidInputException('Negative compact uint');
    }
    if (value <= 3) return 3;
    if (value <= 19) return 6;
    if (value <= 275) return 11;
    return 3 + _bitVarUintBitLength(value);
  }

  static int _bitVarUintBitLength(int value) {
    if (value < 0) {
      throw const MCOImageInvalidInputException('Negative varuint');
    }
    var current = value;
    var bits = 0;
    do {
      current >>= 7;
      bits += 8;
    } while (current != 0);
    return bits;
  }

  static void _writeQuadtreeNode(
    _V3BitWriter writer,
    List<int> pixels,
    int stride,
    int x,
    int y,
    int width,
    int height,
    int localBits,
  ) {
    final firstColor = pixels[y * stride + x];
    var isSolid = true;
    for (var dy = 0; dy < height && isSolid; dy++) {
      final rowStart = (y + dy) * stride + x;
      for (var dx = 0; dx < width; dx++) {
        if (pixels[rowStart + dx] != firstColor) {
          isSolid = false;
          break;
        }
      }
    }
    if (isSolid) {
      writer
        ..writeBits(1, 1)
        ..writeBits(firstColor, localBits);
      return;
    }

    writer.writeBits(0, 1);
    if (width == 1) {
      final topHeight = height ~/ 2;
      _writeQuadtreeNode(
        writer,
        pixels,
        stride,
        x,
        y,
        width,
        topHeight,
        localBits,
      );
      _writeQuadtreeNode(
        writer,
        pixels,
        stride,
        x,
        y + topHeight,
        width,
        height - topHeight,
        localBits,
      );
      return;
    }
    if (height == 1) {
      final leftWidth = width ~/ 2;
      _writeQuadtreeNode(
        writer,
        pixels,
        stride,
        x,
        y,
        leftWidth,
        height,
        localBits,
      );
      _writeQuadtreeNode(
        writer,
        pixels,
        stride,
        x + leftWidth,
        y,
        width - leftWidth,
        height,
        localBits,
      );
      return;
    }

    final leftWidth = width ~/ 2;
    final topHeight = height ~/ 2;
    _writeQuadtreeNode(
      writer,
      pixels,
      stride,
      x,
      y,
      leftWidth,
      topHeight,
      localBits,
    );
    _writeQuadtreeNode(
      writer,
      pixels,
      stride,
      x + leftWidth,
      y,
      width - leftWidth,
      topHeight,
      localBits,
    );
    _writeQuadtreeNode(
      writer,
      pixels,
      stride,
      x,
      y + topHeight,
      leftWidth,
      height - topHeight,
      localBits,
    );
    _writeQuadtreeNode(
      writer,
      pixels,
      stride,
      x + leftWidth,
      y + topHeight,
      width - leftWidth,
      height - topHeight,
      localBits,
    );
  }

  static void _readQuadtreeNode(
    _V3BitReader reader,
    List<int> pixels,
    int stride,
    int x,
    int y,
    int width,
    int height,
    List<int> palette,
    int localBits,
  ) {
    final isSolid = reader.readBits(1) != 0;
    if (isSolid) {
      final colorIndex = reader.readBits(localBits);
      if (colorIndex >= palette.length) {
        throw const MCOImageInvalidPayloadException(
          'Quadtree color index out of range',
        );
      }
      for (var dy = 0; dy < height; dy++) {
        final rowStart = (y + dy) * stride + x;
        for (var dx = 0; dx < width; dx++) {
          pixels[rowStart + dx] = palette[colorIndex];
        }
      }
      return;
    }
    if (width == 1 && height == 1) {
      throw const MCOImageInvalidPayloadException(
        'Quadtree splits a single pixel',
      );
    }

    if (width == 1) {
      final topHeight = height ~/ 2;
      _readQuadtreeNode(
        reader,
        pixels,
        stride,
        x,
        y,
        width,
        topHeight,
        palette,
        localBits,
      );
      _readQuadtreeNode(
        reader,
        pixels,
        stride,
        x,
        y + topHeight,
        width,
        height - topHeight,
        palette,
        localBits,
      );
      return;
    }
    if (height == 1) {
      final leftWidth = width ~/ 2;
      _readQuadtreeNode(
        reader,
        pixels,
        stride,
        x,
        y,
        leftWidth,
        height,
        palette,
        localBits,
      );
      _readQuadtreeNode(
        reader,
        pixels,
        stride,
        x + leftWidth,
        y,
        width - leftWidth,
        height,
        palette,
        localBits,
      );
      return;
    }

    final leftWidth = width ~/ 2;
    final topHeight = height ~/ 2;
    _readQuadtreeNode(
      reader,
      pixels,
      stride,
      x,
      y,
      leftWidth,
      topHeight,
      palette,
      localBits,
    );
    _readQuadtreeNode(
      reader,
      pixels,
      stride,
      x + leftWidth,
      y,
      width - leftWidth,
      topHeight,
      palette,
      localBits,
    );
    _readQuadtreeNode(
      reader,
      pixels,
      stride,
      x,
      y + topHeight,
      leftWidth,
      height - topHeight,
      palette,
      localBits,
    );
    _readQuadtreeNode(
      reader,
      pixels,
      stride,
      x + leftWidth,
      y + topHeight,
      width - leftWidth,
      height - topHeight,
      palette,
      localBits,
    );
  }

  static List<int> _localPalette(List<int> pixels) {
    final counts = <int, int>{};
    for (final pixel in pixels) {
      counts[pixel] = (counts[pixel] ?? 0) + 1;
    }
    final colors = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        if (byCount != 0) return byCount;
        return a.compareTo(b);
      });
    if (colors.isEmpty) {
      throw const MCOImageInvalidInputException('Empty local palette');
    }
    return colors;
  }

  static Map<int, int> _localIndexMap(List<int> colors) {
    return {for (var i = 0; i < colors.length; i++) colors[i]: i};
  }

  static List<_V3Run> _buildRuns(List<int> pixels) {
    if (pixels.isEmpty) return const <_V3Run>[];
    final runs = <_V3Run>[];
    var color = pixels.first;
    var length = 1;
    for (var i = 1; i < pixels.length; i++) {
      if (pixels[i] == color) {
        length++;
      } else {
        runs.add(_V3Run(color, length));
        color = pixels[i];
        length = 1;
      }
    }
    runs.add(_V3Run(color, length));
    return runs;
  }

  static List<_V3SparseSegment> _buildSparseSegments(
    List<int> pixels,
    int background,
  ) {
    final result = <_V3SparseSegment>[];
    var pos = 0;
    while (pos < pixels.length) {
      while (pos < pixels.length && pixels[pos] == background) {
        pos++;
      }
      if (pos >= pixels.length) break;
      final start = pos;
      final color = pixels[pos];
      while (pos < pixels.length && pixels[pos] == color) {
        pos++;
      }
      result.add(_V3SparseSegment(start, color, pos - start));
    }
    return result;
  }

  static int? _biColorForeground(List<int> pixels, int background) {
    int? foreground;
    for (final pixel in pixels) {
      if (pixel == background) continue;
      foreground ??= pixel;
      if (pixel != foreground) return null;
    }
    return foreground;
  }

  static void _writeRowRepeat(
    _V3BitWriter writer,
    List<int> localPixels,
    int rowLength,
    int localBits,
  ) {
    if (rowLength <= 0 || localPixels.length % rowLength != 0) {
      throw const MCOImageInvalidInputException('Invalid row-repeat geometry');
    }
    for (var x = 0; x < rowLength; x++) {
      writer.writeBits(localPixels[x], localBits);
    }
    final rows = localPixels.length ~/ rowLength;
    for (var row = 1; row < rows; row++) {
      final rowStart = row * rowLength;
      final previousStart = rowStart - rowLength;
      var same = true;
      for (var x = 0; x < rowLength; x++) {
        if (localPixels[rowStart + x] != localPixels[previousStart + x]) {
          same = false;
          break;
        }
      }
      writer.writeBits(same ? 1 : 0, 1);
      if (!same) {
        for (var x = 0; x < rowLength; x++) {
          writer.writeBits(localPixels[rowStart + x], localBits);
        }
      }
    }
  }

  static List<int> _readRowRepeat(
    _V3BitReader reader,
    int count,
    int rowLength,
    int localBits,
  ) {
    if (rowLength <= 0 || count % rowLength != 0) {
      throw const MCOImageInvalidPayloadException(
        'Invalid row-repeat geometry',
      );
    }
    final result = List<int>.filled(count, 0);
    for (var x = 0; x < rowLength; x++) {
      result[x] = reader.readBits(localBits);
    }
    final rows = count ~/ rowLength;
    for (var row = 1; row < rows; row++) {
      final rowStart = row * rowLength;
      final previousStart = rowStart - rowLength;
      if (reader.readBits(1) != 0) {
        for (var x = 0; x < rowLength; x++) {
          result[rowStart + x] = result[previousStart + x];
        }
      } else {
        for (var x = 0; x < rowLength; x++) {
          result[rowStart + x] = reader.readBits(localBits);
        }
      }
    }
    return result;
  }

  static void _writeLocalPalette(
    _V3BitWriter writer,
    PaletteProfile profile,
    List<int> colors,
  ) {
    writer.writeBitVarUint(colors.length);
    for (final color in colors) {
      _writeColorRef(writer, profile, color);
    }
  }

  static List<int> _readLocalPalette(
    _V3BitReader reader,
    PaletteProfile profile,
  ) {
    final length = reader.readBitVarUint();
    if (length <= 0 || length > _paletteSize(profile)) {
      throw const MCOImageInvalidPayloadException('Invalid local palette size');
    }
    final colors = <int>[];
    final seen = <int>{};
    for (var i = 0; i < length; i++) {
      final color = _readColorRef(reader, profile);
      if (!seen.add(color)) {
        throw const MCOImageInvalidPayloadException('Duplicate local color');
      }
      colors.add(color);
    }
    return colors;
  }

  static void _writeColorRef(
    _V3BitWriter writer,
    PaletteProfile profile,
    int color,
  ) {
    _validateColor(color, profile);
    if (profile.isDynamic) {
      writer.writeBits(
        MCOImageDynamicPalette.profileColorIdForGlobalIndex(profile, color)!,
        _globalBits(profile),
      );
    } else {
      writer.writeBits(color, _globalBits(profile));
    }
  }

  static int _readColorRef(_V3BitReader reader, PaletteProfile profile) {
    final colorRef = reader.readBits(_globalBits(profile));
    final color = profile.isDynamic
        ? MCOImageDynamicPalette.globalIndexForProfileColorId(profile, colorRef)
        : colorRef;
    _validateColor(color, profile, payload: true);
    return color;
  }

  static int _globalBits(PaletteProfile profile) {
    return switch (profile) {
      PaletteProfile.mono => 1,
      PaletteProfile.master4 => 2,
      PaletteProfile.master8 => 3,
      PaletteProfile.grayscale8 => 3,
      PaletteProfile.master16 => 4,
      PaletteProfile.grayscale16 => 4,
      PaletteProfile.master32 => 5,
      PaletteProfile.grayscale32 => 5,
      PaletteProfile.master64 => 6,
      PaletteProfile.dynamicGlobal8 => 3,
      PaletteProfile.dynamicGlobal16 => 4,
      PaletteProfile.dynamicGlobal32 => 5,
      PaletteProfile.dynamicGlobal64 => 6,
      PaletteProfile.dynamicGlobal128 => 7,
      PaletteProfile.dynamicGlobal256 => 8,
      PaletteProfile.dynamicGlobal512 => 9,
    };
  }

  static int _paletteSize(PaletteProfile profile) {
    return switch (profile) {
      PaletteProfile.mono => 2,
      PaletteProfile.master4 => 4,
      PaletteProfile.master8 => 8,
      PaletteProfile.grayscale8 => 8,
      PaletteProfile.master16 => 16,
      PaletteProfile.grayscale16 => 16,
      PaletteProfile.master32 => 32,
      PaletteProfile.grayscale32 => 32,
      PaletteProfile.master64 => 64,
      PaletteProfile.dynamicGlobal8 => 8,
      PaletteProfile.dynamicGlobal16 => 16,
      PaletteProfile.dynamicGlobal32 => 32,
      PaletteProfile.dynamicGlobal64 => 64,
      PaletteProfile.dynamicGlobal128 => 128,
      PaletteProfile.dynamicGlobal256 => 256,
      PaletteProfile.dynamicGlobal512 => 512,
    };
  }

  static int _profileId(PaletteProfile profile) => profile.index;

  static PaletteProfile _profileFromId(int id) {
    if (id < 0 || id >= PaletteProfile.values.length) {
      throw MCOImageInvalidPayloadException('Unknown MCOimg v3 profile $id');
    }
    return PaletteProfile.values[id];
  }

  static bool _isColorValid(int color, PaletteProfile profile) {
    if (profile.isDynamic) {
      return MCOImageDynamicPalette.profileColorIdForGlobalIndex(
            profile,
            color,
          ) !=
          null;
    }
    return color >= 0 && color < _paletteSize(profile);
  }

  static void _validateColor(
    int color,
    PaletteProfile profile, {
    bool payload = false,
  }) {
    if (_isColorValid(color, profile)) return;
    final message = 'Color $color is not available in ${profile.name}';
    if (payload) throw MCOImageInvalidPayloadException(message);
    throw MCOImageInvalidInputException(message);
  }

  static void _validateImage(MCOImage image) {
    _validateDimensions(image.width, image.height);
    if (image.pixels.length != image.width * image.height) {
      throw const MCOImageInvalidInputException('Invalid pixel count');
    }
    for (final pixel in image.pixels) {
      _validateColor(pixel, image.paletteProfile);
    }
    if (image.transparentColor != null) {
      _validateColor(image.transparentColor!, image.paletteProfile);
    }
  }

  static void _validateDimensions(
    int width,
    int height, {
    bool payload = false,
  }) {
    if (width >= _minSize &&
        height >= _minSize &&
        width <= _maxSize &&
        height <= _maxSize) {
      return;
    }
    const message = 'Image size must be 1..256 in both axes';
    if (payload) throw const MCOImageInvalidPayloadException(message);
    throw const MCOImageInvalidInputException(message);
  }

  static _V3Bounds? _boundsForBackground(MCOImage image, int backgroundColor) {
    var minX = image.width;
    var minY = image.height;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (image.pixels[y * image.width + x] == backgroundColor) continue;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
    }
    if (maxX < minX || maxY < minY) return null;
    return _V3Bounds(
      minX,
      minY,
      maxX - minX + 1,
      maxY - minY + 1,
    );
  }

  static List<_V3Bounds> _componentBoundsForBackground(
    MCOImage image,
    int backgroundColor,
  ) {
    final visited = List<bool>.filled(image.pixels.length, false);
    final regions = <_V3Bounds>[];
    for (var start = 0; start < image.pixels.length; start++) {
      if (visited[start] || image.pixels[start] == backgroundColor) continue;
      final queue = <int>[start];
      var read = 0;
      visited[start] = true;
      var minX = image.width;
      var minY = image.height;
      var maxX = -1;
      var maxY = -1;
      while (read < queue.length) {
        final index = queue[read++];
        final x = index % image.width;
        final y = index ~/ image.width;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
        void addNeighbor(int nx, int ny) {
          if (nx < 0 || ny < 0 || nx >= image.width || ny >= image.height) {
            return;
          }
          final neighbor = ny * image.width + nx;
          if (visited[neighbor] ||
              image.pixels[neighbor] == backgroundColor) {
            return;
          }
          visited[neighbor] = true;
          queue.add(neighbor);
        }

        addNeighbor(x - 1, y);
        addNeighbor(x + 1, y);
        addNeighbor(x, y - 1);
        addNeighbor(x, y + 1);
      }
      regions.add(
        _V3Bounds(
          minX,
          minY,
          maxX - minX + 1,
          maxY - minY + 1,
        ),
      );
    }
    regions.sort((a, b) {
      final byY = a.y.compareTo(b.y);
      if (byY != 0) return byY;
      return a.x.compareTo(b.x);
    });
    return regions;
  }

  static bool _regionsDoNotOverlap(List<_V3Bounds> regions) {
    for (var i = 0; i < regions.length; i++) {
      for (var j = i + 1; j < regions.length; j++) {
        if (_boundsOverlap(regions[i], regions[j])) return false;
      }
    }
    return true;
  }

  static bool _boundsOverlap(_V3Bounds a, _V3Bounds b) {
    return a.x < b.x + b.width &&
        a.x + a.width > b.x &&
        a.y < b.y + b.height &&
        a.y + a.height > b.y;
  }

  static void _writeRegionGeometry(
    _V3BitWriter writer,
    _V3Bounds bounds,
    int imageWidth,
    int imageHeight, {
    required bool compactGeometry,
  }) {
    final xBits = compactGeometry ? _geometryBits(imageWidth) : 8;
    final yBits = compactGeometry ? _geometryBits(imageHeight) : 8;
    writer
      ..writeBits(bounds.x, xBits)
      ..writeBits(bounds.y, yBits)
      ..writeBits(bounds.width - 1, xBits)
      ..writeBits(bounds.height - 1, yBits);
  }

  static _V3Bounds _readRegionGeometry(
    _V3BitReader reader,
    int imageWidth,
    int imageHeight, {
    required bool compactGeometry,
  }) {
    final xBits = compactGeometry ? _geometryBits(imageWidth) : 8;
    final yBits = compactGeometry ? _geometryBits(imageHeight) : 8;
    final x = reader.readBits(xBits);
    final y = reader.readBits(yBits);
    final width = reader.readBits(xBits) + 1;
    final height = reader.readBits(yBits) + 1;
    final bounds = _V3Bounds(x, y, width, height);
    if (x >= imageWidth ||
        y >= imageHeight ||
        x + width > imageWidth ||
        y + height > imageHeight) {
      throw const MCOImageInvalidPayloadException('Invalid v3 region');
    }
    return bounds;
  }

  static int _geometryBits(int size) {
    if (size <= 1) return 0;
    return (size - 1).bitLength;
  }

  static List<int> _extractBoundsPixels(MCOImage image, _V3Bounds bounds) {
    final result = <int>[];
    for (var y = 0; y < bounds.height; y++) {
      final start = (bounds.y + y) * image.width + bounds.x;
      result.addAll(
        image.pixels.getRange(start, start + bounds.width),
      );
    }
    return result;
  }

  static int _rowLengthForScan(ScanMode scan, int width, int height) {
    return switch (scan) {
      ScanMode.h || ScanMode.s => width,
      ScanMode.v || ScanMode.sv => height,
    };
  }

  static List<int> _toScanOrder(
    List<int> pixels,
    int width,
    int height,
    ScanMode scan,
  ) {
    final result = <int>[];
    switch (scan) {
      case ScanMode.h:
        return List<int>.of(pixels);
      case ScanMode.v:
        for (var x = 0; x < width; x++) {
          for (var y = 0; y < height; y++) {
            result.add(pixels[y * width + x]);
          }
        }
        return result;
      case ScanMode.s:
        for (var y = 0; y < height; y++) {
          if (y.isEven) {
            for (var x = 0; x < width; x++) {
              result.add(pixels[y * width + x]);
            }
          } else {
            for (var x = width - 1; x >= 0; x--) {
              result.add(pixels[y * width + x]);
            }
          }
        }
        return result;
      case ScanMode.sv:
        for (var x = 0; x < width; x++) {
          if (x.isEven) {
            for (var y = 0; y < height; y++) {
              result.add(pixels[y * width + x]);
            }
          } else {
            for (var y = height - 1; y >= 0; y--) {
              result.add(pixels[y * width + x]);
            }
          }
        }
        return result;
    }
  }

  static List<int> _fromScanOrder(
    List<int> linear,
    int width,
    int height,
    ScanMode scan,
  ) {
    final result = List<int>.filled(width * height, 0);
    var index = 0;
    switch (scan) {
      case ScanMode.h:
        return List<int>.of(linear);
      case ScanMode.v:
        for (var x = 0; x < width; x++) {
          for (var y = 0; y < height; y++) {
            result[y * width + x] = linear[index++];
          }
        }
        return result;
      case ScanMode.s:
        for (var y = 0; y < height; y++) {
          if (y.isEven) {
            for (var x = 0; x < width; x++) {
              result[y * width + x] = linear[index++];
            }
          } else {
            for (var x = width - 1; x >= 0; x--) {
              result[y * width + x] = linear[index++];
            }
          }
        }
        return result;
      case ScanMode.sv:
        for (var x = 0; x < width; x++) {
          if (x.isEven) {
            for (var y = 0; y < height; y++) {
              result[y * width + x] = linear[index++];
            }
          } else {
            for (var y = height - 1; y >= 0; y--) {
              result[y * width + x] = linear[index++];
            }
          }
        }
        return result;
    }
  }

  static int _localBits(int colorCount) {
    if (colorCount <= 1) return 0;
    return (colorCount - 1).bitLength;
  }
}

class _V3Run {
  final int color;
  final int length;

  const _V3Run(this.color, this.length);
}

class _V3SparseSegment {
  final int start;
  final int color;
  final int length;

  const _V3SparseSegment(this.start, this.color, this.length);
}

class _V3LzPixelToken {
  final List<int> literals;
  final int distance;
  final int length;

  const _V3LzPixelToken.literal(this.literals)
    : distance = 0,
      length = 0;

  const _V3LzPixelToken.match(this.distance, this.length)
    : literals = const <int>[];

  bool get isMatch => distance > 0;
}

class _V3Bounds {
  final int x;
  final int y;
  final int width;
  final int height;

  const _V3Bounds(this.x, this.y, this.width, this.height);
}

class _V3RegionBlock {
  final _V3Bounds bounds;
  final MCOImageV3BlockAlgorithm algorithm;
  final ScanMode scan;
  final List<int> linear;
  final int bitLength;

  const _V3RegionBlock({
    required this.bounds,
    required this.algorithm,
    required this.scan,
    required this.linear,
    required this.bitLength,
  });
}

class _V3BitWriter {
  final List<int> _bytes = <int>[];
  var _current = 0;
  var _bitOffset = 0;

  int get bitLength => _bytes.length * 8 + _bitOffset;

  void writeBits(int value, int bits) {
    if (bits < 0 || bits > 32) {
      throw const MCOImageInvalidInputException('Invalid bit length');
    }
    if (bits == 0) return;
    if (value < 0 || value >= (1 << bits)) {
      throw const MCOImageInvalidInputException('Value does not fit bits');
    }
    var remaining = bits;
    var shifted = value;
    while (remaining > 0) {
      final available = 8 - _bitOffset;
      final take = math.min(available, remaining);
      final mask = (1 << take) - 1;
      _current |= (shifted & mask) << _bitOffset;
      _bitOffset += take;
      shifted >>= take;
      remaining -= take;
      if (_bitOffset == 8) {
        _bytes.add(_current);
        _current = 0;
        _bitOffset = 0;
      }
    }
  }

  void writeAlignedByte(int value) {
    alignToByte();
    _bytes.add(value & 0xff);
  }

  void writeBitVarUint(int value) {
    if (value < 0) {
      throw const MCOImageInvalidInputException('Negative varuint');
    }
    var remaining = value;
    do {
      var byte = remaining & 0x7f;
      remaining >>= 7;
      if (remaining != 0) byte |= 0x80;
      writeBits(byte, 8);
    } while (remaining != 0);
  }

  void writeCompactUint(int value) {
    if (value < 0) {
      throw const MCOImageInvalidInputException('Negative compact uint');
    }
    if (value <= 3) {
      writeBits(0, 1);
      writeBits(value, 2);
    } else if (value <= 19) {
      writeBits(1, 2);
      writeBits(value - 4, 4);
    } else if (value <= 275) {
      writeBits(3, 3);
      writeBits(value - 20, 8);
    } else {
      writeBits(7, 3);
      writeBitVarUint(value);
    }
  }

  void alignToByte() {
    if (_bitOffset > 0) {
      _bytes.add(_current);
      _current = 0;
      _bitOffset = 0;
    }
  }

  Uint8List toBytes() {
    alignToByte();
    return Uint8List.fromList(_bytes);
  }
}

class _V3BitReader {
  final Uint8List _bytes;
  int byteIndex;
  var _bitOffset = 0;

  _V3BitReader(this._bytes, {this.byteIndex = 0});

  int readBits(int bits) {
    if (bits < 0 || bits > 32) {
      throw const MCOImageInvalidPayloadException('Invalid bit length');
    }
    var result = 0;
    var shift = 0;
    var remaining = bits;
    while (remaining > 0) {
      if (byteIndex >= _bytes.length) {
        throw const MCOImageInvalidPayloadException('Unexpected end of bits');
      }
      final available = 8 - _bitOffset;
      final take = math.min(available, remaining);
      final mask = (1 << take) - 1;
      result |= ((_bytes[byteIndex] >> _bitOffset) & mask) << shift;
      _bitOffset += take;
      if (_bitOffset == 8) {
        byteIndex++;
        _bitOffset = 0;
      }
      shift += take;
      remaining -= take;
    }
    return result;
  }

  int readBitVarUint() {
    var result = 0;
    var shift = 0;
    for (var i = 0; i < 5; i++) {
      final byte = readBits(8);
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return result;
      shift += 7;
    }
    throw const MCOImageInvalidPayloadException('Varuint is too long');
  }

  int readCompactUint() {
    if (readBits(1) == 0) return readBits(2);
    if (readBits(1) == 0) return readBits(4) + 4;
    if (readBits(1) == 0) return readBits(8) + 20;
    return readBitVarUint();
  }

  void finish() {
    if (_bitOffset != 0) {
      final unusedMask = 0xff << _bitOffset;
      if ((_bytes[byteIndex] & unusedMask) != 0) {
        throw const MCOImageInvalidPayloadException('Non-zero padding bits');
      }
      byteIndex++;
      _bitOffset = 0;
    }
    if (byteIndex != _bytes.length) {
      throw const MCOImageInvalidPayloadException('Trailing payload bytes');
    }
  }
}
