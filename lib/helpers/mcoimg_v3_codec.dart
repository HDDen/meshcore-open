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
  compactBlock,
  boundsBlock,
  compactBoundsBlock,
  regions,
  compactRegionsStream,
  solidBackground,
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
  adaptiveBitplanes,
  directGrayscaleBitplanes,
  directDynamicBitplanes,
  compactRowDelta,
  directGrayscaleRowDelta,
  directDynamicRowDelta,
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
  static const List<MCOImageV3BlockAlgorithm> _regionBlockAlgorithms = [
    MCOImageV3BlockAlgorithm.rawGlobal,
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.rleLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.quadtree,
    MCOImageV3BlockAlgorithm.bitplanes,
    MCOImageV3BlockAlgorithm.adaptiveBitplanes,
    MCOImageV3BlockAlgorithm.directGrayscaleBitplanes,
    MCOImageV3BlockAlgorithm.directDynamicBitplanes,
    MCOImageV3BlockAlgorithm.compactRowDelta,
    MCOImageV3BlockAlgorithm.directGrayscaleRowDelta,
    MCOImageV3BlockAlgorithm.directDynamicRowDelta,
    MCOImageV3BlockAlgorithm.rowRepeat,
    MCOImageV3BlockAlgorithm.sparseBackground,
    MCOImageV3BlockAlgorithm.compactSparse,
    MCOImageV3BlockAlgorithm.biColorMask,
  ];
  static const List<MCOImageV3BlockAlgorithm> _sharedPaletteRegionAlgorithms = [
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.rleLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.quadtree,
    MCOImageV3BlockAlgorithm.bitplanes,
    MCOImageV3BlockAlgorithm.adaptiveBitplanes,
    MCOImageV3BlockAlgorithm.compactRowDelta,
    MCOImageV3BlockAlgorithm.rowRepeat,
  ];
  static const int _compactRowDeltaOpBits = 3;
  static const int _compactRowDeltaOpRepeat = 0;
  static const int _compactRowDeltaOpRaw = 1;
  static const int _compactRowDeltaOpIndexed = 2;
  static const int _compactRowDeltaOpSameScalar = 3;
  static const int _compactRowDeltaOpSegments = 4;
  static const int _compactRowDeltaOpTrimmedMask = 5;
  static const int _compactRowDeltaOpPredicted = 7;
  static const int _rowDeltaPredictorLeft = 1;
  static const int _rowDeltaPredictorRight = 2;

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
    if (body.length < 4) {
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
    if (container == MCOImageV3Container.block &&
        _canUseCompactBlockHeader(algorithm)) {
      throw const MCOImageInvalidPayloadException(
        'Scan-independent v3 block must use compactBlock',
      );
    }
    if (container == MCOImageV3Container.compactBlock &&
        !_canUseCompactBlockHeader(algorithm)) {
      throw const MCOImageInvalidPayloadException(
        'compactBlock cannot be used with scan-dependent algorithms',
      );
    }
    if (container == MCOImageV3Container.solidBackground &&
        algorithm != MCOImageV3BlockAlgorithm.rawGlobal) {
      throw const MCOImageInvalidPayloadException(
        'solidBackground must use rawGlobal algorithm id',
      );
    }
    final hasScanByte = _containerHasScanByte(container, algorithm);
    if (hasScanByte && body.length < 5) {
      throw const MCOImageInvalidPayloadException(
        'MCOimg v3 payload too short',
      );
    }
    final scan = hasScanByte ? _scanFromId(body[4]) : ScanMode.h;
    final reader = _V3BitReader(body, byteIndex: hasScanByte ? 5 : 4);
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
      MCOImageV3Container.compactBlock => _fromScanOrder(
        _decodeBlockBody(
          reader,
          width,
          height,
          profile,
          algorithm,
          ScanMode.h,
        ),
        width,
        height,
        ScanMode.h,
      ),
      MCOImageV3Container.boundsBlock => _decodeBoundsBlockBody(
        reader,
        width,
        height,
        profile,
        algorithm,
        scan,
        compactGeometry: false,
      ),
      MCOImageV3Container.compactBoundsBlock => _decodeBoundsBlockBody(
        reader,
        width,
        height,
        profile,
        algorithm,
        hasScanByte ? scan : ScanMode.h,
        compactGeometry: true,
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
        commonBlockHeader: false,
        deltaGeometry: false,
      );
      if (compactRegionsCandidate != null) {
        candidates.add(compactRegionsCandidate);
      }
      final deltaCompactRegionsCandidate = _tryBuildRegionsCandidate(
        image,
        bg,
        compactGeometry: true,
        commonBlockHeader: false,
        deltaGeometry: true,
      );
      if (deltaCompactRegionsCandidate != null) {
        candidates.add(deltaCompactRegionsCandidate);
      }
      final commonCompactRegionsCandidate = _tryBuildRegionsCandidate(
        image,
        bg,
        compactGeometry: true,
        commonBlockHeader: true,
        deltaGeometry: false,
        sharedLocalPalette: false,
      );
      if (commonCompactRegionsCandidate != null) {
        candidates.add(commonCompactRegionsCandidate);
      }
      final sharedCompactRegionsCandidate = _tryBuildRegionsCandidate(
        image,
        bg,
        compactGeometry: true,
        commonBlockHeader: true,
        deltaGeometry: false,
        sharedLocalPalette: true,
      );
      if (sharedCompactRegionsCandidate != null) {
        candidates.add(sharedCompactRegionsCandidate);
      }
      final commonDeltaCompactRegionsCandidate = _tryBuildRegionsCandidate(
        image,
        bg,
        compactGeometry: true,
        commonBlockHeader: true,
        deltaGeometry: true,
        sharedLocalPalette: false,
      );
      if (commonDeltaCompactRegionsCandidate != null) {
        candidates.add(commonDeltaCompactRegionsCandidate);
      }
      final sharedDeltaCompactRegionsCandidate = _tryBuildRegionsCandidate(
        image,
        bg,
        compactGeometry: true,
        commonBlockHeader: true,
        deltaGeometry: true,
        sharedLocalPalette: true,
      );
      if (sharedDeltaCompactRegionsCandidate != null) {
        candidates.add(sharedDeltaCompactRegionsCandidate);
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
          MCOImageV3BlockAlgorithm.bitplanes,
          MCOImageV3BlockAlgorithm.adaptiveBitplanes,
          MCOImageV3BlockAlgorithm.directGrayscaleBitplanes,
          MCOImageV3BlockAlgorithm.directDynamicBitplanes,
          MCOImageV3BlockAlgorithm.compactRowDelta,
          MCOImageV3BlockAlgorithm.directGrayscaleRowDelta,
          MCOImageV3BlockAlgorithm.directDynamicRowDelta,
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
            compactGeometry: false,
          );
          if (candidate != null) candidates.add(candidate);
          final compactCandidate = _tryBuildBoundsBlockCandidate(
            image,
            bounds,
            linear,
            algorithm,
            scan,
            backgroundColor: bg,
            compactGeometry: true,
          );
          if (compactCandidate != null) candidates.add(compactCandidate);
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
        MCOImageV3BlockAlgorithm.bitplanes,
        MCOImageV3BlockAlgorithm.adaptiveBitplanes,
        MCOImageV3BlockAlgorithm.directGrayscaleBitplanes,
        MCOImageV3BlockAlgorithm.directDynamicBitplanes,
        MCOImageV3BlockAlgorithm.compactRowDelta,
        MCOImageV3BlockAlgorithm.directGrayscaleRowDelta,
        MCOImageV3BlockAlgorithm.directDynamicRowDelta,
        MCOImageV3BlockAlgorithm.rowRepeat,
      ]) {
        if (_canUseCompactBlockHeader(algorithm)) {
          if (scan != ScanMode.h) continue;
          final compactCandidate = _tryBuildCandidate(
            image,
            linear,
            algorithm,
            scan,
            backgroundColor: preferredBackground,
            compactHeader: true,
          );
          if (compactCandidate != null) candidates.add(compactCandidate);
          continue;
        }
        final candidate = _tryBuildCandidate(
          image,
          linear,
          algorithm,
          scan,
          backgroundColor: preferredBackground,
          compactHeader: false,
        );
        if (candidate != null) candidates.add(candidate);
      }
      for (final bg in backgroundCandidates) {
        for (final algorithm in const [
          MCOImageV3BlockAlgorithm.sparseBackground,
          MCOImageV3BlockAlgorithm.compactSparse,
          MCOImageV3BlockAlgorithm.biColorMask,
        ]) {
          if (_canUseCompactBlockHeader(algorithm)) {
            if (scan != ScanMode.h) continue;
            final compactCandidate = _tryBuildCandidate(
              image,
              linear,
              algorithm,
              scan,
              backgroundColor: bg,
              compactHeader: true,
            );
            if (compactCandidate != null) candidates.add(compactCandidate);
            continue;
          }
          final candidate = _tryBuildCandidate(
            image,
            linear,
            algorithm,
            scan,
            backgroundColor: bg,
            compactHeader: false,
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
      );
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
    bool commonBlockHeader = false,
    bool deltaGeometry = false,
    bool sharedLocalPalette = false,
  }) {
    final regions = _componentBoundsForBackground(image, backgroundColor);
    if (regions.length < 2 || regions.length > _maxRegions) return null;
    if (!_regionsDoNotOverlap(regions)) return null;
    if (commonBlockHeader && !compactGeometry) return null;
    if (deltaGeometry && !compactGeometry) return null;
    if (sharedLocalPalette && (!compactGeometry || !commonBlockHeader)) {
      return null;
    }

    final regionPlan = sharedLocalPalette
        ? _bestSharedLocalPaletteRegionPlan(image, regions, backgroundColor)
        : _V3RegionPlan(
            blocks: commonBlockHeader
                ? _bestCommonRegionBlocks(image, regions, backgroundColor)
                : _bestIndividualRegionBlocks(image, regions, backgroundColor),
          );
    final regionBlocks = regionPlan.blocks;
    if (regionBlocks == null) return null;

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
      if (compactGeometry) {
        writer.writeBits(commonBlockHeader ? 1 : 0, 1);
        writer.writeBits(deltaGeometry ? 1 : 0, 1);
        writer.writeBits(sharedLocalPalette ? 1 : 0, 1);
        if (commonBlockHeader) {
          final algorithm = regionBlocks.first.algorithm;
          writer.writeBits(algorithm.index, 5);
          if (!_canUseCompactBlockHeader(algorithm)) {
            writer.writeBits(regionBlocks.first.scan.index, 2);
          }
        }
        if (sharedLocalPalette) {
          _writeLocalPalette(
            writer,
            image.paletteProfile,
            regionPlan.sharedLocalPalette!,
          );
        }
      }
      _V3Bounds? previousBounds;
      for (var index = 0; index < regionBlocks.length; index++) {
        final block = regionBlocks[index];
        if (deltaGeometry && index > 0) {
          _writeDeltaRegionGeometry(writer, block.bounds, previousBounds!);
        } else {
          _writeRegionGeometry(
            writer,
            block.bounds,
            image.width,
            image.height,
            compactGeometry: compactGeometry,
          );
        }
        previousBounds = block.bounds;
        if (!commonBlockHeader) {
          writer.writeBits(block.algorithm.index, 5);
          if (!_canUseCompactBlockHeader(block.algorithm)) {
            writer.writeBits(block.scan.index, 2);
          }
        }
        if (sharedLocalPalette) {
          _writeBlockBodyWithSharedPalette(
            writer,
            block.linear,
            block.algorithm,
            regionPlan.sharedLocalPalette!,
            rowLength: _rowLengthForScan(
              block.scan,
              block.bounds.width,
              block.bounds.height,
            ),
          );
        } else {
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
      container: _regionsContainerName(
        container,
        commonBlockHeader: commonBlockHeader,
        deltaGeometry: deltaGeometry,
        sharedLocalPalette: sharedLocalPalette,
      ),
    );
  }

  List<_V3RegionBlock>? _bestIndividualRegionBlocks(
    MCOImage image,
    List<_V3Bounds> regions,
    int backgroundColor,
  ) {
    final regionBlocks = <_V3RegionBlock>[];
    for (final region in regions) {
      final block = _bestRegionBlock(image, region, backgroundColor);
      if (block == null) return null;
      regionBlocks.add(block);
    }
    return regionBlocks;
  }

  List<_V3RegionBlock>? _bestCommonRegionBlocks(
    MCOImage image,
    List<_V3Bounds> regions,
    int backgroundColor,
  ) {
    List<_V3RegionBlock>? bestBlocks;
    int? bestBits;
    MCOImageV3BlockAlgorithm? bestAlgorithm;
    for (final scan in ScanMode.values) {
      for (final algorithm in _regionBlockAlgorithms) {
        if (algorithm == MCOImageV3BlockAlgorithm.quadtree &&
            scan != ScanMode.h) {
          continue;
        }
        final blocks = <_V3RegionBlock>[];
        var totalBits = 0;
        var failed = false;
        for (final region in regions) {
          final block = _tryBuildRegionBlock(
            image,
            region,
            backgroundColor,
            algorithm,
            scan,
          );
          if (block == null) {
            failed = true;
            break;
          }
          blocks.add(block);
          totalBits += block.bitLength;
        }
        if (failed) continue;
        if (bestBits == null ||
            totalBits < bestBits ||
            totalBits == bestBits &&
                _modeTieRank(_imageModeForAlgorithm(algorithm)) <
                    _modeTieRank(_imageModeForAlgorithm(bestAlgorithm!))) {
          bestBits = totalBits;
          bestBlocks = blocks;
          bestAlgorithm = algorithm;
        }
      }
    }
    return bestBlocks;
  }

  _V3RegionPlan _bestSharedLocalPaletteRegionPlan(
    MCOImage image,
    List<_V3Bounds> regions,
    int backgroundColor,
  ) {
    final croppedByRegion = <_V3Bounds, List<int>>{};
    final allPixels = <int>[];
    for (final region in regions) {
      final cropped = _extractBoundsPixels(image, region);
      croppedByRegion[region] = cropped;
      allPixels.addAll(cropped);
    }
    final paletteVariants = _localPaletteVariants(
      allPixels,
      image.paletteProfile,
      includeTransitionOrder: true,
    );

    List<_V3RegionBlock>? bestBlocks;
    List<int>? bestPalette;
    int? bestBits;
    MCOImageV3BlockAlgorithm? bestAlgorithm;
    for (final scan in ScanMode.values) {
      for (final algorithm in _sharedPaletteRegionAlgorithms) {
        if (algorithm == MCOImageV3BlockAlgorithm.quadtree &&
            scan != ScanMode.h) {
          continue;
        }
        for (final palette in paletteVariants) {
          final paletteWriter = _V3BitWriter();
          _writeLocalPalette(paletteWriter, image.paletteProfile, palette);
          var totalBits = paletteWriter.bitLength;
          final blocks = <_V3RegionBlock>[];
          var failed = false;
          for (final region in regions) {
            final block = _tryBuildSharedPaletteRegionBlock(
              image,
              region,
              croppedByRegion[region]!,
              backgroundColor,
              algorithm,
              scan,
              palette,
            );
            if (block == null) {
              failed = true;
              break;
            }
            blocks.add(block);
            totalBits += block.bitLength;
          }
          if (failed) continue;
          if (bestBits == null ||
              totalBits < bestBits ||
              totalBits == bestBits &&
                  _modeTieRank(_imageModeForAlgorithm(algorithm)) <
                      _modeTieRank(_imageModeForAlgorithm(bestAlgorithm!))) {
            bestBits = totalBits;
            bestBlocks = blocks;
            bestPalette = palette;
            bestAlgorithm = algorithm;
          }
        }
      }
    }
    return _V3RegionPlan(
      blocks: bestBlocks,
      sharedLocalPalette: bestPalette,
    );
  }

  _V3RegionBlock? _bestRegionBlock(
    MCOImage image,
    _V3Bounds bounds,
    int backgroundColor,
  ) {
    _V3RegionBlock? best;
    for (final scan in ScanMode.values) {
      for (final algorithm in _regionBlockAlgorithms) {
        if (algorithm == MCOImageV3BlockAlgorithm.quadtree &&
            scan != ScanMode.h) {
          continue;
        }
        final block = _tryBuildRegionBlock(
          image,
          bounds,
          backgroundColor,
          algorithm,
          scan,
        );
        if (block == null) continue;
        if (best == null ||
            block.bitLength < best.bitLength ||
            block.bitLength == best.bitLength &&
                _modeTieRank(_imageModeForAlgorithm(algorithm)) <
                    _modeTieRank(_imageModeForAlgorithm(best.algorithm))) {
          best = block;
        }
      }
    }
    return best;
  }

  _V3RegionBlock? _tryBuildRegionBlock(
    MCOImage image,
    _V3Bounds bounds,
    int backgroundColor,
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan,
  ) {
    final cropped = _extractBoundsPixels(image, bounds);
    final linear = _toScanOrder(cropped, bounds.width, bounds.height, scan);
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
      return null;
    }
    final bits = writer.bitLength;
    if (bits == 0) return null;
    return _V3RegionBlock(
      bounds: bounds,
      algorithm: algorithm,
      scan: scan,
      linear: linear,
      bitLength: bits,
    );
  }

  _V3RegionBlock? _tryBuildSharedPaletteRegionBlock(
    MCOImage image,
    _V3Bounds bounds,
    List<int> cropped,
    int backgroundColor,
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan,
    List<int> palette,
  ) {
    final linear = _toScanOrder(cropped, bounds.width, bounds.height, scan);
    final writer = _V3BitWriter();
    try {
      _writeBlockBodyWithSharedPalette(
        writer,
        linear,
        algorithm,
        palette,
        rowLength: _rowLengthForScan(scan, bounds.width, bounds.height),
      );
    } on MCOImageCodecException {
      return null;
    }
    final bits = writer.bitLength;
    if (bits == 0) return null;
    return _V3RegionBlock(
      bounds: bounds,
      algorithm: algorithm,
      scan: scan,
      linear: linear,
      bitLength: bits,
    );
  }

  EncodedMCOImage? _tryBuildBoundsBlockCandidate(
    MCOImage image,
    _V3Bounds bounds,
    List<int> linear,
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan, {
    required int backgroundColor,
    required bool compactGeometry,
  }) {
    final writer = _V3BitWriter();
    if (compactGeometry &&
        _canUseCompactBlockHeader(algorithm) &&
        scan != ScanMode.h) {
      return null;
    }
    if (algorithm == MCOImageV3BlockAlgorithm.quadtree &&
        scan != ScanMode.h) {
      return null;
    }
    writer.writeAlignedByte(
      _formatMarker |
          (image.transparentColor != null ? _transparentFlag : 0) |
          _profileId(image.paletteProfile),
    );
    final container = compactGeometry
        ? MCOImageV3Container.compactBoundsBlock
        : MCOImageV3Container.boundsBlock;
    writer
      ..writeAlignedByte(image.width - 1)
      ..writeAlignedByte(image.height - 1)
      ..writeAlignedByte(_containerAlgorithmByte(container, algorithm));
    if (_containerHasScanByte(container, algorithm)) {
      writer.writeAlignedByte(scan.index);
    }
    if (image.transparentColor != null) {
      _writeColorRef(writer, image.paletteProfile, image.transparentColor!);
    }

    final bodyStartBits = writer.bitLength;
    try {
      _writeColorRef(writer, image.paletteProfile, backgroundColor);
      _writeBoundsGeometry(
        writer,
        bounds,
        image.width,
        image.height,
        compactGeometry: compactGeometry,
      );
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
    bool compactHeader = false,
  }) {
    if (compactHeader &&
        (scan != ScanMode.h || !_canUseCompactBlockHeader(algorithm))) {
      return null;
    }
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
    final container = compactHeader
        ? MCOImageV3Container.compactBlock
        : MCOImageV3Container.block;
    writer
      ..writeAlignedByte(image.width - 1)
      ..writeAlignedByte(image.height - 1)
      ..writeAlignedByte(_containerAlgorithmByte(container, algorithm));
    if (!compactHeader) {
      writer.writeAlignedByte(scan.index);
    }
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
    ScanMode scan, {
    required bool compactGeometry,
  }) {
    final background = _readColorRef(reader, profile);
    final bounds = _readBoundsGeometry(
      reader,
      width,
      height,
      compactGeometry: compactGeometry,
    );
    final croppedLinear = _decodeBlockBody(
      reader,
      bounds.width,
      bounds.height,
      profile,
      algorithm,
      scan,
    );
    final cropped = _fromScanOrder(
      croppedLinear,
      bounds.width,
      bounds.height,
      scan,
    );
    final pixels = List<int>.filled(width * height, background);
    for (var row = 0; row < bounds.height; row++) {
      final srcStart = row * bounds.width;
      final dstStart = (bounds.y + row) * width + bounds.x;
      for (var col = 0; col < bounds.width; col++) {
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
    final hasCommonBlockHeader =
        compactGeometry && reader.readBits(1) != 0;
    final hasDeltaGeometry = compactGeometry && reader.readBits(1) != 0;
    final hasSharedLocalPalette =
        compactGeometry && reader.readBits(1) != 0;
    if (hasSharedLocalPalette && !hasCommonBlockHeader) {
      throw const MCOImageInvalidPayloadException(
        'Shared region palette requires common region block header',
      );
    }
    final commonAlgorithm =
        hasCommonBlockHeader ? _algorithmFromId(reader.readBits(5)) : null;
    final commonScan = commonAlgorithm == null
        ? null
        : _canUseCompactBlockHeader(commonAlgorithm)
            ? ScanMode.h
            : _scanFromId(reader.readBits(2));
    final sharedLocalPalette = hasSharedLocalPalette
        ? _readLocalPalette(reader, profile)
        : null;
    final pixels = List<int>.filled(width * height, background);
    _V3Bounds? previousBounds;
    for (var i = 0; i < regionCount; i++) {
      final bounds = hasDeltaGeometry && i > 0
          ? _readDeltaRegionGeometry(
              reader,
              previousBounds!,
              width,
              height,
            )
          : _readRegionGeometry(
              reader,
              width,
              height,
              compactGeometry: compactGeometry,
            );
      previousBounds = bounds;
      final algorithm =
          commonAlgorithm ?? _algorithmFromId(reader.readBits(5));
      final scan = commonScan ??
          (_canUseCompactBlockHeader(algorithm)
              ? ScanMode.h
              : _scanFromId(reader.readBits(2)));
      final linear = sharedLocalPalette == null
          ? _decodeBlockBody(
              reader,
              bounds.width,
              bounds.height,
              profile,
              algorithm,
              scan,
            )
          : _decodeBlockBodyWithSharedPalette(
              reader,
              bounds.width,
              bounds.height,
              algorithm,
              scan,
              sharedLocalPalette,
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
      case MCOImageV3BlockAlgorithm.bitplanes:
        final palette = _localPalette(linear);
        _writeLocalPalette(writer, profile, palette);
        final map = _localIndexMap(palette);
        final bits = _localBits(palette.length);
        final localPixels = linear.map((color) => map[color]!).toList();
        for (var bit = 0; bit < bits; bit++) {
          final runs = _buildBitplaneRuns(localPixels, bit);
          final rleBits = 2 + runs.fold<int>(
            0,
            (sum, length) => sum + _compactUintBitLength(length - 1),
          );
          final rawBits = 1 + localPixels.length;
          if (rleBits < rawBits) {
            writer
              ..writeBits(1, 1)
              ..writeBits((localPixels.first >> bit) & 1, 1);
            for (final length in runs) {
              writer.writeCompactUint(length - 1);
            }
          } else {
            writer.writeBits(0, 1);
            for (final pixel in localPixels) {
              writer.writeBits((pixel >> bit) & 1, 1);
            }
          }
        }
        break;
      case MCOImageV3BlockAlgorithm.adaptiveBitplanes:
        _writeBestLocalPaletteBlock(
          writer,
          linear,
          profile,
          includeTransitionOrder: true,
          writeBody: _writeAdaptiveBitplanesLocalBody,
        );
        break;
      case MCOImageV3BlockAlgorithm.directGrayscaleBitplanes:
        if (!_isGrayscaleProfile(profile)) {
          throw const MCOImageInvalidInputException(
            'Direct grayscale bitplanes require a grayscale profile',
          );
        }
        _writeAdaptiveBitplanesBody(writer, linear, _globalBits(profile));
        break;
      case MCOImageV3BlockAlgorithm.directDynamicBitplanes:
        if (!profile.isDynamic) {
          throw const MCOImageInvalidInputException(
            'Direct dynamic bitplanes require a dynamic profile',
          );
        }
        _writeAdaptiveBitplanesBody(
          writer,
          _dynamicProfilePixels(profile, linear),
          _globalBits(profile),
        );
        break;
      case MCOImageV3BlockAlgorithm.compactRowDelta:
        _writeBestLocalPaletteBlock(
          writer,
          linear,
          profile,
          includeTransitionOrder: true,
          writeBody: (
            bodyWriter,
            localPixels,
            bits,
          ) {
            _writeCompactRowDeltaBody(
              bodyWriter,
              localPixels,
              rowLength,
              bits,
            );
          },
        );
        break;
      case MCOImageV3BlockAlgorithm.directGrayscaleRowDelta:
        if (!_isGrayscaleProfile(profile)) {
          throw const MCOImageInvalidInputException(
            'Direct grayscale row-delta requires a grayscale profile',
          );
        }
        _writeCompactRowDeltaBody(
          writer,
          linear,
          rowLength,
          _globalBits(profile),
        );
        break;
      case MCOImageV3BlockAlgorithm.directDynamicRowDelta:
        if (!profile.isDynamic) {
          throw const MCOImageInvalidInputException(
            'Direct dynamic row-delta requires a dynamic profile',
          );
        }
        _writeCompactRowDeltaBody(
          writer,
          _dynamicProfilePixels(profile, linear),
          rowLength,
          _globalBits(profile),
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
      case MCOImageV3BlockAlgorithm.wrappedBlock:
        throw const MCOImageInvalidInputException(
          'MCOimg v3 algorithm is not implemented yet',
        );
    }
  }

  void _writeBlockBodyWithSharedPalette(
    _V3BitWriter writer,
    List<int> linear,
    MCOImageV3BlockAlgorithm algorithm,
    List<int> palette, {
    required int rowLength,
  }) {
    final map = _localIndexMap(palette);
    final bits = _localBits(palette.length);
    List<int> localPixels() {
      return linear.map((color) {
        final index = map[color];
        if (index == null) {
          throw const MCOImageInvalidInputException(
            'Shared region palette is missing a color',
          );
        }
        return index;
      }).toList(growable: false);
    }

    switch (algorithm) {
      case MCOImageV3BlockAlgorithm.rawLocal:
        for (final color in linear) {
          writer.writeBits(map[color]!, bits);
        }
        break;
      case MCOImageV3BlockAlgorithm.rleLocal:
        final runs = _buildRuns(linear);
        writer.writeBitVarUint(runs.length);
        for (final run in runs) {
          writer
            ..writeBits(map[run.color]!, bits)
            ..writeBitVarUint(run.length);
        }
        break;
      case MCOImageV3BlockAlgorithm.compactRle:
        for (final run in _buildRuns(linear)) {
          writer
            ..writeBits(map[run.color]!, bits)
            ..writeCompactUint(run.length - 1);
        }
        break;
      case MCOImageV3BlockAlgorithm.lzPixels:
        final pixels = localPixels();
        final tokens = _buildGreedyLzPixelTokens(pixels, bits);
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
        _writeQuadtreeNode(
          writer,
          localPixels(),
          rowLength,
          0,
          0,
          rowLength,
          linear.length ~/ rowLength,
          bits,
        );
        break;
      case MCOImageV3BlockAlgorithm.bitplanes:
        final pixels = localPixels();
        for (var bit = 0; bit < bits; bit++) {
          final runs = _buildBitplaneRuns(pixels, bit);
          final rleBits = 2 + runs.fold<int>(
            0,
            (sum, length) => sum + _compactUintBitLength(length - 1),
          );
          final rawBits = 1 + pixels.length;
          if (rleBits < rawBits) {
            writer
              ..writeBits(1, 1)
              ..writeBits((pixels.first >> bit) & 1, 1);
            for (final length in runs) {
              writer.writeCompactUint(length - 1);
            }
          } else {
            writer.writeBits(0, 1);
            for (final pixel in pixels) {
              writer.writeBits((pixel >> bit) & 1, 1);
            }
          }
        }
        break;
      case MCOImageV3BlockAlgorithm.adaptiveBitplanes:
        _writeAdaptiveBitplanesBody(writer, localPixels(), bits);
        break;
      case MCOImageV3BlockAlgorithm.compactRowDelta:
        _writeCompactRowDeltaBody(
          writer,
          localPixels(),
          rowLength,
          bits,
        );
        break;
      case MCOImageV3BlockAlgorithm.rowRepeat:
        _writeRowRepeat(writer, localPixels(), rowLength, bits);
        break;
      default:
        throw const MCOImageInvalidInputException(
          'MCOimg v3 algorithm cannot use a shared region palette',
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
      case MCOImageV3BlockAlgorithm.bitplanes:
        final palette = _readLocalPalette(reader, profile);
        final bits = _localBits(palette.length);
        final localPixels = List<int>.filled(count, 0);
        for (var bit = 0; bit < bits; bit++) {
          final isRle = reader.readBits(1) != 0;
          if (!isRle) {
            for (var i = 0; i < count; i++) {
              localPixels[i] |= reader.readBits(1) << bit;
            }
            continue;
          }

          var value = reader.readBits(1);
          var position = 0;
          while (position < count) {
            final length = reader.readCompactUint() + 1;
            if (position + length > count) {
              throw const MCOImageInvalidPayloadException(
                'Bitplane RLE exceeds pixel count',
              );
            }
            if (value != 0) {
              for (var i = 0; i < length; i++) {
                localPixels[position + i] |= 1 << bit;
              }
            }
            position += length;
            value ^= 1;
          }
        }
        return localPixels.map((index) {
          if (index >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'Bitplane color index out of range',
            );
          }
          return palette[index];
        }).toList(growable: false);
      case MCOImageV3BlockAlgorithm.adaptiveBitplanes:
        final palette = _readLocalPalette(reader, profile);
        return _decodeAdaptiveBitplanesBody(reader, count, palette);
      case MCOImageV3BlockAlgorithm.directGrayscaleBitplanes:
        if (!_isGrayscaleProfile(profile)) {
          throw const MCOImageInvalidPayloadException(
            'Direct grayscale bitplanes require a grayscale profile',
          );
        }
        return _decodeAdaptiveBitplanesBody(
          reader,
          count,
          List<int>.generate(_paletteSize(profile), (index) => index),
        );
      case MCOImageV3BlockAlgorithm.directDynamicBitplanes:
        if (!profile.isDynamic) {
          throw const MCOImageInvalidPayloadException(
            'Direct dynamic bitplanes require a dynamic profile',
          );
        }
        return _decodeAdaptiveBitplanesBody(
          reader,
          count,
          _dynamicProfilePalette(profile),
        );
      case MCOImageV3BlockAlgorithm.compactRowDelta:
        final palette = _readLocalPalette(reader, profile);
        final bits = _localBits(palette.length);
        final localPixels = _readCompactRowDeltaBody(
          reader,
          count,
          _rowLengthForScan(scan, width, height),
          bits,
          maxValue: palette.length - 1,
        );
        return localPixels.map((index) {
          if (index >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'Compact row-delta color index out of range',
            );
          }
          return palette[index];
        }).toList(growable: false);
      case MCOImageV3BlockAlgorithm.directGrayscaleRowDelta:
        if (!_isGrayscaleProfile(profile)) {
          throw const MCOImageInvalidPayloadException(
            'Direct grayscale row-delta requires a grayscale profile',
          );
        }
        return _readCompactRowDeltaBody(
          reader,
          count,
          _rowLengthForScan(scan, width, height),
          _globalBits(profile),
          maxValue: _paletteSize(profile) - 1,
        );
      case MCOImageV3BlockAlgorithm.directDynamicRowDelta:
        if (!profile.isDynamic) {
          throw const MCOImageInvalidPayloadException(
            'Direct dynamic row-delta requires a dynamic profile',
          );
        }
        final profilePixels = _readCompactRowDeltaBody(
          reader,
          count,
          _rowLengthForScan(scan, width, height),
          _globalBits(profile),
          maxValue: _paletteSize(profile) - 1,
        );
        final palette = _dynamicProfilePalette(profile);
        return profilePixels.map((index) => palette[index]).toList(
              growable: false,
            );
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
      case MCOImageV3BlockAlgorithm.wrappedBlock:
        throw const MCOImageInvalidPayloadException(
          'Unsupported MCOimg v3 algorithm',
        );
    }
  }

  List<int> _decodeBlockBodyWithSharedPalette(
    _V3BitReader reader,
    int width,
    int height,
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan,
    List<int> palette,
  ) {
    final count = width * height;
    final bits = _localBits(palette.length);
    List<int> mapLocalPixels(List<int> localPixels) {
      return localPixels.map((index) {
        if (index >= palette.length) {
          throw const MCOImageInvalidPayloadException(
            'Shared palette color index out of range',
          );
        }
        return palette[index];
      }).toList(growable: false);
    }

    switch (algorithm) {
      case MCOImageV3BlockAlgorithm.rawLocal:
        return mapLocalPixels(
          List<int>.generate(count, (_) => reader.readBits(bits)),
        );
      case MCOImageV3BlockAlgorithm.rleLocal:
        final result = <int>[];
        final runCount = reader.readBitVarUint();
        for (var i = 0; i < runCount; i++) {
          final colorIndex = reader.readBits(bits);
          if (colorIndex >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'RLE shared palette index out of range',
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
        final result = <int>[];
        while (result.length < count) {
          final colorIndex = reader.readBits(bits);
          if (colorIndex >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'Compact RLE shared palette index out of range',
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
                  'LZ shared palette index out of range',
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
          bits,
        );
        return result;
      case MCOImageV3BlockAlgorithm.bitplanes:
        final localPixels = List<int>.filled(count, 0);
        for (var bit = 0; bit < bits; bit++) {
          final isRle = reader.readBits(1) != 0;
          if (!isRle) {
            for (var i = 0; i < count; i++) {
              localPixels[i] |= reader.readBits(1) << bit;
            }
            continue;
          }
          var value = reader.readBits(1);
          var position = 0;
          while (position < count) {
            final length = reader.readCompactUint() + 1;
            if (position + length > count) {
              throw const MCOImageInvalidPayloadException(
                'Bitplane RLE exceeds pixel count',
              );
            }
            if (value != 0) {
              for (var i = 0; i < length; i++) {
                localPixels[position + i] |= 1 << bit;
              }
            }
            position += length;
            value ^= 1;
          }
        }
        return mapLocalPixels(localPixels);
      case MCOImageV3BlockAlgorithm.adaptiveBitplanes:
        return _decodeAdaptiveBitplanesBody(reader, count, palette);
      case MCOImageV3BlockAlgorithm.compactRowDelta:
        return mapLocalPixels(
          _readCompactRowDeltaBody(
            reader,
            count,
            _rowLengthForScan(scan, width, height),
            bits,
            maxValue: palette.length - 1,
          ),
        );
      case MCOImageV3BlockAlgorithm.rowRepeat:
        return mapLocalPixels(_readRowRepeat(reader, count, width, bits));
      default:
        throw const MCOImageInvalidPayloadException(
          'MCOimg v3 algorithm cannot use a shared region palette',
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

  static bool _canUseCompactBlockHeader(
    MCOImageV3BlockAlgorithm algorithm,
  ) {
    return switch (algorithm) {
      MCOImageV3BlockAlgorithm.rawGlobal ||
      MCOImageV3BlockAlgorithm.rawLocal ||
      MCOImageV3BlockAlgorithm.biColorMask => true,
      _ => false,
    };
  }

  static bool _containerHasScanByte(
    MCOImageV3Container container,
    MCOImageV3BlockAlgorithm algorithm,
  ) {
    return switch (container) {
      MCOImageV3Container.compactBlock => false,
      MCOImageV3Container.solidBackground => false,
      MCOImageV3Container.compactBoundsBlock =>
        !_canUseCompactBlockHeader(algorithm),
      _ => true,
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
      MCOImageV3BlockAlgorithm.bitplanes ||
      MCOImageV3BlockAlgorithm.adaptiveBitplanes ||
      MCOImageV3BlockAlgorithm.compactRowDelta ||
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

  static void _writeBestLocalPaletteBlock(
    _V3BitWriter writer,
    List<int> linear,
    PaletteProfile profile, {
    required bool includeTransitionOrder,
    required void Function(
      _V3BitWriter writer,
      List<int> localPixels,
      int bits,
    ) writeBody,
  }) {
    final variants = _localPaletteVariants(
      linear,
      profile,
      includeTransitionOrder: includeTransitionOrder,
    );
    _V3LocalPaletteEncoding? best;
    for (final palette in variants) {
      final candidate = _encodeLocalPaletteBlock(
        linear,
        profile,
        palette,
        writeBody,
      );
      if (best == null || candidate.bitLength < best.bitLength) {
        best = candidate;
      }
    }
    if (best == null) {
      throw const MCOImageInvalidInputException('Empty local palette');
    }
    _writeLocalPalette(writer, profile, best.palette);
    writeBody(writer, best.localPixels, best.bits);
  }

  static _V3LocalPaletteEncoding _encodeLocalPaletteBlock(
    List<int> linear,
    PaletteProfile profile,
    List<int> palette,
    void Function(
      _V3BitWriter writer,
      List<int> localPixels,
      int bits,
    ) writeBody,
  ) {
    final map = _localIndexMap(palette);
    final bits = _localBits(palette.length);
    final localPixels = linear.map((color) => map[color]!).toList();
    final writer = _V3BitWriter();
    _writeLocalPalette(writer, profile, palette);
    writeBody(writer, localPixels, bits);
    return _V3LocalPaletteEncoding(
      palette: palette,
      localPixels: localPixels,
      bits: bits,
      bitLength: writer.bitLength,
    );
  }

  static List<List<int>> _localPaletteVariants(
    List<int> pixels,
    PaletteProfile profile, {
    required bool includeTransitionOrder,
  }) {
    final variants = <List<int>>[];
    final seen = <String>{};
    void add(List<int> palette) {
      if (palette.isEmpty) return;
      final key = palette.join(',');
      if (seen.add(key)) variants.add(palette);
    }

    add(_localPalette(pixels));
    add(_firstUseLocalPalette(pixels));
    add(_profileOrderLocalPalette(pixels, profile));
    if (includeTransitionOrder) {
      final transitionPalette = _transitionLocalPalette(pixels);
      if (transitionPalette != null) add(transitionPalette);
    }
    return variants;
  }

  static List<int> _firstUseLocalPalette(List<int> pixels) {
    final seen = <int>{};
    final palette = <int>[];
    for (final pixel in pixels) {
      if (seen.add(pixel)) palette.add(pixel);
    }
    return palette;
  }

  static List<int> _profileOrderLocalPalette(
    List<int> pixels,
    PaletteProfile profile,
  ) {
    final colors = pixels.toSet().toList();
    colors.sort((a, b) {
      final aRef = _profileOrderColorRef(profile, a);
      final bRef = _profileOrderColorRef(profile, b);
      final byRef = aRef.compareTo(bRef);
      return byRef != 0 ? byRef : a.compareTo(b);
    });
    return colors;
  }

  static int _profileOrderColorRef(PaletteProfile profile, int color) {
    if (!profile.isDynamic) return color;
    return MCOImageDynamicPalette.profileColorIdForGlobalIndex(
          profile,
          color,
        ) ??
        color;
  }

  static List<int>? _transitionLocalPalette(List<int> pixels) {
    final colors = pixels.toSet().toList();
    if (colors.length < 2 || colors.length > 64) return null;

    final counts = <int, int>{};
    final edgeWeights = <int, Map<int, int>>{};
    for (final pixel in pixels) {
      counts[pixel] = (counts[pixel] ?? 0) + 1;
    }
    for (var i = 1; i < pixels.length; i++) {
      final a = pixels[i - 1];
      final b = pixels[i];
      if (a == b) continue;
      edgeWeights.putIfAbsent(a, () => <int, int>{});
      edgeWeights.putIfAbsent(b, () => <int, int>{});
      edgeWeights[a]![b] = (edgeWeights[a]![b] ?? 0) + 1;
      edgeWeights[b]![a] = (edgeWeights[b]![a] ?? 0) + 1;
    }

    colors.sort((a, b) {
      final byCount = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
    final remaining = colors.toSet();
    final palette = <int>[colors.first];
    remaining.remove(colors.first);
    while (remaining.isNotEmpty) {
      final previous = palette.last;
      var best = remaining.first;
      var bestWeight = edgeWeights[previous]?[best] ?? 0;
      for (final color in remaining.skip(1)) {
        final weight = edgeWeights[previous]?[color] ?? 0;
        if (_isBetterTransitionPaletteColor(
          color,
          weight,
          best,
          bestWeight,
          counts,
        )) {
          best = color;
          bestWeight = weight;
        }
      }
      palette.add(best);
      remaining.remove(best);
    }
    return palette;
  }

  static bool _isBetterTransitionPaletteColor(
    int color,
    int weight,
    int best,
    int bestWeight,
    Map<int, int> counts,
  ) {
    if (weight != bestWeight) return weight > bestWeight;
    final count = counts[color] ?? 0;
    final bestCount = counts[best] ?? 0;
    if (count != bestCount) return count > bestCount;
    return color < best;
  }

  static void _writeAdaptiveBitplanesLocalBody(
    _V3BitWriter writer,
    List<int> localPixels,
    int bits,
  ) {
    _writeAdaptiveBitplanesBody(writer, localPixels, bits);
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

  static List<int> _buildBitplaneRuns(List<int> pixels, int bit) {
    if (pixels.isEmpty) return const <int>[];
    final runs = <int>[];
    var current = (pixels.first >> bit) & 1;
    var length = 1;
    for (var i = 1; i < pixels.length; i++) {
      final value = (pixels[i] >> bit) & 1;
      if (value == current) {
        length++;
      } else {
        runs.add(length);
        current = value;
        length = 1;
      }
    }
    runs.add(length);
    return runs;
  }

  static void _writeAdaptiveBitplanesBody(
    _V3BitWriter writer,
    List<int> pixels,
    int bitCount,
  ) {
    for (var bit = 0; bit < bitCount; bit++) {
      final decision = _chooseAdaptiveBitplaneEncoding(pixels, bit);
      switch (decision.mode) {
        case _V3AdaptiveBitplaneMode.raw:
          writer.writeBits(0, 1);
          for (final pixel in pixels) {
            writer.writeBits((pixel >> bit) & 1, 1);
          }
          break;
        case _V3AdaptiveBitplaneMode.legacyRle:
          writer
            ..writeBits(1, 2)
            ..writeBits(decision.startingBit, 1);
          for (final length in decision.runs) {
            writer.writeCompactUint(length - 1);
          }
          break;
        case _V3AdaptiveBitplaneMode.shortRle:
          writer
            ..writeBits(3, 3)
            ..writeBits(decision.startingBit, 1);
          for (final length in decision.runs) {
            _writeShortBitplaneRunLength(writer, length);
          }
          break;
        case _V3AdaptiveBitplaneMode.constantZero:
          writer.writeBits(7, 5);
          break;
        case _V3AdaptiveBitplaneMode.constantOne:
          writer.writeBits(15, 5);
          break;
        case _V3AdaptiveBitplaneMode.sparseOne:
          writer.writeBits(23, 5);
          _writeSparseBitplanePositions(writer, decision.minorityPositions);
          break;
        case _V3AdaptiveBitplaneMode.sparseZero:
          writer.writeBits(31, 5);
          _writeSparseBitplanePositions(writer, decision.minorityPositions);
          break;
      }
    }
  }

  static List<int> _decodeAdaptiveBitplanesBody(
    _V3BitReader reader,
    int pixelCount,
    List<int> palette,
  ) {
    final bits = _localBits(palette.length);
    final localPixels = List<int>.filled(pixelCount, 0);
    for (var bit = 0; bit < bits; bit++) {
      final firstPrefixBit = reader.readBits(1);
      if (firstPrefixBit == 0) {
        for (var i = 0; i < pixelCount; i++) {
          localPixels[i] |= reader.readBits(1) << bit;
        }
        continue;
      }

      final secondPrefixBit = reader.readBits(1);
      if (secondPrefixBit == 0) {
        _readAdaptiveBitplaneRuns(
          reader,
          localPixels,
          bit,
          pixelCount,
          shortLengths: false,
        );
        continue;
      }

      final thirdPrefixBit = reader.readBits(1);
      if (thirdPrefixBit == 0) {
        _readAdaptiveBitplaneRuns(
          reader,
          localPixels,
          bit,
          pixelCount,
          shortLengths: true,
        );
        continue;
      }

      switch (reader.readBits(2)) {
        case 0:
          break;
        case 1:
          for (var i = 0; i < pixelCount; i++) {
            localPixels[i] |= 1 << bit;
          }
          break;
        case 2:
          _readSparseBitplane(
            reader,
            localPixels,
            bit,
            pixelCount,
            minorityBit: 1,
          );
          break;
        case 3:
          for (var i = 0; i < pixelCount; i++) {
            localPixels[i] |= 1 << bit;
          }
          _readSparseBitplane(
            reader,
            localPixels,
            bit,
            pixelCount,
            minorityBit: 0,
          );
          break;
      }
    }
    return localPixels.map((index) {
      if (index >= palette.length) {
        throw const MCOImageInvalidPayloadException(
          'Adaptive bitplane color index out of range',
        );
      }
      return palette[index];
    }).toList(growable: false);
  }

  static _V3AdaptiveBitplaneDecision _chooseAdaptiveBitplaneEncoding(
    List<int> pixels,
    int bit,
  ) {
    final runs = _buildBitplaneRuns(pixels, bit);
    final startingBit = (pixels.first >> bit) & 1;
    final onePositions = <int>[];
    final zeroPositions = <int>[];
    for (var i = 0; i < pixels.length; i++) {
      (((pixels[i] >> bit) & 1) == 0 ? zeroPositions : onePositions).add(i);
    }

    final decisions = <_V3AdaptiveBitplaneDecision>[
      _V3AdaptiveBitplaneDecision(
        _V3AdaptiveBitplaneMode.raw,
        1 + pixels.length,
        startingBit: startingBit,
        runs: runs,
      ),
      _V3AdaptiveBitplaneDecision(
        _V3AdaptiveBitplaneMode.legacyRle,
        3 +
            runs.fold<int>(
              0,
              (sum, length) => sum + _compactUintBitLength(length - 1),
            ),
        startingBit: startingBit,
        runs: runs,
      ),
      _V3AdaptiveBitplaneDecision(
        _V3AdaptiveBitplaneMode.shortRle,
        4 +
            runs.fold<int>(
              0,
              (sum, length) => sum + _shortBitplaneRunBitLength(length),
            ),
        startingBit: startingBit,
        runs: runs,
      ),
    ];
    if (onePositions.isEmpty || zeroPositions.isEmpty) {
      decisions.add(
        _V3AdaptiveBitplaneDecision(
          onePositions.isEmpty
              ? _V3AdaptiveBitplaneMode.constantZero
              : _V3AdaptiveBitplaneMode.constantOne,
          5,
          startingBit: startingBit,
          runs: runs,
        ),
      );
    } else {
      decisions
        ..add(
          _V3AdaptiveBitplaneDecision(
            _V3AdaptiveBitplaneMode.sparseOne,
            5 + _sparseBitplanePositionCost(onePositions),
            startingBit: startingBit,
            runs: runs,
            minorityPositions: onePositions,
          ),
        )
        ..add(
          _V3AdaptiveBitplaneDecision(
            _V3AdaptiveBitplaneMode.sparseZero,
            5 + _sparseBitplanePositionCost(zeroPositions),
            startingBit: startingBit,
            runs: runs,
            minorityPositions: zeroPositions,
          ),
        );
    }
    var best = decisions.first;
    for (final decision in decisions.skip(1)) {
      if (decision.bitCost < best.bitCost) best = decision;
    }
    return best;
  }

  static void _readAdaptiveBitplaneRuns(
    _V3BitReader reader,
    List<int> pixels,
    int bit,
    int pixelCount, {
    required bool shortLengths,
  }) {
    var value = reader.readBits(1);
    var position = 0;
    while (position < pixelCount) {
      final length = shortLengths
          ? _readShortBitplaneRunLength(reader)
          : reader.readCompactUint() + 1;
      if (length <= 0 || position + length > pixelCount) {
        throw const MCOImageInvalidPayloadException(
          'Adaptive bitplane RLE exceeds pixel count',
        );
      }
      if (value != 0) {
        for (var i = 0; i < length; i++) {
          pixels[position + i] |= 1 << bit;
        }
      }
      position += length;
      value ^= 1;
    }
  }

  static void _readSparseBitplane(
    _V3BitReader reader,
    List<int> pixels,
    int bit,
    int pixelCount, {
    required int minorityBit,
  }) {
    final count = reader.readCompactUint() + 1;
    if (count > pixelCount) {
      throw const MCOImageInvalidPayloadException(
        'Sparse bitplane count exceeds pixel count',
      );
    }
    var previous = -1;
    for (var i = 0; i < count; i++) {
      final gap = reader.readCompactUint();
      final position = previous + gap + 1;
      if (position <= previous || position >= pixelCount) {
        throw const MCOImageInvalidPayloadException(
          'Sparse bitplane position out of range',
        );
      }
      if (minorityBit == 0) {
        pixels[position] &= ~(1 << bit);
      } else {
        pixels[position] |= 1 << bit;
      }
      previous = position;
    }
  }

  static int _sparseBitplanePositionCost(List<int> positions) {
    var cost = _compactUintBitLength(positions.length - 1);
    var previous = -1;
    for (final position in positions) {
      cost += _compactUintBitLength(position - previous - 1);
      previous = position;
    }
    return cost;
  }

  static void _writeSparseBitplanePositions(
    _V3BitWriter writer,
    List<int> positions,
  ) {
    writer.writeCompactUint(positions.length - 1);
    var previous = -1;
    for (final position in positions) {
      writer.writeCompactUint(position - previous - 1);
      previous = position;
    }
  }

  static void _writeShortBitplaneRunLength(
    _V3BitWriter writer,
    int length,
  ) {
    if (length <= 0) {
      throw const MCOImageInvalidInputException('Invalid bitplane run');
    }
    if (length <= 3) {
      writer.writeBits((1 << (length - 1)) - 1, length);
      return;
    }
    writer.writeBits(7, 3);
    writer.writeCompactUint(length - 4);
  }

  static int _readShortBitplaneRunLength(_V3BitReader reader) {
    if (reader.readBits(1) == 0) return 1;
    if (reader.readBits(1) == 0) return 2;
    if (reader.readBits(1) == 0) return 3;
    return reader.readCompactUint() + 4;
  }

  static int _shortBitplaneRunBitLength(int length) {
    if (length <= 0) {
      throw const MCOImageInvalidInputException('Invalid bitplane run');
    }
    if (length <= 3) return length;
    return 3 + _compactUintBitLength(length - 4);
  }

  static void _writeCompactRowDeltaBody(
    _V3BitWriter writer,
    List<int> values,
    int rowLength,
    int valueBits,
  ) {
    if (rowLength <= 0 || values.length % rowLength != 0) {
      throw const MCOImageInvalidInputException(
        'Invalid compact row-delta geometry',
      );
    }
    writer.writeBits(0, 1);
    for (var x = 0; x < rowLength; x++) {
      writer.writeBits(values[x], valueBits);
    }
    final rowCount = values.length ~/ rowLength;
    for (var row = 1; row < rowCount; row++) {
      final decision = _bestCompactRowDeltaDecision(
        values,
        rowLength,
        valueBits,
        row,
      );
      _writeCompactRowDeltaDecision(
        writer,
        values,
        rowLength,
        valueBits,
        row,
        decision,
      );
    }
  }

  static List<int> _readCompactRowDeltaBody(
    _V3BitReader reader,
    int count,
    int rowLength,
    int valueBits, {
    required int maxValue,
  }) {
    if (rowLength <= 0 || count % rowLength != 0) {
      throw const MCOImageInvalidPayloadException(
        'Invalid compact row-delta geometry',
      );
    }
    final useVirtualBaseRow = reader.readBits(1) != 0;
    if (useVirtualBaseRow) {
      throw const MCOImageInvalidPayloadException(
        'Virtual compact row-delta base row is not supported in v3 yet',
      );
    }
    final result = List<int>.filled(count, 0);
    for (var x = 0; x < rowLength; x++) {
      final value = reader.readBits(valueBits);
      if (value > maxValue) {
        throw const MCOImageInvalidPayloadException(
          'Compact row-delta first row value out of range',
        );
      }
      result[x] = value;
    }
    final rowCount = count ~/ rowLength;
    for (var row = 1; row < rowCount; row++) {
      final rowStart = row * rowLength;
      final previousStart = rowStart - rowLength;
      final op = reader.readBits(_compactRowDeltaOpBits);
      if (op == _compactRowDeltaOpRepeat) {
        for (var x = 0; x < rowLength; x++) {
          result[rowStart + x] = result[previousStart + x];
        }
        continue;
      }
      if (op == _compactRowDeltaOpRaw) {
        for (var x = 0; x < rowLength; x++) {
          final value = reader.readBits(valueBits);
          if (value > maxValue) {
            throw const MCOImageInvalidPayloadException(
              'Compact row-delta raw value out of range',
            );
          }
          result[rowStart + x] = value;
        }
        continue;
      }
      if (op == _compactRowDeltaOpIndexed) {
        for (var x = 0; x < rowLength; x++) {
          result[rowStart + x] = result[previousStart + x];
        }
        final changeCount = reader.readCompactUint() + 1;
        if (changeCount > rowLength) {
          throw const MCOImageInvalidPayloadException(
            'Compact row-delta change count exceeds row length',
          );
        }
        final positions = _readCompactChangePositions(
          reader,
          changeCount,
          rowLength,
        );
        for (final x in positions) {
          final value = reader.readBits(valueBits);
          if (value > maxValue) {
            throw const MCOImageInvalidPayloadException(
              'Compact row-delta indexed value out of range',
            );
          }
          result[rowStart + x] = value;
        }
        continue;
      }
      if (op == _compactRowDeltaOpPredicted) {
        final predictor = _readCompactRowDeltaPredictor(reader);
        _copyCompactRowDeltaPredictedRow(
          result,
          rowStart,
          rowLength,
          row,
          predictor,
        );
        continue;
      }
      if (op == _compactRowDeltaOpSameScalar ||
          op == _compactRowDeltaOpSegments ||
          op == _compactRowDeltaOpTrimmedMask) {
        for (var x = 0; x < rowLength; x++) {
          result[rowStart + x] = result[previousStart + x];
        }
        final positions = <int>[];
        if (op == _compactRowDeltaOpSameScalar) {
          final changeCount = reader.readCompactUint() + 1;
          if (changeCount > rowLength) {
            throw const MCOImageInvalidPayloadException(
              'Compact row-delta change count exceeds row length',
            );
          }
          positions.addAll(
            _readCompactChangePositions(reader, changeCount, rowLength),
          );
          final value = reader.readBits(valueBits);
          if (value > maxValue) {
            throw const MCOImageInvalidPayloadException(
              'Compact row-delta scalar value out of range',
            );
          }
          for (final x in positions) {
            result[rowStart + x] = value;
          }
          continue;
        }
        if (op == _compactRowDeltaOpSegments) {
          final segmentCount = reader.readCompactUint() + 1;
          if (segmentCount > rowLength) {
            throw const MCOImageInvalidPayloadException(
              'Compact row-delta segment count exceeds row length',
            );
          }
          var previousEnd = 0;
          for (var i = 0; i < segmentCount; i++) {
            final gap = reader.readCompactUint();
            final start = (i == 0 ? 0 : previousEnd) + gap;
            final length = reader.readCompactUint() + 1;
            if (start < previousEnd || start + length > rowLength) {
              throw const MCOImageInvalidPayloadException(
                'Invalid compact row-delta segment',
              );
            }
            for (var x = start; x < start + length; x++) {
              positions.add(x);
            }
            previousEnd = start + length;
          }
        } else {
          final start = reader.readCompactUint();
          final span = reader.readCompactUint() + 1;
          if (start + span > rowLength) {
            throw const MCOImageInvalidPayloadException(
              'Invalid compact row-delta mask bounds',
            );
          }
          for (var offset = 0; offset < span; offset++) {
            if (reader.readBits(1) != 0) positions.add(start + offset);
          }
          if (positions.isEmpty) {
            throw const MCOImageInvalidPayloadException(
              'Empty compact row-delta mask',
            );
          }
        }
        for (final x in positions) {
          final value = reader.readBits(valueBits);
          if (value > maxValue) {
            throw const MCOImageInvalidPayloadException(
              'Compact row-delta changed value out of range',
            );
          }
          result[rowStart + x] = value;
        }
        continue;
      }
      throw const MCOImageInvalidPayloadException(
        'Unsupported compact row-delta op',
      );
    }
    return result;
  }

  static List<_V3RowDeltaChange> _compactRowDeltaChanges(
    List<int> values,
    int rowLength,
    int row,
  ) {
    final changes = <_V3RowDeltaChange>[];
    final rowStart = row * rowLength;
    final previousStart = rowStart - rowLength;
    for (var x = 0; x < rowLength; x++) {
      final value = values[rowStart + x];
      if (value != values[previousStart + x]) {
        changes.add(_V3RowDeltaChange(x, value));
      }
    }
    return changes;
  }

  static _V3CompactRowDeltaDecision _bestCompactRowDeltaDecision(
    List<int> values,
    int rowLength,
    int valueBits,
    int row,
  ) {
    final rowStart = row * rowLength;
    var best = _V3CompactRowDeltaDecision(
      op: _compactRowDeltaOpRaw,
      changes: const <_V3RowDeltaChange>[],
      bitCost: _compactRowDeltaOpBits + rowLength * valueBits,
    );

    final changes = _compactRowDeltaChanges(values, rowLength, row);
    if (changes.isEmpty) {
      best = const _V3CompactRowDeltaDecision(
        op: _compactRowDeltaOpRepeat,
        changes: <_V3RowDeltaChange>[],
        bitCost: _compactRowDeltaOpBits,
      );
    } else {
      final indexedCost = _compactRowDeltaOpBits +
          _compactUintBitLength(changes.length - 1) +
          _compactChangePositionsBitCost(changes) +
          changes.length * valueBits;
      if (indexedCost < best.bitCost) {
        best = _V3CompactRowDeltaDecision(
          op: _compactRowDeltaOpIndexed,
          changes: changes,
          bitCost: indexedCost,
        );
      }

      final sameValue = _sameRowDeltaChangeValue(changes);
      if (sameValue != null) {
        final sameScalarCost = _compactRowDeltaOpBits +
            _compactUintBitLength(changes.length - 1) +
            _compactChangePositionsBitCost(changes) +
            valueBits;
        if (sameScalarCost < best.bitCost) {
          best = _V3CompactRowDeltaDecision(
            op: _compactRowDeltaOpSameScalar,
            changes: changes,
            bitCost: sameScalarCost,
          );
        }
      }

      final segments = _rowDeltaSegments(changes);
      var segmentGeometryCost = _compactUintBitLength(segments.length - 1);
      var previousEnd = 0;
      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final gap = i == 0 ? segment.x : segment.x - previousEnd;
        segmentGeometryCost += _compactUintBitLength(gap) +
            _compactUintBitLength(segment.length - 1);
        previousEnd = segment.x + segment.length;
      }
      final segmentCost = _compactRowDeltaOpBits +
          segmentGeometryCost +
          changes.length * valueBits;
      if (segmentCost < best.bitCost) {
        best = _V3CompactRowDeltaDecision(
          op: _compactRowDeltaOpSegments,
          changes: changes,
          bitCost: segmentCost,
        );
      }

      final span = changes.last.x - changes.first.x + 1;
      final maskCost = _compactRowDeltaOpBits +
          _compactUintBitLength(changes.first.x) +
          _compactUintBitLength(span - 1) +
          span +
          changes.length * valueBits;
      if (maskCost < best.bitCost) {
        best = _V3CompactRowDeltaDecision(
          op: _compactRowDeltaOpTrimmedMask,
          changes: changes,
          bitCost: maskCost,
        );
      }
    }

    for (final predictor in const [
      _rowDeltaPredictorLeft,
      _rowDeltaPredictorRight,
    ]) {
      var predicted = true;
      for (var x = 0; x < rowLength; x++) {
        if (values[rowStart + x] !=
            _compactRowDeltaPredictedValue(
              values,
              rowLength,
              row,
              x,
              predictor,
            )) {
          predicted = false;
          break;
        }
      }
      if (!predicted) continue;
      const cost = _compactRowDeltaOpBits + 2;
      if (cost < best.bitCost) {
        best = _V3CompactRowDeltaDecision(
          op: _compactRowDeltaOpPredicted,
          predictor: predictor,
          changes: const <_V3RowDeltaChange>[],
          bitCost: cost,
        );
      }
    }

    return best;
  }

  static void _writeCompactRowDeltaDecision(
    _V3BitWriter writer,
    List<int> values,
    int rowLength,
    int valueBits,
    int row,
    _V3CompactRowDeltaDecision decision,
  ) {
    writer.writeBits(decision.op, _compactRowDeltaOpBits);
    if (decision.op == _compactRowDeltaOpRepeat) return;
    if (decision.op == _compactRowDeltaOpPredicted) {
      _writeCompactRowDeltaPredictor(writer, decision.predictor);
      return;
    }
    final rowStart = row * rowLength;
    if (decision.op == _compactRowDeltaOpRaw) {
      for (var x = 0; x < rowLength; x++) {
        writer.writeBits(values[rowStart + x], valueBits);
      }
      return;
    }

    final changes = decision.changes;
    switch (decision.op) {
      case _compactRowDeltaOpIndexed:
        writer.writeCompactUint(changes.length - 1);
        _writeCompactChangePositions(writer, changes);
        for (final change in changes) {
          writer.writeBits(change.value, valueBits);
        }
        break;
      case _compactRowDeltaOpSameScalar:
        writer.writeCompactUint(changes.length - 1);
        _writeCompactChangePositions(writer, changes);
        writer.writeBits(changes.first.value, valueBits);
        break;
      case _compactRowDeltaOpSegments:
        final segments = _rowDeltaSegments(changes);
        writer.writeCompactUint(segments.length - 1);
        var previousEnd = 0;
        for (var i = 0; i < segments.length; i++) {
          final segment = segments[i];
          writer
            ..writeCompactUint(i == 0 ? segment.x : segment.x - previousEnd)
            ..writeCompactUint(segment.length - 1);
          previousEnd = segment.x + segment.length;
        }
        for (final change in changes) {
          writer.writeBits(change.value, valueBits);
        }
        break;
      case _compactRowDeltaOpTrimmedMask:
        final start = changes.first.x;
        final span = changes.last.x - start + 1;
        writer
          ..writeCompactUint(start)
          ..writeCompactUint(span - 1);
        var changeIndex = 0;
        for (var offset = 0; offset < span; offset++) {
          final changed = changeIndex < changes.length &&
              changes[changeIndex].x == start + offset;
          writer.writeBits(changed ? 1 : 0, 1);
          if (changed) changeIndex++;
        }
        for (final change in changes) {
          writer.writeBits(change.value, valueBits);
        }
        break;
      default:
        throw const MCOImageInvalidInputException(
          'Invalid compact row-delta op',
        );
    }
  }

  static void _writeCompactRowDeltaPredictor(
    _V3BitWriter writer,
    int predictor,
  ) {
    writer.writeBits(predictor == _rowDeltaPredictorLeft ? 0 : 1, 1);
  }

  static int _readCompactRowDeltaPredictor(_V3BitReader reader) {
    return reader.readBits(1) == 0
        ? _rowDeltaPredictorLeft
        : _rowDeltaPredictorRight;
  }

  static void _copyCompactRowDeltaPredictedRow(
    List<int> values,
    int rowStart,
    int rowLength,
    int row,
    int predictor,
  ) {
    for (var x = 0; x < rowLength; x++) {
      values[rowStart + x] = _compactRowDeltaPredictedValue(
        values,
        rowLength,
        row,
        x,
        predictor,
      );
    }
  }

  static int _compactRowDeltaPredictedValue(
    List<int> values,
    int rowLength,
    int row,
    int x,
    int predictor,
  ) {
    final previousStart = (row - 1) * rowLength;
    return switch (predictor) {
      _rowDeltaPredictorLeft =>
        values[previousStart + (x == 0 ? rowLength - 1 : x - 1)],
      _rowDeltaPredictorRight =>
        values[previousStart + (x + 1 == rowLength ? 0 : x + 1)],
      _ => values[previousStart + x],
    };
  }

  static int _compactChangePositionsBitCost(
    List<_V3RowDeltaChange> changes,
  ) {
    var cost = 0;
    var previousX = -1;
    for (final change in changes) {
      cost += _compactUintBitLength(change.x - previousX - 1);
      previousX = change.x;
    }
    return cost;
  }

  static void _writeCompactChangePositions(
    _V3BitWriter writer,
    List<_V3RowDeltaChange> changes,
  ) {
    var previousX = -1;
    for (final change in changes) {
      writer.writeCompactUint(change.x - previousX - 1);
      previousX = change.x;
    }
  }

  static int? _sameRowDeltaChangeValue(List<_V3RowDeltaChange> changes) {
    if (changes.isEmpty) return null;
    final value = changes.first.value;
    for (final change in changes.skip(1)) {
      if (change.value != value) return null;
    }
    return value;
  }

  static List<_V3RowDeltaSegment> _rowDeltaSegments(
    List<_V3RowDeltaChange> changes,
  ) {
    if (changes.isEmpty) return const <_V3RowDeltaSegment>[];
    final segments = <_V3RowDeltaSegment>[];
    var startX = changes.first.x;
    final values = <int>[changes.first.value];
    for (final change in changes.skip(1)) {
      if (change.x == startX + values.length) {
        values.add(change.value);
      } else {
        segments.add(_V3RowDeltaSegment(startX, List<int>.of(values)));
        startX = change.x;
        values
          ..clear()
          ..add(change.value);
      }
    }
    segments.add(_V3RowDeltaSegment(startX, List<int>.of(values)));
    return segments;
  }

  static List<int> _readCompactChangePositions(
    _V3BitReader reader,
    int count,
    int rowLength,
  ) {
    final positions = <int>[];
    var previousX = -1;
    for (var i = 0; i < count; i++) {
      final x = previousX + 1 + reader.readCompactUint();
      if (x >= rowLength) {
        throw const MCOImageInvalidPayloadException(
          'Compact row-delta position out of range',
        );
      }
      positions.add(x);
      previousX = x;
    }
    return positions;
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

  static bool _isGrayscaleProfile(PaletteProfile profile) {
    return profile == PaletteProfile.grayscale8 ||
        profile == PaletteProfile.grayscale16 ||
        profile == PaletteProfile.grayscale32;
  }

  static List<int> _dynamicProfilePixels(
    PaletteProfile profile,
    List<int> pixels,
  ) {
    return pixels.map((pixel) {
      final profileColorId =
          MCOImageDynamicPalette.profileColorIdForGlobalIndex(profile, pixel);
      if (profileColorId == null) {
        throw MCOImageInvalidInputException(
          'Color $pixel is outside dynamic profile $profile',
        );
      }
      return profileColorId;
    }).toList(growable: false);
  }

  static List<int> _dynamicProfilePalette(PaletteProfile profile) {
    return List<int>.generate(
      _paletteSize(profile),
      (index) =>
          MCOImageDynamicPalette.globalIndexForProfileColorId(profile, index),
    );
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

  static void _writeBoundsGeometry(
    _V3BitWriter writer,
    _V3Bounds bounds,
    int imageWidth,
    int imageHeight, {
    required bool compactGeometry,
  }) {
    _writeRegionGeometry(
      writer,
      bounds,
      imageWidth,
      imageHeight,
      compactGeometry: compactGeometry,
    );
  }

  static _V3Bounds _readBoundsGeometry(
    _V3BitReader reader,
    int imageWidth,
    int imageHeight, {
    required bool compactGeometry,
  }) {
    return _readRegionGeometry(
      reader,
      imageWidth,
      imageHeight,
      compactGeometry: compactGeometry,
    );
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

  static void _writeDeltaRegionGeometry(
    _V3BitWriter writer,
    _V3Bounds bounds,
    _V3Bounds previous,
  ) {
    _writeSignedCompactInt(writer, bounds.x - previous.x);
    _writeSignedCompactInt(writer, bounds.y - previous.y);
    _writeSignedCompactInt(writer, bounds.width - previous.width);
    _writeSignedCompactInt(writer, bounds.height - previous.height);
  }

  static _V3Bounds _readDeltaRegionGeometry(
    _V3BitReader reader,
    _V3Bounds previous,
    int imageWidth,
    int imageHeight,
  ) {
    final bounds = _V3Bounds(
      previous.x + _readSignedCompactInt(reader),
      previous.y + _readSignedCompactInt(reader),
      previous.width + _readSignedCompactInt(reader),
      previous.height + _readSignedCompactInt(reader),
    );
    if (bounds.x < 0 ||
        bounds.y < 0 ||
        bounds.width <= 0 ||
        bounds.height <= 0 ||
        bounds.x + bounds.width > imageWidth ||
        bounds.y + bounds.height > imageHeight) {
      throw const MCOImageInvalidPayloadException(
        'Invalid v3 delta region',
      );
    }
    return bounds;
  }

  static void _writeSignedCompactInt(_V3BitWriter writer, int value) {
    writer.writeCompactUint(value < 0 ? (-value * 2) - 1 : value * 2);
  }

  static int _readSignedCompactInt(_V3BitReader reader) {
    final encoded = reader.readCompactUint();
    return encoded.isEven ? encoded ~/ 2 : -((encoded + 1) ~/ 2);
  }

  static String _regionsContainerName(
    MCOImageV3Container container, {
    required bool commonBlockHeader,
    required bool deltaGeometry,
    required bool sharedLocalPalette,
  }) {
    final suffixes = <String>[
      if (commonBlockHeader) 'common',
      if (deltaGeometry) 'delta',
      if (sharedLocalPalette) 'shared',
    ];
    if (suffixes.isEmpty) return container.name;
    return '${container.name}-${suffixes.join('-')}';
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

class _V3LocalPaletteEncoding {
  final List<int> palette;
  final List<int> localPixels;
  final int bits;
  final int bitLength;

  const _V3LocalPaletteEncoding({
    required this.palette,
    required this.localPixels,
    required this.bits,
    required this.bitLength,
  });
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

enum _V3AdaptiveBitplaneMode {
  raw,
  legacyRle,
  shortRle,
  constantZero,
  constantOne,
  sparseOne,
  sparseZero,
}

class _V3AdaptiveBitplaneDecision {
  final _V3AdaptiveBitplaneMode mode;
  final int bitCost;
  final int startingBit;
  final List<int> runs;
  final List<int> minorityPositions;

  const _V3AdaptiveBitplaneDecision(
    this.mode,
    this.bitCost, {
    required this.startingBit,
    this.runs = const <int>[],
    this.minorityPositions = const <int>[],
  });
}

class _V3RowDeltaChange {
  final int x;
  final int value;

  const _V3RowDeltaChange(this.x, this.value);
}

class _V3RowDeltaSegment {
  final int x;
  final List<int> values;

  const _V3RowDeltaSegment(this.x, this.values);

  int get length => values.length;
}

class _V3CompactRowDeltaDecision {
  final int op;
  final int predictor;
  final List<_V3RowDeltaChange> changes;
  final int bitCost;

  const _V3CompactRowDeltaDecision({
    required this.op,
    this.predictor = 0,
    required this.changes,
    required this.bitCost,
  });
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

class _V3RegionPlan {
  final List<_V3RegionBlock>? blocks;
  final List<int>? sharedLocalPalette;

  const _V3RegionPlan({
    required this.blocks,
    this.sharedLocalPalette,
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
