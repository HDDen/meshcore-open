import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

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
  solidRects,
}

/// Binary-only MCOimg v3 block algorithm.
///
/// This keeps block algorithms separate from container variants. In v3 the
/// region stream can point directly at one of these algorithms for each region.
enum MCOImageV3BlockAlgorithm {
  rawGlobal,
  rawLocal,
  compactRle,
  compactSparse,
  biColorMask,
  rowRepeat,
  lzPixels,
  quadtree,

  // Intentionally separate wire grammars:
  // bitplanes:         0 = raw, 1 = legacy RLE + starting bit
  // adaptiveBitplanes: 0 = raw, 10/110/111xx = adaptive modes
  //
  // Combining them under one ID would require an extra discriminator bit
  // or make at least one existing encoding longer.
  bitplanes,
  adaptiveBitplanes,

  directBitplanes,
  compactRowDelta,
  directRowDelta,
  rowDelta;

  @Deprecated('Use directBitplanes')
  static const MCOImageV3BlockAlgorithm directGrayscaleBitplanes =
      directBitplanes;

  @Deprecated('Use directBitplanes')
  static const MCOImageV3BlockAlgorithm directDynamicBitplanes =
      directBitplanes;

  @Deprecated('Use directRowDelta')
  static const MCOImageV3BlockAlgorithm directGrayscaleRowDelta =
      directRowDelta;

  @Deprecated('Use directRowDelta')
  static const MCOImageV3BlockAlgorithm directDynamicRowDelta =
      directRowDelta;
}

class EncodedMCOImageV3 {
  final Uint8List body;
  final int byteLength;
  final int subtypeId;
  final int version;
  final EncodedMCOImage encodedCandidate;

  const EncodedMCOImageV3({
    required this.body,
    required this.byteLength,
    required this.encodedCandidate,
    this.subtypeId = ChannelAppDataHelper.mcoImageSubtype,
    this.version = ChannelAppDataHelper.mcoImageV3Version,
  });

  int get subtypeVersion => ChannelAppDataHelper.packSubtypeVersion(
        subtypeId: subtypeId,
        version: version,
      );

  Uint8List toAppPayloadWithoutSender() {
    return ChannelAppDataHelper.appPayloadWithoutSender(
      subtypeId: subtypeId,
      version: version,
      body: body,
    );
  }
}

class MCOImageV3Codec {
  MCOImageV3Codec();

  // Encoding is synchronous. The cache is reset for every encode/debugEncode
  // call and shared by full-image, bounds and region candidate searches.
  _V3LzTokenCache _lzTokenCache = _V3LzTokenCache();

  static const String textPrefix = 'im3:';
  static const int subtypeId = ChannelAppDataHelper.mcoImageSubtype;
  static const int version = ChannelAppDataHelper.mcoImageV3Version;
  static const int subtypeVersion =
      ChannelAppDataHelper.mcoImageV3SubtypeVersion;

  static bool isTextPayload(String text) => text.startsWith(textPrefix);

  static String textFromBody(Uint8List body) {
    return textFromAppPayloadWithoutSender(
      ChannelAppDataHelper.appPayloadWithoutSender(
        subtypeId: subtypeId,
        version: version,
        body: body,
      ),
    );
  }

  static String textFromAppPayloadWithoutSender(Uint8List payload) {
    return '$textPrefix${_V3Base91.encode(payload)}';
  }

  static Uint8List appPayloadWithoutSenderFromText(String text) {
    if (!isTextPayload(text)) {
      throw const MCOImageInvalidPayloadException('Missing im3: prefix');
    }
    return _V3Base91.decode(text.substring(textPrefix.length));
  }

  static Uint8List bodyFromText(String text) {
    final appPayload = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
      appPayloadWithoutSenderFromText(text),
    );
    if (appPayload == null || appPayload.subtypeId != subtypeId || appPayload.version != version) {
      throw const MCOImageInvalidPayloadException(
        'Invalid MCOimg v3 app payload',
      );
    }
    return appPayload.body;
  }

  static MCOImagePayloadInfo? inspectText(String text) {
    if (!isTextPayload(text)) return null;
    try {
      return inspectAppPayloadWithoutSender(
        appPayloadWithoutSenderFromText(text),
      );
    } on MCOImageCodecException {
      return null;
    }
  }

  static MCOImagePayloadInfo inspectAppPayloadWithoutSender(Uint8List payload) {
    final appPayload = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
      payload,
    );
    if (appPayload == null || appPayload.subtypeId != subtypeId || appPayload.version != version) {
      throw const MCOImageInvalidPayloadException(
        'Invalid MCOimg v3 app payload',
      );
    }
    return inspectBody(appPayload.body);
  }

  static MCOImagePayloadInfo inspectBody(Uint8List body) {
    if (body.length < 3) {
      throw const MCOImageInvalidPayloadException('MCOimg v3 payload too short');
    }
    final header = body[0];
    final scan = _scanFromHeader(header);
    final implicitWhiteBackground =
        (header & _implicitWhiteBackgroundFlag) != 0;
    final reader = _V3BitReader(body, byteIndex: 1);
    _readDimensions(reader);
    final containerByte = reader.readBits(8);
    final container = _containerFromId(
      containerByte >> _containerContextContainerShift,
    );
    final containerContext = containerByte & _containerContextMask;
    final algorithm = _topLevelAlgorithm(container, containerContext);
    _validateTopLevelScan(container, algorithm, scan);
    _validateImplicitWhiteBackground(
      container,
      algorithm,
      implicitWhiteBackground,
    );
    return MCOImagePayloadInfo(
      version: ChannelAppDataHelper.mcoImageV3Version,
      algorithm: _payloadAlgorithmLabel(container, algorithm),
      binaryLength: body.length,
    );
  }

  MCOImage decodeText(String text) {
    return decodeAppPayloadWithoutSender(
      appPayloadWithoutSenderFromText(text),
    );
  }
  static const int _transparentFlag = 0x80;
  static const int _implicitWhiteBackgroundFlag = 0x40;
  static const int _scanShift = 4;
  static const int _scanMask = 0x30;
  static const int _profileMask = 0x0f;
  static const int _dimensionModeSquare64 = 0;
  static const int _dimensionModeSmall32 = 1;
  static const int _dimensionModeMedium64 = 2;
  static const int _dimensionModeExtended = 3;
  static const int _containerContextContainerShift = 5;
  static const int _containerContextMask = 0x1f;
  static const int _minSize = 1;
  static const int _maxSize = 256;
  static const int _maxRegions = 32;
  static const int _normalMaxRegions = 16;
  static const int _greedyTieLargestArea = 0;
  static const int _greedyTieWidest = 1;
  static const int _greedyTieTallest = 2;
  static const int _maxBeamRegionPixels = 4096;
  static const int _regionBeamWidth = 3;
  static const int _regionBeamDepth = 2;
  static const int _regionBeamNeighbors = 8;
  static const int _maxExtremeRegionPixels = 1536;
  static const int _maxExtremeRegionComponents = 20;
  static const int _maxExtremeRegionBackgroundRank = 5;
  static const int _maxExtremeRegionSearchRegions = 20;
  static const int _extremeRegionBeamWidth = 10;
  static const int _extremeRegionBeamDepth = 8;
  static const int _extremeRegionNeighbors = 32;
  static const int _extremeRegionResultLimit = 10;
  static const int _extremeRegionExactRerankPoolSize = 32;
  static const int _extremeRegionEvaluationBudget = 1536;
  static const int _maxFrequentBackgroundCandidates = 8;
  static const int _maxExhaustiveBackgroundColors = 64;
  static const int _maxExhaustiveBackgroundPixels = 4096;
  static const int _minLzMatchLength = 3;
  static const int _maxLzMatchCandidates = 48;
  static const int _maxOptimalLzPixels = 1024;
  static const int _localPaletteDescriptorBits = 2;
  static const int _localPaletteSmallLengthLimit = 64;
  static const int _localPaletteMediumLengthLimit = 128;
  static const int _localPaletteLargeLengthLimit = 384;
  static const int _localPaletteDescriptorBitmap = 0;
  static const int _localPaletteDescriptorSortedDelta = 1;
  static const int _localPaletteDescriptorRangeRuns = 2;
  static const int _localPaletteDescriptorBankBitmaps = 3;
  static const int _localPaletteDescriptorOrderedBanked8x64 = 4;
  static const int _localPaletteBankDescriptorBitmaps = 0;
  static const int _localPaletteBankDescriptorOrdered8x64 = 1;

  // In compact regions, a common algorithm id of 31 introduces a hybrid
  // header: the real common algorithm follows, then every region carries one
  // override bit and only exceptions serialize their own algorithm/scan.
  static const int _hybridCommonRegionAlgorithmMarker = 31;
  static const List<MCOImageV3BlockAlgorithm> _regionBlockAlgorithms = [
    MCOImageV3BlockAlgorithm.rawGlobal,
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.quadtree,
    MCOImageV3BlockAlgorithm.bitplanes,
    MCOImageV3BlockAlgorithm.adaptiveBitplanes,
    MCOImageV3BlockAlgorithm.directBitplanes,
    MCOImageV3BlockAlgorithm.compactRowDelta,
    MCOImageV3BlockAlgorithm.directRowDelta,
    MCOImageV3BlockAlgorithm.rowDelta,
    MCOImageV3BlockAlgorithm.rowRepeat,
    MCOImageV3BlockAlgorithm.compactSparse,
    MCOImageV3BlockAlgorithm.biColorMask,
  ];
  static const List<MCOImageV3BlockAlgorithm> _normalRegionBlockAlgorithms = [
    MCOImageV3BlockAlgorithm.rawGlobal,
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.quadtree,
    MCOImageV3BlockAlgorithm.bitplanes,
    MCOImageV3BlockAlgorithm.adaptiveBitplanes,
    MCOImageV3BlockAlgorithm.compactRowDelta,
    MCOImageV3BlockAlgorithm.rowDelta,
    MCOImageV3BlockAlgorithm.rowRepeat,
    MCOImageV3BlockAlgorithm.compactSparse,
    MCOImageV3BlockAlgorithm.biColorMask,
  ];
  static const List<MCOImageV3BlockAlgorithm> _sharedPaletteRegionAlgorithms = [
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.compactSparse,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.quadtree,
    MCOImageV3BlockAlgorithm.bitplanes,
    MCOImageV3BlockAlgorithm.adaptiveBitplanes,
    MCOImageV3BlockAlgorithm.compactRowDelta,
    MCOImageV3BlockAlgorithm.rowDelta,
    MCOImageV3BlockAlgorithm.rowRepeat,
    MCOImageV3BlockAlgorithm.biColorMask,
  ];
  static const List<MCOImageV3BlockAlgorithm> _regionCostBlockAlgorithms = [
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.compactSparse,
    MCOImageV3BlockAlgorithm.bitplanes,
    MCOImageV3BlockAlgorithm.adaptiveBitplanes,
    MCOImageV3BlockAlgorithm.rowDelta,
    MCOImageV3BlockAlgorithm.biColorMask,
  ];
  static const List<MCOImageV3BlockAlgorithm>
      _normalSharedPaletteRegionAlgorithms = [
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.compactSparse,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.quadtree,
    MCOImageV3BlockAlgorithm.bitplanes,
    MCOImageV3BlockAlgorithm.adaptiveBitplanes,
    MCOImageV3BlockAlgorithm.compactRowDelta,
    MCOImageV3BlockAlgorithm.rowDelta,
    MCOImageV3BlockAlgorithm.rowRepeat,
    MCOImageV3BlockAlgorithm.biColorMask,
  ];
  static const int _rowDeltaOpBits = 2;
  static const int _rowDeltaOpRaw = 0;
  static const int _rowDeltaOpRepeat = 1;
  static const int _rowDeltaOpIndexed = 2;
  static const int _rowDeltaOpExtended = 3;
  static const int _rowDeltaExtendedBits = 2;
  static const int _rowDeltaExtendedMask = 0;
  static const int _rowDeltaExtendedSegments = 1;
  static const int _rowDeltaExtendedSameScalarMask = 2;
  static const int _rowDeltaExtendedRepeatRun = 3;

  static const int _compactRowDeltaOpBits = 3;
  static const int _compactRowDeltaOpRepeat = 0;
  static const int _compactRowDeltaOpRaw = 1;
  static const int _compactRowDeltaOpIndexed = 2;
  static const int _compactRowDeltaOpSameScalar = 3;
  static const int _compactRowDeltaOpSegments = 4;
  static const int _compactRowDeltaOpTrimmedMask = 5;
  static const int _compactRowDeltaOpRepeatRun = 6;
  static const int _compactRowDeltaOpPredicted = 7;
  static const int _rowDeltaPredictorSame = 0;
  static const int _rowDeltaPredictorLeft = 1;
  static const int _rowDeltaPredictorRight = 2;

  static int _normalizeCompressionLevel(int compressionLevel) {
    return switch (compressionLevel) {
      mcoImageCompressionLevelNormal => mcoImageCompressionLevelNormal,
      mcoImageCompressionLevelExtreme => mcoImageCompressionLevelExtreme,
      _ => mcoImageCompressionLevelHigh,
    };
  }

  static String _compressionLevelLabel(int compressionLevel) {
    return switch (_normalizeCompressionLevel(compressionLevel)) {
      mcoImageCompressionLevelNormal => 'Normal',
      mcoImageCompressionLevelExtreme => 'Extreme',
      _ => 'High',
    };
  }

  static List<MCOImageV3BlockAlgorithm> _regionBlockAlgorithmsForLevel({
    required bool useHighCompressionExtras,
    bool reducedCostEvaluator = false,
  }) {
    if (reducedCostEvaluator) return _regionCostBlockAlgorithms;
    return useHighCompressionExtras
        ? _regionBlockAlgorithms
        : _normalRegionBlockAlgorithms;
  }

  static List<MCOImageV3BlockAlgorithm>
      _sharedPaletteRegionAlgorithmsForLevel({
    required bool useHighCompressionExtras,
    bool reducedCostEvaluator = false,
  }) {
    if (reducedCostEvaluator) return _regionCostBlockAlgorithms;
    return useHighCompressionExtras
        ? _sharedPaletteRegionAlgorithms
        : _normalSharedPaletteRegionAlgorithms;
  }

  EncodedMCOImageV3 encode(
    MCOImage image, {
    int? backgroundColor,
    List<MCOImageBackgroundCandidate>? backgroundCandidates,
    List<ScanMode>? scanModes,
    bool includeNonScanCandidates = true,
    int compressionLevel = mcoImageDefaultCompressionLevel,
  }) {
    // v3 always optimizes and returns one canonical binary body.
    // Text output is only an app-side im3: Base91 wrapper over these bytes.
    _validateImage(image);
    final result = _encodeNative(
      image,
      backgroundColor: backgroundColor,
      backgroundCandidates: backgroundCandidates,
      scanModes: scanModes,
      includeNonScanCandidates: includeNonScanCandidates,
      compressionLevel: compressionLevel,
    );
    return EncodedMCOImageV3(
      body: result.payload,
      byteLength: result.payload.length,
      encodedCandidate: result,
    );
  }

  MCOImageEncodeDiagnostics debugEncode(
    MCOImage image, {
    int? backgroundColor,
    List<MCOImageBackgroundCandidate>? backgroundCandidates,
    List<ScanMode>? scanModes,
    bool includeNonScanCandidates = true,
    int compressionLevel = mcoImageDefaultCompressionLevel,
  }) {
    _validateImage(image);
    return _debugEncodeNative(
      image,
      backgroundColor: backgroundColor,
      backgroundCandidates: backgroundCandidates,
      scanModes: scanModes,
      includeNonScanCandidates: includeNonScanCandidates,
      compressionLevel: compressionLevel,
    );
  }

  static List<MCOImageBackgroundCandidate> backgroundCandidatesFor(
    MCOImage image, {
    int? backgroundColor,
    int compressionLevel = mcoImageDefaultCompressionLevel,
  }) {
    _validateImage(image);
    final effectiveCompressionLevel = _normalizeCompressionLevel(
      compressionLevel,
    );
    final preferredBackground =
        backgroundColor ??
        image.transparentColor ??
        MCOImagePalette.whiteIndexFor(image.paletteProfile);
    return _backgroundCandidates(
      image,
      preferredBackground,
      exhaustiveSmallImage:
          effectiveCompressionLevel != mcoImageCompressionLevelNormal,
    )
        .map(
          (candidate) => MCOImageBackgroundCandidate(
            color: candidate.color,
            rank: candidate.rank,
          ),
        )
        .toList(growable: false);
  }

  MCOImage decodeBody(Uint8List body) {
    if (body.length < 3) {
      throw const MCOImageInvalidPayloadException('MCOimg v3 payload too short');
    }
    final header = body[0];
    final scan = _scanFromHeader(header);
    final hasTransparentColor = (header & _transparentFlag) != 0;
    final implicitWhiteBackground =
        (header & _implicitWhiteBackgroundFlag) != 0;
    final profile = _profileFromId(header & _profileMask);
    final reader = _V3BitReader(body, byteIndex: 1);
    final dimensions = _readDimensions(reader);
    final width = dimensions.width;
    final height = dimensions.height;
    final containerByte = reader.readBits(8);
    final container = _containerFromId(
      containerByte >> _containerContextContainerShift,
    );
    final containerContext = containerByte & _containerContextMask;
    final algorithm = _topLevelAlgorithm(container, containerContext);
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
    _validateTopLevelScan(container, algorithm, scan);
    _validateImplicitWhiteBackground(
      container,
      algorithm,
      implicitWhiteBackground,
    );
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
          implicitWhiteBackground: implicitWhiteBackground,
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
          implicitWhiteBackground: implicitWhiteBackground,
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
        implicitWhiteBackground: implicitWhiteBackground,
      ),
      MCOImageV3Container.compactBoundsBlock => _decodeBoundsBlockBody(
        reader,
        width,
        height,
        profile,
        algorithm,
        scan,
        compactGeometry: true,
        implicitWhiteBackground: implicitWhiteBackground,
      ),
      MCOImageV3Container.regions => _decodeRegionsBody(
        reader,
        width,
        height,
        profile,
        regionCountContext: containerContext,
        compactGeometry: false,
        implicitWhiteBackground: implicitWhiteBackground,
      ),
      MCOImageV3Container.compactRegionsStream => _decodeRegionsBody(
        reader,
        width,
        height,
        profile,
        regionCountContext: containerContext,
        compactGeometry: true,
        implicitWhiteBackground: implicitWhiteBackground,
      ),
      MCOImageV3Container.solidBackground => List<int>.filled(
        width * height,
        _readSolidBackgroundColor(
          reader,
          profile,
          containerContext,
          implicitWhiteBackground: implicitWhiteBackground,
        ),
      ),
      MCOImageV3Container.solidRects => _decodeSolidRectsBody(
        reader,
        width,
        height,
        profile,
        rectCountContext: containerContext,
        implicitWhiteBackground: implicitWhiteBackground,
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
    if (appPayload.subtypeId != subtypeId || appPayload.version != version) {
      throw MCOImageInvalidPayloadException(
        'Unsupported MCOimg app subtype=${appPayload.subtypeId} '
        'version=${appPayload.version}',
      );
    }
    return decodeBody(appPayload.body);
  }

  EncodedMCOImage _encodeNative(
    MCOImage image, {
    int? backgroundColor,
    List<MCOImageBackgroundCandidate>? backgroundCandidates,
    List<ScanMode>? scanModes,
    bool includeNonScanCandidates = true,
    int compressionLevel = mcoImageDefaultCompressionLevel,
  }) {
    return _debugEncodeNative(
      image,
      backgroundColor: backgroundColor,
      backgroundCandidates: backgroundCandidates,
      scanModes: scanModes,
      includeNonScanCandidates: includeNonScanCandidates,
      compressionLevel: compressionLevel,
    ).result;
  }

  MCOImageEncodeDiagnostics _debugEncodeNative(
    MCOImage image, {
    int? backgroundColor,
    List<MCOImageBackgroundCandidate>? backgroundCandidates,
    List<ScanMode>? scanModes,
    bool includeNonScanCandidates = true,
    int compressionLevel = mcoImageDefaultCompressionLevel,
  }) {
    _lzTokenCache = _V3LzTokenCache();
    final effectiveCompressionLevel = _normalizeCompressionLevel(
      compressionLevel,
    );
    final useHighCompressionExtras =
        effectiveCompressionLevel != mcoImageCompressionLevelNormal;
    final useExtremeCompressionExtras =
        effectiveCompressionLevel == mcoImageCompressionLevelExtreme;
    final candidatesByPayload = <String, EncodedMCOImage>{};

    int compareCandidates(
      EncodedMCOImage a,
      EncodedMCOImage b,
    ) {
      final byBytes = a.byteLength.compareTo(b.byteLength);
      if (byBytes != 0) return byBytes;
      return _modeTieRank(a.mode).compareTo(_modeTieRank(b.mode));
    }

    void addCandidate(EncodedMCOImage? candidate) {
      if (candidate == null) return;
      final payloadKey = String.fromCharCodes(candidate.payload);
      final existing = candidatesByPayload[payloadKey];
      if (existing == null || compareCandidates(candidate, existing) < 0) {
        candidatesByPayload[payloadKey] = candidate;
      }
    }

    final preferredBackground =
        backgroundColor ??
        image.transparentColor ??
        MCOImagePalette.whiteIndexFor(image.paletteProfile);
    final effectiveBackgroundCandidates = backgroundCandidates == null
        ? _backgroundCandidates(
            image,
            preferredBackground,
            exhaustiveSmallImage: useHighCompressionExtras,
          )
        : _backgroundCandidatesFromPublic(
            backgroundCandidates,
            image.paletteProfile,
          );
    final effectiveScanModes = scanModes ?? ScanMode.values;
    if (includeNonScanCandidates) {
      final solidCandidate = _tryBuildSolidBackgroundCandidate(image);
      if (solidCandidate != null) addCandidate(solidCandidate);
    }

    for (final background in effectiveBackgroundCandidates) {
      final bg = background.color;
      if (includeNonScanCandidates) {
        final solidRectsCandidate = _tryBuildSolidRectsCandidate(
          image,
          bg,
          backgroundRank: background.rank,
        );
        if (solidRectsCandidate != null) {
          addCandidate(solidRectsCandidate);
        }
        final maxRegions = useHighCompressionExtras
            ? _maxRegions
            : _normalMaxRegions;
        final regionVariants = _regionVariantsForBackground(
          image,
          bg,
          maxRegions,
          useHighCompressionExtras: useHighCompressionExtras,
          useExtremeSearch: useExtremeCompressionExtras &&
              background.rank <= _maxExtremeRegionBackgroundRank,
        );
        for (final variant in regionVariants) {
          final regionPlanCache = _createRegionPlanCache(
            image,
            variant.regions,
            useHighCompressionExtras: useHighCompressionExtras,
          );
          final regionsCandidate = _tryBuildRegionsCandidate(
            image,
            bg,
            regionsOverride: variant.regions,
            variantLabel: variant.label,
            regionPlanCache: regionPlanCache,
            compactGeometry: false,
            useHighCompressionExtras: useHighCompressionExtras,
          );
          if (regionsCandidate != null) addCandidate(regionsCandidate);
          if (useHighCompressionExtras) {
            const regionOptions = [
              (
                commonBlockHeader: false,
                hybridCommonHeader: false,
                deltaGeometry: false,
                sharedLocalPalette: false,
              ),
              (
                commonBlockHeader: false,
                hybridCommonHeader: false,
                deltaGeometry: true,
                sharedLocalPalette: false,
              ),
              (
                commonBlockHeader: false,
                hybridCommonHeader: false,
                deltaGeometry: false,
                sharedLocalPalette: true,
              ),
              (
                commonBlockHeader: false,
                hybridCommonHeader: false,
                deltaGeometry: true,
                sharedLocalPalette: true,
              ),
              (
                commonBlockHeader: true,
                hybridCommonHeader: false,
                deltaGeometry: false,
                sharedLocalPalette: false,
              ),
              (
                commonBlockHeader: true,
                hybridCommonHeader: false,
                deltaGeometry: true,
                sharedLocalPalette: false,
              ),
              (
                commonBlockHeader: true,
                hybridCommonHeader: false,
                deltaGeometry: false,
                sharedLocalPalette: true,
              ),
              (
                commonBlockHeader: true,
                hybridCommonHeader: false,
                deltaGeometry: true,
                sharedLocalPalette: true,
              ),
              (
                commonBlockHeader: true,
                hybridCommonHeader: true,
                deltaGeometry: false,
                sharedLocalPalette: false,
              ),
              (
                commonBlockHeader: true,
                hybridCommonHeader: true,
                deltaGeometry: true,
                sharedLocalPalette: false,
              ),
              (
                commonBlockHeader: true,
                hybridCommonHeader: true,
                deltaGeometry: false,
                sharedLocalPalette: true,
              ),
              (
                commonBlockHeader: true,
                hybridCommonHeader: true,
                deltaGeometry: true,
                sharedLocalPalette: true,
              ),
            ];
            for (final options in regionOptions) {
              final candidate = _tryBuildRegionsCandidate(
                image,
                bg,
                regionsOverride: variant.regions,
                variantLabel: variant.label,
                regionPlanCache: regionPlanCache,
                compactGeometry: true,
                commonBlockHeader: options.commonBlockHeader,
                hybridCommonHeader: options.hybridCommonHeader,
                deltaGeometry: options.deltaGeometry,
                sharedLocalPalette: options.sharedLocalPalette,
                useHighCompressionExtras: useHighCompressionExtras,
              );
              if (candidate != null) addCandidate(candidate);
            }
          }
        }
      }

      final bounds = _boundsForBackground(image, bg);
      if (bounds == null ||
          bounds.width == image.width && bounds.height == image.height) {
        continue;
      }
      for (final scan in effectiveScanModes) {
        final cropped = _extractBoundsPixels(image, bounds);
        final linear = _toScanOrder(cropped, bounds.width, bounds.height, scan);
        for (final algorithm in const [
          MCOImageV3BlockAlgorithm.rawGlobal,
          MCOImageV3BlockAlgorithm.rawLocal,
          MCOImageV3BlockAlgorithm.compactRle,
          MCOImageV3BlockAlgorithm.lzPixels,
                MCOImageV3BlockAlgorithm.quadtree,
          MCOImageV3BlockAlgorithm.bitplanes,
          MCOImageV3BlockAlgorithm.adaptiveBitplanes,
          MCOImageV3BlockAlgorithm.directBitplanes,
          MCOImageV3BlockAlgorithm.compactRowDelta,
          MCOImageV3BlockAlgorithm.directRowDelta,
          MCOImageV3BlockAlgorithm.rowDelta,
          MCOImageV3BlockAlgorithm.rowRepeat,
          MCOImageV3BlockAlgorithm.compactSparse,
          MCOImageV3BlockAlgorithm.biColorMask,
        ]) {
          if (algorithm == MCOImageV3BlockAlgorithm.quadtree &&
              scan != ScanMode.h) {
            continue;
          }
          final blockBody = _tryBuildBlockBodyEncoding(
            image,
            linear,
            algorithm,
            backgroundColor: bg,
            rowLength: _rowLengthForScan(
              scan,
              bounds.width,
              bounds.height,
            ),
            backgroundInherited: true,
          );
          if (blockBody == null) continue;

          final candidate = _tryWrapBoundsBlockCandidate(
            image,
            bounds,
            linear,
            blockBody,
            algorithm,
            scan,
            backgroundColor: bg,
            compactGeometry: false,
          );
          if (candidate != null) addCandidate(candidate);

          final compactCandidate = _tryWrapBoundsBlockCandidate(
            image,
            bounds,
            linear,
            blockBody,
            algorithm,
            scan,
            backgroundColor: bg,
            compactGeometry: true,
          );
          if (compactCandidate != null) addCandidate(compactCandidate);
        }
      }
    }

    for (final scan in effectiveScanModes) {
      final linear = _toScanOrder(image.pixels, image.width, image.height, scan);
      for (final algorithm in const [
        MCOImageV3BlockAlgorithm.rawGlobal,
        MCOImageV3BlockAlgorithm.rawLocal,
        MCOImageV3BlockAlgorithm.compactRle,
        MCOImageV3BlockAlgorithm.lzPixels,
            MCOImageV3BlockAlgorithm.quadtree,
        MCOImageV3BlockAlgorithm.bitplanes,
        MCOImageV3BlockAlgorithm.directBitplanes,
        MCOImageV3BlockAlgorithm.directRowDelta,
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
          if (compactCandidate != null) addCandidate(compactCandidate);
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
        if (candidate != null) addCandidate(candidate);
      }
      for (final background in effectiveBackgroundCandidates) {
        final bg = background.color;
        for (final algorithm in const [
          MCOImageV3BlockAlgorithm.adaptiveBitplanes,
          MCOImageV3BlockAlgorithm.rowDelta,
          MCOImageV3BlockAlgorithm.compactRowDelta,
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
            if (compactCandidate != null) addCandidate(compactCandidate);
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
          if (candidate != null) addCandidate(candidate);
        }
      }
    }
    final candidates = candidatesByPayload.values.toList(growable: false);
    if (candidates.isEmpty) {
      throw const MCOImageInvalidInputException('No MCOimg v3 candidate');
    }
    candidates.sort(compareCandidates);
    _flushCandidateDebugLog(
      compressionLevel: effectiveCompressionLevel,
      candidates: candidates,
    );
    return MCOImageEncodeDiagnostics(
      result: candidates.first,
      candidates: List<EncodedMCOImage>.unmodifiable(candidates),
      compressionLevel: effectiveCompressionLevel,
    );
  }

  static void _flushCandidateDebugLog({
    required int compressionLevel,
    required List<EncodedMCOImage> candidates,
  }) {
    final total = candidates.length;
    for (var index = 0; index < total; index++) {
      final candidate = candidates[index];
      final algorithm = _candidateAlgorithmLabel(candidate);
      final completed = index + 1;
      final percentage = total == 0 ? 100.0 : completed * 100 / total;
      debugPrint(
        '[MCOimg][${_compressionLevelLabel(compressionLevel)}] '
        '$completed/$total (${percentage.toStringAsFixed(1)}%); '
        'bytes=${candidate.byteLength}; '
        'chars=${candidate.charLength}; '
        '${index == 0 ? 'BEST' : 'not-best'}; '
        'v3 $algorithm; '
        'algorithm=$algorithm; '
        'container=${candidate.container}; '
        'mode=${candidate.mode.name}; '
        'scan=${candidate.scan.name}; '
        'bg=${candidate.backgroundColor ?? -1}; '
        'bgRank=${candidate.backgroundRank}; '
        'bounds=${candidate.boundsPresent};',
      );
    }
  }

  static String _candidateAlgorithmLabel(
    EncodedMCOImage candidate,
  ) {
    try {
      return inspectBody(candidate.payload).algorithm;
    } on MCOImageCodecException {
      return candidate.mode.name;
    }
  }

  EncodedMCOImage? _tryBuildSolidBackgroundCandidate(MCOImage image) {
    if (image.pixels.isEmpty) return null;
    final color = image.pixels.first;
    for (final pixel in image.pixels) {
      if (pixel != color) return null;
    }

    final implicitWhiteBackground = _isImplicitWhiteBackground(
      image.paletteProfile,
      color,
    );
    const container = MCOImageV3Container.solidBackground;
    final colorRef = implicitWhiteBackground
        ? 0
        : _colorRefForProfile(image.paletteProfile, color);
    final writer = _V3BitWriter();
    _writeImagePreamble(
      writer,
      image,
      scan: ScanMode.h,
      implicitWhiteBackground: implicitWhiteBackground,
      container: container,
      containerContext: colorRef & _containerContextMask,
    );
    if (image.transparentColor != null) {
      _writeColorRef(writer, image.paletteProfile, image.transparentColor!);
    }
    if (!implicitWhiteBackground) {
      _writeContextualColorRefTail(
        writer,
        image.paletteProfile,
        colorRef,
      );
    }

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

  EncodedMCOImage? _tryBuildSolidRectsCandidate(
    MCOImage image,
    int backgroundColor, {
    required int backgroundRank,
  }) {
    final variants = _solidRectVariants(
      image.pixels,
      image.width,
      image.height,
      backgroundColor,
      maxRects: 64,
    );
    EncodedMCOImage? best;
    for (final rects in variants) {
      if (rects.isEmpty) continue;
      final implicitWhiteBackground = _isImplicitWhiteBackground(
        image.paletteProfile,
        backgroundColor,
      );
      const container = MCOImageV3Container.solidRects;
      final rectCountCode = rects.length - 1;
      final writer = _V3BitWriter();
      _writeImagePreamble(
        writer,
        image,
        scan: ScanMode.h,
        implicitWhiteBackground: implicitWhiteBackground,
        container: container,
        containerContext: rectCountCode & _containerContextMask,
      );
      if (image.transparentColor != null) {
        _writeColorRef(writer, image.paletteProfile, image.transparentColor!);
      }
      _writeBackgroundRef(
        writer,
        image.paletteProfile,
        backgroundColor,
        implicitWhiteBackground: implicitWhiteBackground,
      );
      final rectColors = rects.map((rect) => rect.color).toList();
      final palette = _localPalette(rectColors);
      _writeLocalPalette(writer, image.paletteProfile, palette);
      final map = _localIndexMap(palette);
      final bits = _localBits(palette.length);
      writer.writeBits(rectCountCode >> 5, 1);
      for (final rect in rects) {
        _writeBoundsGeometry(
          writer,
          rect.bounds,
          image.width,
          image.height,
          compactGeometry: true,
        );
        writer.writeBits(map[rect.color]!, bits);
      }
      final payload = writer.toBytes();
      final candidate = EncodedMCOImage(
        payload: payload,
        text: '',
        mode: ImageMode.extended,
        scan: ScanMode.h,
        byteLength: payload.length,
        charLength: 0,
        backgroundColor: backgroundColor,
        transparentColor: image.transparentColor,
        backgroundRank: backgroundRank,
        regionCount: rects.length,
        codecVersion: ChannelAppDataHelper.mcoImageV3Version,
        localPaletteSize: palette.length,
        bitsPerLocalPixel: bits,
        requestedEncodingVersion: MCOImageEncodingVersion.v3,
        actualEncodingVersion: MCOImageEncodingVersion.v3,
        paletteKind: image.paletteProfile.isDynamic ? 'dynamic' : 'fixed',
        container: 'solid-rects',
      );
      if (best == null || candidate.byteLength < best.byteLength) {
        best = candidate;
      }
    }
    return best;
  }

  EncodedMCOImage? _tryBuildRegionsCandidate(
    MCOImage image,
    int backgroundColor, {
    List<_V3Bounds>? regionsOverride,
    String? variantLabel,
    required bool compactGeometry,
    bool commonBlockHeader = false,
    bool hybridCommonHeader = false,
    bool deltaGeometry = false,
    bool sharedLocalPalette = false,
    required bool useHighCompressionExtras,
    bool reducedCostEvaluator = false,
    _V3RegionPlanCache? regionPlanCache,
  }) {
    final regions =
        regionsOverride ?? _componentBoundsForBackground(image, backgroundColor);
    final maxRegions = useHighCompressionExtras
        ? _maxRegions
        : _normalMaxRegions;
    if (regions.length < 2 || regions.length > maxRegions) return null;
    if (!_regionsDoNotOverlap(regions)) return null;
    if (commonBlockHeader && !compactGeometry) return null;
    if (hybridCommonHeader && !commonBlockHeader) return null;
    if (deltaGeometry && !compactGeometry) return null;
    if (sharedLocalPalette && !compactGeometry) return null;

    final effectivePlanCache =
        regionPlanCache ??
        _createRegionPlanCache(
          image,
          regions,
          useHighCompressionExtras: useHighCompressionExtras,
          reducedCostEvaluator: reducedCostEvaluator,
        );
    assert(
      effectivePlanCache.useHighCompressionExtras ==
          useHighCompressionExtras,
      'Region plan cache compression level mismatch',
    );
    assert(
      effectivePlanCache.reducedCostEvaluator == reducedCostEvaluator,
      'Region plan cache evaluator mismatch',
    );
    assert(
      effectivePlanCache.preparedRegions.length == regions.length,
      'Region plan cache layout mismatch',
    );
    final regionPlan = _regionPlanForCandidate(
      image,
      backgroundColor,
      effectivePlanCache,
      commonBlockHeader: commonBlockHeader,
      hybridCommonHeader: hybridCommonHeader,
      sharedLocalPalette: sharedLocalPalette,
    );
    final regionBlocks = regionPlan.blocks;
    if (regionBlocks == null) return null;

    final implicitWhiteBackground = _isImplicitWhiteBackground(
      image.paletteProfile,
      backgroundColor,
    );
    final container = compactGeometry
        ? MCOImageV3Container.compactRegionsStream
        : MCOImageV3Container.regions;
    final regionCountContext = regionBlocks.length - 1;
    final writer = _V3BitWriter();
    _writeImagePreamble(
      writer,
      image,
      scan: ScanMode.h,
      implicitWhiteBackground: implicitWhiteBackground,
      container: container,
      containerContext: regionCountContext,
    );
    if (image.transparentColor != null) {
      _writeColorRef(writer, image.paletteProfile, image.transparentColor!);
    }

    final bodyStartBits = writer.bitLength;
    try {
      _writeBackgroundRef(
        writer,
        image.paletteProfile,
        backgroundColor,
        implicitWhiteBackground: implicitWhiteBackground,
      );
      if (compactGeometry) {
        writer.writeBits(commonBlockHeader ? 1 : 0, 1);
        writer.writeBits(deltaGeometry ? 1 : 0, 1);
        writer.writeBits(sharedLocalPalette ? 1 : 0, 1);
        if (commonBlockHeader) {
          _writeRegionCommonHeader(
            writer,
            regionPlan,
            hybridCommonHeader: hybridCommonHeader,
          );
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
        if (hybridCommonHeader) {
          final usesCommon = _regionUsesCommonHeader(
            regionPlan,
            index,
            hybridCommonHeader: true,
          );
          writer.writeBits(usesCommon ? 0 : 1, 1);
          if (!usesCommon) {
            _writeRegionAlgorithmAndScan(
              writer,
              block.algorithm,
              block.scan,
            );
          }
        } else if (!commonBlockHeader) {
          _writeRegionAlgorithmAndScan(
            writer,
            block.algorithm,
            block.scan,
          );
        }
        if (sharedLocalPalette) {
          _writeBlockBodyWithSharedPalette(
            writer,
            block.linear,
            block.algorithm,
            regionPlan.sharedLocalPalette!,
            backgroundColor: backgroundColor,
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
            backgroundInherited: true,
          );
        }
      }
    } on MCOImageCodecException {
      return null;
    }
    if (writer.bitLength == bodyStartBits) return null;
    final serializedBitLength = writer.bitLength;
    final payload = writer.toBytes();
    assert(() {
      final expectedBitLength = _regionCandidateBitLength(
        image,
        backgroundColor,
        regionPlan,
        compactGeometry: compactGeometry,
        commonBlockHeader: commonBlockHeader,
        hybridCommonHeader: hybridCommonHeader,
        deltaGeometry: deltaGeometry,
        sharedLocalPalette: sharedLocalPalette,
      );
      assert(
        serializedBitLength == expectedBitLength,
        'MCOimg v3 region cost mismatch: estimated $expectedBitLength bits, '
        'serialized $serializedBitLength bits',
      );
      assert(
        payload.length == (expectedBitLength + 7) ~/ 8,
        'MCOimg v3 region byte cost mismatch',
      );
      return true;
    }());
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
        variantLabel: variantLabel,
        commonBlockHeader: commonBlockHeader,
        hybridCommonHeader: hybridCommonHeader,
        deltaGeometry: deltaGeometry,
        sharedLocalPalette: sharedLocalPalette,
      ),
    );
  }

  static List<_V3PreparedRegion> _prepareRegions(
    MCOImage image,
    List<_V3Bounds> regions,
  ) {
    return [
      for (final bounds in regions) _prepareRegion(image, bounds),
    ];
  }

  static _V3PreparedRegion _prepareRegion(
    MCOImage image,
    _V3Bounds bounds,
  ) {
    final cropped = _extractBoundsPixels(image, bounds);
    return _V3PreparedRegion(
      bounds: bounds,
      cropped: cropped,
      scanOrders: [
        for (final scan in ScanMode.values)
          _toScanOrder(cropped, bounds.width, bounds.height, scan),
      ],
    );
  }

  static _V3RegionPlanCache _createRegionPlanCache(
    MCOImage image,
    List<_V3Bounds> regions, {
    required bool useHighCompressionExtras,
    bool reducedCostEvaluator = false,
  }) {
    return _V3RegionPlanCache(
      preparedRegions: _prepareRegions(image, regions),
      useHighCompressionExtras: useHighCompressionExtras,
      reducedCostEvaluator: reducedCostEvaluator,
    );
  }

  _V3RegionPlan _regionPlanForCandidate(
    MCOImage image,
    int backgroundColor,
    _V3RegionPlanCache cache, {
    required bool commonBlockHeader,
    required bool hybridCommonHeader,
    required bool sharedLocalPalette,
  }) {
    if (sharedLocalPalette) {
      if (hybridCommonHeader) {
        if (!cache.sharedHybridComputed) {
          cache.sharedHybridPlan = _bestHybridSharedLocalPaletteRegionPlan(
            image,
            cache.preparedRegions,
            backgroundColor,
            useHighCompressionExtras: cache.useHighCompressionExtras,
            reducedCostEvaluator: cache.reducedCostEvaluator,
          );
          cache.sharedHybridComputed = true;
        }
        return cache.sharedHybridPlan!;
      }
      if (commonBlockHeader) {
        if (!cache.sharedComputed) {
          cache.sharedPlan = _bestSharedLocalPaletteRegionPlan(
            image,
            cache.preparedRegions,
            backgroundColor,
            useHighCompressionExtras: cache.useHighCompressionExtras,
            reducedCostEvaluator: cache.reducedCostEvaluator,
          );
          cache.sharedComputed = true;
        }
        return cache.sharedPlan!;
      }
      if (!cache.sharedIndividualComputed) {
        cache.sharedIndividualPlan =
            _bestIndividualSharedLocalPaletteRegionPlan(
          image,
          cache.preparedRegions,
          backgroundColor,
          useHighCompressionExtras: cache.useHighCompressionExtras,
          reducedCostEvaluator: cache.reducedCostEvaluator,
        );
        cache.sharedIndividualComputed = true;
      }
      return cache.sharedIndividualPlan!;
    }

    if (hybridCommonHeader) {
      if (!cache.hybridComputed) {
        if (!cache.individualComputed) {
          cache.individualPlan = _V3RegionPlan(
            blocks: _bestIndividualRegionBlocks(
              image,
              cache.preparedRegions,
              backgroundColor,
              useHighCompressionExtras: cache.useHighCompressionExtras,
              reducedCostEvaluator: cache.reducedCostEvaluator,
            ),
          );
          cache.individualComputed = true;
        }
        cache.hybridPlan = _bestHybridCommonRegionPlan(
          image,
          cache.preparedRegions,
          backgroundColor,
          individualBlocks: cache.individualPlan?.blocks,
          useHighCompressionExtras: cache.useHighCompressionExtras,
          reducedCostEvaluator: cache.reducedCostEvaluator,
        );
        cache.hybridComputed = true;
      }
      return cache.hybridPlan!;
    }

    if (commonBlockHeader) {
      if (!cache.commonComputed) {
        final blocks = _bestCommonRegionBlocks(
          image,
          cache.preparedRegions,
          backgroundColor,
          useHighCompressionExtras: cache.useHighCompressionExtras,
          reducedCostEvaluator: cache.reducedCostEvaluator,
        );
        cache.commonPlan = _V3RegionPlan(
          blocks: blocks,
          commonAlgorithm: blocks?.first.algorithm,
          commonScan: blocks?.first.scan,
        );
        cache.commonComputed = true;
      }
      return cache.commonPlan!;
    }

    if (!cache.individualComputed) {
      cache.individualPlan = _V3RegionPlan(
        blocks: _bestIndividualRegionBlocks(
          image,
          cache.preparedRegions,
          backgroundColor,
          useHighCompressionExtras: cache.useHighCompressionExtras,
          reducedCostEvaluator: cache.reducedCostEvaluator,
        ),
      );
      cache.individualComputed = true;
    }
    return cache.individualPlan!;
  }

  List<_V3RegionBlock>? _bestIndividualRegionBlocks(
    MCOImage image,
    List<_V3PreparedRegion> regions,
    int backgroundColor, {
    required bool useHighCompressionExtras,
    bool reducedCostEvaluator = false,
  }) {
    final regionBlocks = <_V3RegionBlock>[];
    for (final region in regions) {
      final block = _bestRegionBlock(
        image,
        region,
        backgroundColor,
        useHighCompressionExtras: useHighCompressionExtras,
        reducedCostEvaluator: reducedCostEvaluator,
      );
      if (block == null) return null;
      regionBlocks.add(block);
    }
    return regionBlocks;
  }

  List<_V3RegionBlock>? _bestCommonRegionBlocks(
    MCOImage image,
    List<_V3PreparedRegion> regions,
    int backgroundColor, {
    required bool useHighCompressionExtras,
    bool reducedCostEvaluator = false,
  }) {
    List<_V3RegionBlock>? bestBlocks;
    int? bestBits;
    MCOImageV3BlockAlgorithm? bestAlgorithm;
    for (final scan in ScanMode.values) {
      for (final algorithm in _regionBlockAlgorithmsForLevel(
        useHighCompressionExtras: useHighCompressionExtras,
        reducedCostEvaluator: reducedCostEvaluator,
      )) {
        if (!_regionAlgorithmSupportsScan(algorithm, scan) ||
            algorithm == MCOImageV3BlockAlgorithm.quadtree &&
                scan != ScanMode.h) {
          continue;
        }
        final blocks = <_V3RegionBlock>[];
        var totalBits = _commonRegionBlockHeaderBitLength(algorithm);
        var failed = false;
        for (final region in regions) {
          final block = _tryBuildRegionBlock(
            image,
            region,
            backgroundColor,
            algorithm,
            scan,
            greedyLzOnly: reducedCostEvaluator,
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
    List<_V3PreparedRegion> regions,
    int backgroundColor, {
    required bool useHighCompressionExtras,
    bool reducedCostEvaluator = false,
  }) {
    if (regions.length < 3) {
      return const _V3RegionPlan(blocks: null);
    }
    final allPixels = <int>[];
    for (final region in regions) {
      allPixels.addAll(region.cropped);
    }
    final orderInvariantPaletteVariants = _localPaletteVariants(
      allPixels,
      image.paletteProfile,
      indexOrderSensitive: false,
      includeTransitionOrder: false,
    );
    List<List<int>>? orderSensitivePaletteVariants;

    List<_V3RegionBlock>? bestBlocks;
    List<int>? bestPalette;
    int? bestBits;
    MCOImageV3BlockAlgorithm? bestAlgorithm;
    ScanMode? bestScan;
    for (final scan in ScanMode.values) {
      for (final algorithm in _sharedPaletteRegionAlgorithmsForLevel(
        useHighCompressionExtras: useHighCompressionExtras,
        reducedCostEvaluator: reducedCostEvaluator,
      )) {
        if (!_regionAlgorithmSupportsScan(algorithm, scan) ||
            algorithm == MCOImageV3BlockAlgorithm.quadtree &&
                scan != ScanMode.h) {
          continue;
        }
        final paletteVariants = _localPaletteOrderAffectsBody(algorithm)
            ? orderSensitivePaletteVariants ??= _localPaletteVariants(
                allPixels,
                image.paletteProfile,
                indexOrderSensitive: true,
                includeTransitionOrder: !reducedCostEvaluator,
                includeBitplaneOptimizedOrder: !reducedCostEvaluator,
                includeRgbOrder: !reducedCostEvaluator,
                preferredFirstColor: backgroundColor,
              )
            : orderInvariantPaletteVariants;
        for (final palette in paletteVariants) {
          final paletteWriter = _V3BitWriter();
          _writeLocalPalette(paletteWriter, image.paletteProfile, palette);
          var totalBits =
              paletteWriter.bitLength +
              _commonRegionBlockHeaderBitLength(algorithm);
          final blocks = <_V3RegionBlock>[];
          var failed = false;
          for (final region in regions) {
            final block = _tryBuildSharedPaletteRegionBlock(
              image,
              region,
              backgroundColor,
              algorithm,
              scan,
              palette,
              greedyLzOnly: reducedCostEvaluator,
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
            bestScan = scan;
          }
        }
      }
    }
    return _V3RegionPlan(
      blocks: bestBlocks,
      sharedLocalPalette: bestPalette,
      commonAlgorithm: bestAlgorithm,
      commonScan: bestScan,
    );
  }

  _V3RegionBlock? _bestSharedPaletteRegionBlock(
    MCOImage image,
    _V3PreparedRegion region,
    int backgroundColor,
    List<int> palette, {
    required bool useHighCompressionExtras,
    bool reducedCostEvaluator = false,
  }) {
    _V3RegionBlock? best;
    int? bestBits;
    for (final scan in ScanMode.values) {
      for (final algorithm in _sharedPaletteRegionAlgorithmsForLevel(
        useHighCompressionExtras: useHighCompressionExtras,
        reducedCostEvaluator: reducedCostEvaluator,
      )) {
        if (!_regionAlgorithmSupportsScan(algorithm, scan) ||
            algorithm == MCOImageV3BlockAlgorithm.quadtree &&
                scan != ScanMode.h) {
          continue;
        }
        final block = _tryBuildSharedPaletteRegionBlock(
          image,
          region,
          backgroundColor,
          algorithm,
          scan,
          palette,
          greedyLzOnly: reducedCostEvaluator,
        );
        if (block == null) continue;
        final blockBits = _individualRegionBlockBitLength(block);
        if (best == null ||
            blockBits < bestBits! ||
            blockBits == bestBits &&
                _modeTieRank(_imageModeForAlgorithm(algorithm)) <
                    _modeTieRank(_imageModeForAlgorithm(best.algorithm))) {
          best = block;
          bestBits = blockBits;
        }
      }
    }
    return best;
  }

  _V3RegionPlan _bestIndividualSharedLocalPaletteRegionPlan(
    MCOImage image,
    List<_V3PreparedRegion> regions,
    int backgroundColor, {
    required bool useHighCompressionExtras,
    bool reducedCostEvaluator = false,
  }) {
    final allPixels = <int>[];
    for (final region in regions) {
      allPixels.addAll(region.cropped);
    }
    final paletteVariants = _localPaletteVariants(
      allPixels,
      image.paletteProfile,
      indexOrderSensitive: true,
      includeTransitionOrder: !reducedCostEvaluator,
      includeBitplaneOptimizedOrder: !reducedCostEvaluator,
      includeRgbOrder: !reducedCostEvaluator,
      preferredFirstColor: backgroundColor,
    );

    List<_V3RegionBlock>? bestBlocks;
    List<int>? bestPalette;
    int? bestBits;
    for (final palette in paletteVariants) {
      final paletteWriter = _V3BitWriter();
      _writeLocalPalette(paletteWriter, image.paletteProfile, palette);
      var totalBits = paletteWriter.bitLength;
      final blocks = <_V3RegionBlock>[];
      var failed = false;
      for (final region in regions) {
        final block = _bestSharedPaletteRegionBlock(
          image,
          region,
          backgroundColor,
          palette,
          useHighCompressionExtras: useHighCompressionExtras,
          reducedCostEvaluator: reducedCostEvaluator,
        );
        if (block == null) {
          failed = true;
          break;
        }
        blocks.add(block);
        totalBits += _individualRegionBlockBitLength(block);
      }
      if (failed) continue;
      if (bestBits == null || totalBits < bestBits) {
        bestBits = totalBits;
        bestBlocks = blocks;
        bestPalette = palette;
      }
    }
    return _V3RegionPlan(
      blocks: bestBlocks,
      sharedLocalPalette: bestPalette,
    );
  }

  _V3RegionPlan _bestHybridCommonRegionPlan(
    MCOImage image,
    List<_V3PreparedRegion> regions,
    int backgroundColor, {
    required List<_V3RegionBlock>? individualBlocks,
    required bool useHighCompressionExtras,
    bool reducedCostEvaluator = false,
  }) {
    if (regions.length < 3 || individualBlocks == null) {
      return const _V3RegionPlan(blocks: null);
    }

    List<_V3RegionBlock>? bestBlocks;
    List<bool>? bestUsesCommon;
    MCOImageV3BlockAlgorithm? bestAlgorithm;
    ScanMode? bestScan;
    int? bestBits;
    for (final scan in ScanMode.values) {
      for (final algorithm in _regionBlockAlgorithmsForLevel(
        useHighCompressionExtras: useHighCompressionExtras,
        reducedCostEvaluator: reducedCostEvaluator,
      )) {
        if (!_regionAlgorithmSupportsScan(algorithm, scan) ||
            algorithm == MCOImageV3BlockAlgorithm.quadtree &&
                scan != ScanMode.h) {
          continue;
        }
        var totalBits = _hybridCommonRegionBlockHeaderBitLength(algorithm);
        final blocks = <_V3RegionBlock>[];
        final usesCommon = <bool>[];
        var commonCount = 0;
        var exceptionCount = 0;
        for (var index = 0; index < regions.length; index++) {
          final commonBlock = _tryBuildRegionBlock(
            image,
            regions[index],
            backgroundColor,
            algorithm,
            scan,
            greedyLzOnly: reducedCostEvaluator,
          );
          final individualBlock = individualBlocks[index];
          final commonBits =
              commonBlock == null ? 0 : 1 + commonBlock.bitLength;
          final exceptionBits =
              1 + _individualRegionBlockBitLength(individualBlock);
          if (commonBlock != null && commonBits <= exceptionBits) {
            blocks.add(commonBlock);
            usesCommon.add(true);
            totalBits += commonBits;
            commonCount++;
          } else {
            blocks.add(individualBlock);
            usesCommon.add(false);
            totalBits += exceptionBits;
            exceptionCount++;
          }
        }
        if (commonCount == 0 || exceptionCount == 0) continue;
        if (bestBits == null ||
            totalBits < bestBits ||
            totalBits == bestBits &&
                _modeTieRank(_imageModeForAlgorithm(algorithm)) <
                    _modeTieRank(_imageModeForAlgorithm(bestAlgorithm!))) {
          bestBits = totalBits;
          bestBlocks = blocks;
          bestUsesCommon = usesCommon;
          bestAlgorithm = algorithm;
          bestScan = scan;
        }
      }
    }
    return _V3RegionPlan(
      blocks: bestBlocks,
      commonAlgorithm: bestAlgorithm,
      commonScan: bestScan,
      usesCommonHeader: bestUsesCommon,
    );
  }

  _V3RegionPlan _bestHybridSharedLocalPaletteRegionPlan(
    MCOImage image,
    List<_V3PreparedRegion> regions,
    int backgroundColor, {
    required bool useHighCompressionExtras,
    bool reducedCostEvaluator = false,
  }) {
    final allPixels = <int>[];
    for (final region in regions) {
      allPixels.addAll(region.cropped);
    }
    final paletteVariants = _localPaletteVariants(
      allPixels,
      image.paletteProfile,
      indexOrderSensitive: true,
      includeTransitionOrder: !reducedCostEvaluator,
      includeBitplaneOptimizedOrder: !reducedCostEvaluator,
      includeRgbOrder: !reducedCostEvaluator,
      preferredFirstColor: backgroundColor,
    );

    List<_V3RegionBlock>? bestBlocks;
    List<int>? bestPalette;
    List<bool>? bestUsesCommon;
    MCOImageV3BlockAlgorithm? bestAlgorithm;
    ScanMode? bestScan;
    int? bestBits;
    for (final palette in paletteVariants) {
      final paletteWriter = _V3BitWriter();
      _writeLocalPalette(paletteWriter, image.paletteProfile, palette);
      final individualBlocks = <_V3RegionBlock>[];
      var failed = false;
      for (final region in regions) {
        final block = _bestSharedPaletteRegionBlock(
          image,
          region,
          backgroundColor,
          palette,
          useHighCompressionExtras: useHighCompressionExtras,
          reducedCostEvaluator: reducedCostEvaluator,
        );
        if (block == null) {
          failed = true;
          break;
        }
        individualBlocks.add(block);
      }
      if (failed) continue;

      for (final scan in ScanMode.values) {
        for (final algorithm in _sharedPaletteRegionAlgorithmsForLevel(
          useHighCompressionExtras: useHighCompressionExtras,
          reducedCostEvaluator: reducedCostEvaluator,
        )) {
          if (!_regionAlgorithmSupportsScan(algorithm, scan) ||
              algorithm == MCOImageV3BlockAlgorithm.quadtree &&
                  scan != ScanMode.h) {
            continue;
          }
          var totalBits = paletteWriter.bitLength +
              _hybridCommonRegionBlockHeaderBitLength(algorithm);
          final blocks = <_V3RegionBlock>[];
          final usesCommon = <bool>[];
          var commonCount = 0;
          var exceptionCount = 0;
          for (var index = 0; index < regions.length; index++) {
            final commonBlock = _tryBuildSharedPaletteRegionBlock(
              image,
              regions[index],
              backgroundColor,
              algorithm,
              scan,
              palette,
              greedyLzOnly: reducedCostEvaluator,
            );
            final individualBlock = individualBlocks[index];
            final commonBits =
                commonBlock == null ? 0 : 1 + commonBlock.bitLength;
            final exceptionBits =
                1 + _individualRegionBlockBitLength(individualBlock);
            if (commonBlock != null && commonBits <= exceptionBits) {
              blocks.add(commonBlock);
              usesCommon.add(true);
              totalBits += commonBits;
              commonCount++;
            } else {
              blocks.add(individualBlock);
              usesCommon.add(false);
              totalBits += exceptionBits;
              exceptionCount++;
            }
          }
          if (commonCount == 0 || exceptionCount == 0) continue;
          if (bestBits == null ||
              totalBits < bestBits ||
              totalBits == bestBits &&
                  _modeTieRank(_imageModeForAlgorithm(algorithm)) <
                      _modeTieRank(_imageModeForAlgorithm(bestAlgorithm!))) {
            bestBits = totalBits;
            bestBlocks = blocks;
            bestPalette = palette;
            bestUsesCommon = usesCommon;
            bestAlgorithm = algorithm;
            bestScan = scan;
          }
        }
      }
    }
    return _V3RegionPlan(
      blocks: bestBlocks,
      sharedLocalPalette: bestPalette,
      commonAlgorithm: bestAlgorithm,
      commonScan: bestScan,
      usesCommonHeader: bestUsesCommon,
    );
  }

  _V3RegionBlock? _bestRegionBlock(
    MCOImage image,
    _V3PreparedRegion region,
    int backgroundColor, {
    required bool useHighCompressionExtras,
    bool reducedCostEvaluator = false,
  }) {
    _V3RegionBlock? best;
    int? bestBits;
    for (final scan in ScanMode.values) {
      for (final algorithm in _regionBlockAlgorithmsForLevel(
        useHighCompressionExtras: useHighCompressionExtras,
        reducedCostEvaluator: reducedCostEvaluator,
      )) {
        if (!_regionAlgorithmSupportsScan(algorithm, scan) ||
            algorithm == MCOImageV3BlockAlgorithm.quadtree &&
                scan != ScanMode.h) {
          continue;
        }
        final block = _tryBuildRegionBlock(
          image,
          region,
          backgroundColor,
          algorithm,
          scan,
          greedyLzOnly: reducedCostEvaluator,
        );
        if (block == null) continue;
        final blockBits = _individualRegionBlockBitLength(block);
        if (best == null ||
            blockBits < bestBits! ||
            blockBits == bestBits &&
                _modeTieRank(_imageModeForAlgorithm(algorithm)) <
                    _modeTieRank(_imageModeForAlgorithm(best.algorithm))) {
          best = block;
          bestBits = blockBits;
        }
      }
    }
    return best;
  }

  static bool _regionAlgorithmSupportsScan(
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan,
  ) {
    return !_canUseCompactBlockHeader(algorithm) || scan == ScanMode.h;
  }

  static int _regionBlockScanBitLength(
    MCOImageV3BlockAlgorithm algorithm,
  ) {
    return _canUseCompactBlockHeader(algorithm) ? 0 : 2;
  }

  static int _individualRegionBlockBitLength(_V3RegionBlock block) {
    return 5 + _regionBlockScanBitLength(block.algorithm) + block.bitLength;
  }

  static int _commonRegionBlockHeaderBitLength(
    MCOImageV3BlockAlgorithm algorithm,
  ) {
    return 5 + _regionBlockScanBitLength(algorithm);
  }

  static int _hybridCommonRegionBlockHeaderBitLength(
    MCOImageV3BlockAlgorithm algorithm,
  ) {
    return 5 + _commonRegionBlockHeaderBitLength(algorithm);
  }

  static void _writeRegionAlgorithmAndScan(
    _V3BitWriter writer,
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan,
  ) {
    writer.writeBits(algorithm.index, 5);
    if (!_canUseCompactBlockHeader(algorithm)) {
      writer.writeBits(scan.index, 2);
    }
  }

  static void _writeRegionCommonHeader(
    _V3BitWriter writer,
    _V3RegionPlan plan, {
    required bool hybridCommonHeader,
  }) {
    final algorithm = plan.commonAlgorithm;
    final scan = plan.commonScan;
    if (algorithm == null || scan == null) {
      throw const MCOImageInvalidInputException(
        'Common region header is missing',
      );
    }
    if (hybridCommonHeader) {
      writer.writeBits(_hybridCommonRegionAlgorithmMarker, 5);
    }
    _writeRegionAlgorithmAndScan(writer, algorithm, scan);
  }

  static bool _regionUsesCommonHeader(
    _V3RegionPlan plan,
    int index, {
    required bool hybridCommonHeader,
  }) {
    if (!hybridCommonHeader) return true;
    final flags = plan.usesCommonHeader;
    if (flags == null || flags.length != plan.blocks?.length) {
      throw const MCOImageInvalidInputException(
        'Hybrid region header flags are missing',
      );
    }
    return flags[index];
  }

  int _regionCandidateBitLength(
    MCOImage image,
    int backgroundColor,
    _V3RegionPlan regionPlan, {
    required bool compactGeometry,
    required bool commonBlockHeader,
    required bool hybridCommonHeader,
    required bool deltaGeometry,
    required bool sharedLocalPalette,
  }) {
    final regionBlocks = regionPlan.blocks;
    if (regionBlocks == null || regionBlocks.isEmpty) {
      throw const MCOImageInvalidInputException(
        'Region cost requires at least one encoded block',
      );
    }
    final implicitWhiteBackground = _isImplicitWhiteBackground(
      image.paletteProfile,
      backgroundColor,
    );
    final container = compactGeometry
        ? MCOImageV3Container.compactRegionsStream
        : MCOImageV3Container.regions;
    final regionCountContext = regionBlocks.length - 1;
    final writer = _V3BitWriter();
    _writeImagePreamble(
      writer,
      image,
      scan: ScanMode.h,
      implicitWhiteBackground: implicitWhiteBackground,
      container: container,
      containerContext: regionCountContext,
    );
    if (image.transparentColor != null) {
      _writeColorRef(writer, image.paletteProfile, image.transparentColor!);
    }
    _writeBackgroundRef(
      writer,
      image.paletteProfile,
      backgroundColor,
      implicitWhiteBackground: implicitWhiteBackground,
    );
    if (compactGeometry) {
      writer.writeBits(commonBlockHeader ? 1 : 0, 1);
      writer.writeBits(deltaGeometry ? 1 : 0, 1);
      writer.writeBits(sharedLocalPalette ? 1 : 0, 1);
      if (commonBlockHeader) {
        _writeRegionCommonHeader(
          writer,
          regionPlan,
          hybridCommonHeader: hybridCommonHeader,
        );
      }
      if (sharedLocalPalette) {
        final palette = regionPlan.sharedLocalPalette;
        if (palette == null) {
          throw const MCOImageInvalidInputException(
            'Shared region palette is missing',
          );
        }
        _writeLocalPalette(writer, image.paletteProfile, palette);
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
      if (hybridCommonHeader) {
        final usesCommon = _regionUsesCommonHeader(
          regionPlan,
          index,
          hybridCommonHeader: true,
        );
        writer.writeBits(usesCommon ? 0 : 1, 1);
        if (!usesCommon) {
          _writeRegionAlgorithmAndScan(
            writer,
            block.algorithm,
            block.scan,
          );
        }
      } else if (!commonBlockHeader) {
        _writeRegionAlgorithmAndScan(
          writer,
          block.algorithm,
          block.scan,
        );
      }
      writer.writeZeroBits(block.bitLength);
    }
    return writer.bitLength;
  }

  _V3RegionBlock? _tryBuildRegionBlock(
    MCOImage image,
    _V3PreparedRegion region,
    int backgroundColor,
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan, {
    bool greedyLzOnly = false,
  }) {
    if (!_regionAlgorithmSupportsScan(algorithm, scan)) return null;
    final bounds = region.bounds;
    final linear = region.linearFor(scan);
    final writer = _V3BitWriter();
    try {
      _writeBlockBody(
        writer,
        linear,
        image.paletteProfile,
        algorithm,
        backgroundColor: backgroundColor,
        rowLength: _rowLengthForScan(scan, bounds.width, bounds.height),
        backgroundInherited: true,
        greedyLzOnly: greedyLzOnly,
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
    _V3PreparedRegion region,
    int backgroundColor,
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan,
    List<int> palette, {
    bool greedyLzOnly = false,
  }) {
    if (!_regionAlgorithmSupportsScan(algorithm, scan)) return null;
    final bounds = region.bounds;
    final linear = region.linearFor(scan);
    final writer = _V3BitWriter();
    try {
      _writeBlockBodyWithSharedPalette(
        writer,
        linear,
        algorithm,
        palette,
        backgroundColor: backgroundColor,
        rowLength: _rowLengthForScan(scan, bounds.width, bounds.height),
        greedyLzOnly: greedyLzOnly,
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

  _V3BlockBodyEncoding? _tryBuildBlockBodyEncoding(
    MCOImage image,
    List<int> linear,
    MCOImageV3BlockAlgorithm algorithm, {
    required int backgroundColor,
    required int rowLength,
    bool backgroundInherited = false,
  }) {
    final bodyWriter = _V3BitWriter();
    try {
      _writeBlockBody(
        bodyWriter,
        linear,
        image.paletteProfile,
        algorithm,
        backgroundColor: backgroundColor,
        rowLength: rowLength,
        backgroundInherited: backgroundInherited,
      );
    } on MCOImageCodecException {
      return null;
    }
    final bitLength = bodyWriter.bitLength;
    if (bitLength == 0) return null;
    return _V3BlockBodyEncoding(
      bytes: bodyWriter.toBytes(),
      bitLength: bitLength,
    );
  }

  EncodedMCOImage? _tryWrapBoundsBlockCandidate(
    MCOImage image,
    _V3Bounds bounds,
    List<int> linear,
    _V3BlockBodyEncoding blockBody,
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan, {
    required int backgroundColor,
    required bool compactGeometry,
  }) {
    if (compactGeometry &&
        _canUseCompactBlockHeader(algorithm) &&
        scan != ScanMode.h) {
      return null;
    }
    if (algorithm == MCOImageV3BlockAlgorithm.quadtree &&
        scan != ScanMode.h) {
      return null;
    }

    final writer = _V3BitWriter();
    final implicitWhiteBackground = _isImplicitWhiteBackground(
      image.paletteProfile,
      backgroundColor,
    );
    final container = compactGeometry
        ? MCOImageV3Container.compactBoundsBlock
        : MCOImageV3Container.boundsBlock;
    _writeImagePreamble(
      writer,
      image,
      scan: scan,
      implicitWhiteBackground: implicitWhiteBackground,
      container: container,
      containerContext: algorithm.index,
    );
    if (image.transparentColor != null) {
      _writeColorRef(writer, image.paletteProfile, image.transparentColor!);
    }

    _writeBackgroundRef(
      writer,
      image.paletteProfile,
      backgroundColor,
      implicitWhiteBackground: implicitWhiteBackground,
    );
    _writeBoundsGeometry(
      writer,
      bounds,
      image.width,
      image.height,
      compactGeometry: compactGeometry,
    );
    writer.writeBitStream(blockBody.bytes, blockBody.bitLength);

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
    final implicitWhiteBackground =
        _blockAlgorithmUsesBackgroundRef(algorithm) &&
        _isImplicitWhiteBackground(
          image.paletteProfile,
          backgroundColor,
        );
    final writer = _V3BitWriter();
    final container = compactHeader
        ? MCOImageV3Container.compactBlock
        : MCOImageV3Container.block;
    _writeImagePreamble(
      writer,
      image,
      scan: scan,
      implicitWhiteBackground: implicitWhiteBackground,
      container: container,
      containerContext: algorithm.index,
    );
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
    required bool implicitWhiteBackground,
  }) {
    final background = _readBackgroundRef(
      reader,
      profile,
      implicitWhiteBackground: implicitWhiteBackground,
    );
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
      implicitWhiteBackground: implicitWhiteBackground,
      inheritedBackgroundColor: background,
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
    required int regionCountContext,
    required bool compactGeometry,
    required bool implicitWhiteBackground,
  }) {
    final background = _readBackgroundRef(
      reader,
      profile,
      implicitWhiteBackground: implicitWhiteBackground,
    );
    final regionCount = regionCountContext + 1;
    if (regionCount > _maxRegions) {
      throw const MCOImageInvalidPayloadException('Invalid v3 region count');
    }
    final hasCommonBlockHeader =
        compactGeometry && reader.readBits(1) != 0;
    final hasDeltaGeometry = compactGeometry && reader.readBits(1) != 0;
    final hasSharedLocalPalette =
        compactGeometry && reader.readBits(1) != 0;
    var hasHybridCommonHeader = false;
    MCOImageV3BlockAlgorithm? commonAlgorithm;
    ScanMode? commonScan;
    if (hasCommonBlockHeader) {
      final commonAlgorithmId = reader.readBits(5);
      hasHybridCommonHeader =
          commonAlgorithmId == _hybridCommonRegionAlgorithmMarker;
      final decodedCommonAlgorithm = _algorithmFromId(
        hasHybridCommonHeader ? reader.readBits(5) : commonAlgorithmId,
      );
      commonAlgorithm = decodedCommonAlgorithm;
      commonScan = _canUseCompactBlockHeader(decodedCommonAlgorithm)
          ? ScanMode.h
          : _scanFromId(reader.readBits(2));
    }
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
      final hasIndividualHeader = hasHybridCommonHeader
          ? reader.readBits(1) != 0
          : !hasCommonBlockHeader;
      final algorithm = hasIndividualHeader
          ? _algorithmFromId(reader.readBits(5))
          : commonAlgorithm!;
      final scan = hasIndividualHeader
          ? (_canUseCompactBlockHeader(algorithm)
              ? ScanMode.h
              : _scanFromId(reader.readBits(2)))
          : commonScan!;
      final linear = sharedLocalPalette == null
          ? _decodeBlockBody(
              reader,
              bounds.width,
              bounds.height,
              profile,
              algorithm,
              scan,
              implicitWhiteBackground: implicitWhiteBackground,
              inheritedBackgroundColor: background,
            )
          : _decodeBlockBodyWithSharedPalette(
              reader,
              bounds.width,
              bounds.height,
              algorithm,
              scan,
              sharedLocalPalette,
              backgroundColor: background,
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

  List<int> _decodeSolidRectsBody(
    _V3BitReader reader,
    int width,
    int height,
    PaletteProfile profile, {
    required int rectCountContext,
    required bool implicitWhiteBackground,
  }) {
    final background = _readBackgroundRef(
      reader,
      profile,
      implicitWhiteBackground: implicitWhiteBackground,
    );
    final palette = _readLocalPalette(reader, profile);
    final bits = _localBits(palette.length);
    final rectCount =
        rectCountContext + (reader.readBits(1) << 5) + 1;
    if (rectCount > 64) {
      throw const MCOImageInvalidPayloadException(
        'Invalid solid rect count',
      );
    }
    final pixels = List<int>.filled(width * height, background);
    for (var i = 0; i < rectCount; i++) {
      final bounds = _readBoundsGeometry(
        reader,
        width,
        height,
        compactGeometry: true,
      );
      final colorIndex = reader.readBits(bits);
      if (colorIndex >= palette.length) {
        throw const MCOImageInvalidPayloadException(
          'Solid rect color index out of range',
        );
      }
      for (var row = 0; row < bounds.height; row++) {
        final start = (bounds.y + row) * width + bounds.x;
        for (var col = 0; col < bounds.width; col++) {
          pixels[start + col] = palette[colorIndex];
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
    bool backgroundInherited = false,
    bool greedyLzOnly = false,
  }) {
    switch (algorithm) {
      case MCOImageV3BlockAlgorithm.rawGlobal:
        for (final color in linear) {
          _writeColorRef(writer, profile, color);
        }
        break;
      case MCOImageV3BlockAlgorithm.rawLocal:
        _writeBestLocalPaletteBlock(
          writer,
          linear,
          profile,
          indexOrderSensitive: false,
          includeTransitionOrder: true,
          writeBody: (bodyWriter, localPixels, bits) {
            for (final color in localPixels) {
              bodyWriter.writeBits(color, bits);
            }
          },
        );
        break;
      case MCOImageV3BlockAlgorithm.compactRle:
        _writeBestLocalPaletteBlock(
          writer,
          linear,
          profile,
          indexOrderSensitive: false,
          includeTransitionOrder: true,
          writeBody: (bodyWriter, localPixels, bits) {
            var consumed = 0;
            for (final run in _buildRuns(localPixels)) {
              bodyWriter
                ..writeBits(run.color, bits)
                ..writeBoundedCompactUint(
                  run.length - 1,
                  localPixels.length - consumed - 1,
                );
              consumed += run.length;
            }
          },
        );
        break;
      case MCOImageV3BlockAlgorithm.lzPixels:
        _writeBestLocalPaletteBlock(
          writer,
          linear,
          profile,
          indexOrderSensitive: false,
          includeTransitionOrder: true,
          writeBody: (bodyWriter, localPixels, bits) {
            final tokens = greedyLzOnly
                ? _buildGreedyLzPixelTokensCached(localPixels, bits)
                : _buildBestLzPixelTokens(localPixels, bits);
            _writeLzPixelTokens(
              bodyWriter,
              tokens,
              bits,
              localPixels.length,
            );
          },
        );
        break;
      case MCOImageV3BlockAlgorithm.quadtree:
        if (rowLength <= 0 ||
            rowLength != linear.length && linear.length % rowLength != 0) {
          throw const MCOImageInvalidInputException(
            'Invalid quadtree geometry',
          );
        }
        _writeBestLocalPaletteBlock(
          writer,
          linear,
          profile,
          indexOrderSensitive: false,
          includeTransitionOrder: true,
          writeBody: (bodyWriter, localPixels, bits) {
            _writeQuadtreeNode(
              bodyWriter,
              localPixels,
              rowLength,
              0,
              0,
              rowLength,
              linear.length ~/ rowLength,
              bits,
            );
          },
        );
        break;
      // Keep the legacy and adaptive bitplane candidates independent.
      // The adaptive prefix is not a strict wire-compatible superset:
      // its legacy-RLE branch costs one extra prefix bit per RLE plane.
      case MCOImageV3BlockAlgorithm.bitplanes:
        _writeBestLocalPaletteBlock(
          writer,
          linear,
          profile,
          indexOrderSensitive: true,
          includeTransitionOrder: true,
          preferredFirstColor: backgroundColor,
          writeBody: (bodyWriter, localPixels, bits) {
            for (var bit = 0; bit < bits; bit++) {
              final runs = _buildBitplaneRuns(localPixels, bit);
              final rleBits =
                  2 + _residualRunLengthsBitCost(runs, localPixels.length);
              final rawBits = 1 + localPixels.length;
              if (rleBits < rawBits) {
                bodyWriter
                  ..writeBits(1, 1)
                  ..writeBits((localPixels.first >> bit) & 1, 1);
                _writeResidualRunLengths(
                  bodyWriter,
                  runs,
                  localPixels.length,
                );
              } else {
                bodyWriter.writeBits(0, 1);
                for (final pixel in localPixels) {
                  bodyWriter.writeBits((pixel >> bit) & 1, 1);
                }
              }
            }
          },
        );
        break;
      case MCOImageV3BlockAlgorithm.adaptiveBitplanes:
        _writeBestLocalPaletteBlock(
          writer,
          linear,
          profile,
          indexOrderSensitive: true,
          includeTransitionOrder: true,
          includeBitplaneOptimizedOrder: true,
          includeRgbOrder: true,
          preferredFirstColor: backgroundColor,
          writeBody: _writeAdaptiveBitplanesLocalBody,
        );
        break;
      case MCOImageV3BlockAlgorithm.directBitplanes:
        if (_isGrayscaleProfile(profile)) {
          _writeAdaptiveBitplanesBody(
            writer,
            linear,
            _globalBits(profile),
          );
          break;
        }
        if (profile.isDynamic) {
          _writeAdaptiveBitplanesBody(
            writer,
            _dynamicProfilePixels(profile, linear),
            _globalBits(profile),
          );
          break;
        }
        throw const MCOImageInvalidInputException(
          'Direct bitplanes require a grayscale or dynamic profile',
        );
      case MCOImageV3BlockAlgorithm.rowDelta:
        _writeBestLocalPaletteBlock(
          writer,
          linear,
          profile,
          indexOrderSensitive: true,
          includeTransitionOrder: true,
          preferredFirstColor: backgroundColor,
          writeBody: (bodyWriter, localPixels, bits) {
            _writeRowDeltaBody(
              bodyWriter,
              localPixels,
              rowLength,
              bits,
            );
          },
        );
        break;
      case MCOImageV3BlockAlgorithm.compactRowDelta:
        _writeBestLocalPaletteBlock(
          writer,
          linear,
          profile,
          indexOrderSensitive: true,
          includeTransitionOrder: true,
          preferredFirstColor: backgroundColor,
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
              directGrayscale: false,
            );
          },
        );
        break;
      case MCOImageV3BlockAlgorithm.directRowDelta:
        if (_isGrayscaleProfile(profile)) {
          _writeCompactRowDeltaBody(
            writer,
            linear,
            rowLength,
            _globalBits(profile),
            directGrayscale: true,
          );
          break;
        }
        if (profile.isDynamic) {
          _writeCompactRowDeltaBody(
            writer,
            _dynamicProfilePixels(profile, linear),
            rowLength,
            _globalBits(profile),
            directGrayscale: false,
          );
          break;
        }
        throw const MCOImageInvalidInputException(
          'Direct row-delta requires a grayscale or dynamic profile',
        );
      case MCOImageV3BlockAlgorithm.compactSparse:
        // Bounds and regions already serialize their background once.
        if (!backgroundInherited) {
          _writeBackgroundRef(
            writer,
            profile,
            backgroundColor,
            implicitWhiteBackground: _isImplicitWhiteBackground(
              profile,
              backgroundColor,
            ),
          );
        }
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
        writer.writeBoundedCompactUint(
          segments.length - 1,
          linear.length - 1,
        );
        var pos = 0;
        for (final segment in segments) {
          writer
            ..writeBoundedCompactUint(
              segment.start - pos,
              linear.length - pos - 1,
            )
            ..writeBits(map[segment.color]!, bits)
            ..writeBoundedCompactUint(
              segment.length - 1,
              linear.length - segment.start - 1,
            );
          pos = segment.start + segment.length;
        }
        break;
      case MCOImageV3BlockAlgorithm.biColorMask:
        final foreground = _biColorForeground(linear, backgroundColor);
        if (foreground == null) {
          throw const MCOImageInvalidInputException('Not a bi-color image');
        }
        if (!backgroundInherited) {
          _writeBackgroundRef(
            writer,
            profile,
            backgroundColor,
            implicitWhiteBackground: _isImplicitWhiteBackground(
              profile,
              backgroundColor,
            ),
          );
        }
        _writeColorRef(writer, profile, foreground);
        for (final color in linear) {
          writer.writeBits(color == foreground ? 1 : 0, 1);
        }
        break;
      case MCOImageV3BlockAlgorithm.rowRepeat:
        _writeBestLocalPaletteBlock(
          writer,
          linear,
          profile,
          indexOrderSensitive: false,
          includeTransitionOrder: true,
          writeBody: (bodyWriter, localPixels, bits) {
            _writeRowRepeat(bodyWriter, localPixels, rowLength, bits);
          },
        );
        break;
    }
  }

  void _writeBlockBodyWithSharedPalette(
    _V3BitWriter writer,
    List<int> linear,
    MCOImageV3BlockAlgorithm algorithm,
    List<int> palette, {
    required int backgroundColor,
    required int rowLength,
    bool greedyLzOnly = false,
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
      case MCOImageV3BlockAlgorithm.compactRle:
        var consumed = 0;
        for (final run in _buildRuns(linear)) {
          writer
            ..writeBits(map[run.color]!, bits)
            ..writeBoundedCompactUint(
              run.length - 1,
              linear.length - consumed - 1,
            );
          consumed += run.length;
        }
        break;
      case MCOImageV3BlockAlgorithm.compactSparse:
        if (linear.every((pixel) => pixel == backgroundColor)) {
          throw const MCOImageInvalidInputException(
            'Shared compact sparse has no foreground pixels',
          );
        }
        final segments = _buildSparseSegments(linear, backgroundColor);
        if (segments.isEmpty) {
          throw const MCOImageInvalidInputException(
            'Shared compact sparse has no segments',
          );
        }
        writer.writeBoundedCompactUint(
          segments.length - 1,
          linear.length - 1,
        );
        var pos = 0;
        for (final segment in segments) {
          final colorIndex = map[segment.color];
          if (colorIndex == null) {
            throw const MCOImageInvalidInputException(
              'Shared compact sparse color is missing from palette',
            );
          }
          writer
            ..writeBoundedCompactUint(
              segment.start - pos,
              linear.length - pos - 1,
            )
            ..writeBits(colorIndex, bits)
            ..writeBoundedCompactUint(
              segment.length - 1,
              linear.length - segment.start - 1,
            );
          pos = segment.start + segment.length;
        }
        break;
      case MCOImageV3BlockAlgorithm.lzPixels:
        final pixels = localPixels();
        final tokens = greedyLzOnly
            ? _buildGreedyLzPixelTokensCached(pixels, bits)
            : _buildBestLzPixelTokens(pixels, bits);
        _writeLzPixelTokens(
          writer,
          tokens,
          bits,
          pixels.length,
        );
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
          final rleBits =
              2 + _residualRunLengthsBitCost(runs, pixels.length);
          final rawBits = 1 + pixels.length;
          if (rleBits < rawBits) {
            writer
              ..writeBits(1, 1)
              ..writeBits((pixels.first >> bit) & 1, 1);
            _writeResidualRunLengths(
              writer,
              runs,
              pixels.length,
            );
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
      case MCOImageV3BlockAlgorithm.rowDelta:
        _writeRowDeltaBody(
          writer,
          localPixels(),
          rowLength,
          bits,
        );
        break;
      case MCOImageV3BlockAlgorithm.compactRowDelta:
        _writeCompactRowDeltaBody(
          writer,
          localPixels(),
          rowLength,
          bits,
          directGrayscale: false,
        );
        break;
      case MCOImageV3BlockAlgorithm.biColorMask:
        final foreground = _biColorForeground(linear, backgroundColor);
        if (foreground == null) {
          throw const MCOImageInvalidInputException(
            'Shared bi-color mask requires one foreground color',
          );
        }
        final foregroundIndex = map[foreground];
        if (foregroundIndex == null) {
          throw const MCOImageInvalidInputException(
            'Shared region palette is missing bi-color foreground',
          );
        }
        writer.writeBits(foregroundIndex, bits);
        for (final color in linear) {
          writer.writeBits(color == foreground ? 1 : 0, 1);
        }
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
    ScanMode scan, {
    required bool implicitWhiteBackground,
    int? inheritedBackgroundColor,
  }) {
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
          final length = reader.readBoundedCompactUint(
                count - result.length - 1,
              ) +
              1;
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
            final remaining = count - result.length;
            if (result.isEmpty || remaining < _minLzMatchLength) {
              throw const MCOImageInvalidPayloadException(
                'Invalid LZ pixel match',
              );
            }
            final distance =
                reader.readRangeCompactUint(result.length - 1) + 1;
            final length = reader.readRangeCompactUint(
                  remaining - _minLzMatchLength,
                ) +
                _minLzMatchLength;
            if (distance > result.length ||
                result.length + length > count) {
              throw const MCOImageInvalidPayloadException(
                'Invalid LZ pixel match',
              );
            }
            for (var i = 0; i < length; i++) {
              result.add(result[result.length - distance]);
            }
          } else {
            final length = reader.readRangeCompactUint(
                  count - result.length - 1,
                ) +
                1;
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
            final length =
                reader.readRangeCompactUint(count - position - 1) + 1;
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
      case MCOImageV3BlockAlgorithm.directBitplanes:
        if (_isGrayscaleProfile(profile)) {
          return _decodeAdaptiveBitplanesBody(
            reader,
            count,
            List<int>.generate(_paletteSize(profile), (index) => index),
          );
        }
        if (profile.isDynamic) {
          return _decodeAdaptiveBitplanesBody(
            reader,
            count,
            _dynamicProfilePalette(profile),
          );
        }
        throw const MCOImageInvalidPayloadException(
          'Direct bitplanes require a grayscale or dynamic profile',
        );
      case MCOImageV3BlockAlgorithm.rowDelta:
        final palette = _readLocalPalette(reader, profile);
        final bits = _localBits(palette.length);
        final localPixels = _readRowDeltaBody(
          reader,
          count,
          _rowLengthForScan(scan, width, height),
          bits,
          maxValue: palette.length - 1,
        );
        return localPixels.map((index) {
          if (index >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'Row-delta color index out of range',
            );
          }
          return palette[index];
        }).toList(growable: false);
      case MCOImageV3BlockAlgorithm.compactRowDelta:
        final palette = _readLocalPalette(reader, profile);
        final bits = _localBits(palette.length);
        final localPixels = _readCompactRowDeltaBody(
          reader,
          count,
          _rowLengthForScan(scan, width, height),
          bits,
          directGrayscale: false,
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
      case MCOImageV3BlockAlgorithm.directRowDelta:
        if (_isGrayscaleProfile(profile)) {
          return _readCompactRowDeltaBody(
            reader,
            count,
            _rowLengthForScan(scan, width, height),
            _globalBits(profile),
            directGrayscale: true,
            maxValue: _paletteSize(profile) - 1,
          );
        }
        if (profile.isDynamic) {
          final profilePixels = _readCompactRowDeltaBody(
            reader,
            count,
            _rowLengthForScan(scan, width, height),
            _globalBits(profile),
            directGrayscale: false,
            maxValue: _paletteSize(profile) - 1,
          );
          final palette = _dynamicProfilePalette(profile);
          return profilePixels.map((index) => palette[index]).toList(
                growable: false,
              );
        }
        throw const MCOImageInvalidPayloadException(
          'Direct row-delta requires a grayscale or dynamic profile',
        );
      case MCOImageV3BlockAlgorithm.compactSparse:
        final background = inheritedBackgroundColor ??
            _readBackgroundRef(
              reader,
              profile,
              implicitWhiteBackground: implicitWhiteBackground,
            );
        final palette = _readLocalPalette(reader, profile);
        if (palette.contains(background)) {
          throw const MCOImageInvalidPayloadException(
            'Compact sparse palette contains background',
          );
        }
        final bits = _localBits(palette.length);
        final result = List<int>.filled(count, background);
        final segmentCount =
            reader.readBoundedCompactUint(count - 1) + 1;
        var pos = 0;
        for (var i = 0; i < segmentCount; i++) {
          if (pos >= count) {
            throw const MCOImageInvalidPayloadException(
              'Invalid compact sparse segment count',
            );
          }
          pos += reader.readBoundedCompactUint(count - pos - 1);
          final colorIndex = reader.readBits(bits);
          if (colorIndex >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'Compact sparse color index out of range',
            );
          }
          final length =
              reader.readBoundedCompactUint(count - pos - 1) + 1;
          for (var j = 0; j < length; j++) {
            result[pos + j] = palette[colorIndex];
          }
          pos += length;
        }
        return result;
      case MCOImageV3BlockAlgorithm.biColorMask:
        final background = inheritedBackgroundColor ??
            _readBackgroundRef(
              reader,
              profile,
              implicitWhiteBackground: implicitWhiteBackground,
            );
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
    }
  }

  List<int> _decodeBlockBodyWithSharedPalette(
    _V3BitReader reader,
    int width,
    int height,
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan,
    List<int> palette, {
    required int backgroundColor,
  }) {
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
      case MCOImageV3BlockAlgorithm.compactRle:
        final result = <int>[];
        while (result.length < count) {
          final colorIndex = reader.readBits(bits);
          if (colorIndex >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'Compact RLE shared palette index out of range',
            );
          }
          final length = reader.readBoundedCompactUint(
                count - result.length - 1,
              ) +
              1;
          result.addAll(List<int>.filled(length, palette[colorIndex]));
        }
        return result;
      case MCOImageV3BlockAlgorithm.compactSparse:
        final segmentCount =
            reader.readBoundedCompactUint(count - 1) + 1;
        final result = List<int>.filled(count, backgroundColor);
        var pos = 0;
        for (var i = 0; i < segmentCount; i++) {
          if (pos >= count) {
            throw const MCOImageInvalidPayloadException(
              'Invalid shared compact sparse segment count',
            );
          }
          pos += reader.readBoundedCompactUint(count - pos - 1);
          final colorIndex = reader.readBits(bits);
          if (colorIndex >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'Shared compact sparse index out of range',
            );
          }
          if (palette[colorIndex] == backgroundColor) {
            throw const MCOImageInvalidPayloadException(
              'Shared compact sparse segment uses background',
            );
          }
          final length =
              reader.readBoundedCompactUint(count - pos - 1) + 1;
          for (var j = 0; j < length; j++) {
            result[pos + j] = palette[colorIndex];
          }
          pos += length;
        }
        return result;
      case MCOImageV3BlockAlgorithm.lzPixels:
        final result = <int>[];
        while (result.length < count) {
          final isMatch = reader.readBits(1) != 0;
          if (isMatch) {
            final remaining = count - result.length;
            if (result.isEmpty || remaining < _minLzMatchLength) {
              throw const MCOImageInvalidPayloadException(
                'Invalid LZ pixel match',
              );
            }
            final distance =
                reader.readRangeCompactUint(result.length - 1) + 1;
            final length = reader.readRangeCompactUint(
                  remaining - _minLzMatchLength,
                ) +
                _minLzMatchLength;
            if (distance > result.length ||
                result.length + length > count) {
              throw const MCOImageInvalidPayloadException(
                'Invalid LZ pixel match',
              );
            }
            for (var i = 0; i < length; i++) {
              result.add(result[result.length - distance]);
            }
          } else {
            final length = reader.readRangeCompactUint(
                  count - result.length - 1,
                ) +
                1;
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
            final length =
                reader.readRangeCompactUint(count - position - 1) + 1;
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
      case MCOImageV3BlockAlgorithm.rowDelta:
        return mapLocalPixels(
          _readRowDeltaBody(
            reader,
            count,
            _rowLengthForScan(scan, width, height),
            bits,
            maxValue: palette.length - 1,
          ),
        );
      case MCOImageV3BlockAlgorithm.compactRowDelta:
        return mapLocalPixels(
          _readCompactRowDeltaBody(
            reader,
            count,
            _rowLengthForScan(scan, width, height),
            bits,
            directGrayscale: false,
            maxValue: palette.length - 1,
          ),
        );
      case MCOImageV3BlockAlgorithm.biColorMask:
        final foregroundIndex = reader.readBits(bits);
        if (foregroundIndex >= palette.length) {
          throw const MCOImageInvalidPayloadException(
            'Invalid shared bi-color foreground',
          );
        }
        final foreground = palette[foregroundIndex];
        if (foreground == backgroundColor) {
          throw const MCOImageInvalidPayloadException(
            'Shared bi-color foreground equals background',
          );
        }
        return List<int>.generate(
          count,
          (_) => reader.readBits(1) != 0 ? foreground : backgroundColor,
        );
      case MCOImageV3BlockAlgorithm.rowRepeat:
        return mapLocalPixels(
          _readRowRepeat(
            reader,
            count,
            _rowLengthForScan(scan, width, height),
            bits,
          ),
        );
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

  static int _containerContextByte(
    MCOImageV3Container container,
    int context,
  ) {
    if (container.index >= (1 << 3)) {
      throw const MCOImageInvalidInputException(
        'MCOimg v3 container id does not fit',
      );
    }
    if (context < 0 || context > _containerContextMask) {
      throw const MCOImageInvalidInputException(
        'MCOimg v3 container context does not fit',
      );
    }
    return (container.index << _containerContextContainerShift) | context;
  }

  static MCOImageV3BlockAlgorithm _topLevelAlgorithm(
    MCOImageV3Container container,
    int context,
  ) {
    return switch (container) {
      MCOImageV3Container.block ||
      MCOImageV3Container.compactBlock ||
      MCOImageV3Container.boundsBlock ||
      MCOImageV3Container.compactBoundsBlock => _algorithmFromId(context),
      MCOImageV3Container.regions ||
      MCOImageV3Container.compactRegionsStream ||
      MCOImageV3Container.solidBackground ||
      MCOImageV3Container.solidRects =>
        MCOImageV3BlockAlgorithm.rawGlobal,
    };
  }

  static void _writeImagePreamble(
    _V3BitWriter writer,
    MCOImage image, {
    required ScanMode scan,
    required bool implicitWhiteBackground,
    required MCOImageV3Container container,
    required int containerContext,
  }) {
    writer.writeAlignedByte(
      _headerByte(
        image.paletteProfile,
        scan: scan,
        hasTransparentColor: image.transparentColor != null,
        implicitWhiteBackground: implicitWhiteBackground,
      ),
    );
    _writeDimensions(writer, image.width, image.height);
    writer.writeBits(
      _containerContextByte(container, containerContext),
      8,
    );
  }

  static void _writeDimensions(
    _V3BitWriter writer,
    int width,
    int height,
  ) {
    _validateDimensions(width, height);

    if (width == height && width <= 64) {
      writer
        ..writeBits(_dimensionModeSquare64, 2)
        ..writeBits(width - 1, 6);
      return;
    }

    if (width <= 32 && height <= 32) {
      writer
        ..writeBits(_dimensionModeSmall32, 2)
        ..writeBits(width - 1, 5)
        ..writeBits(height - 1, 5);
      return;
    }

    if (width <= 64 && height <= 64) {
      writer
        ..writeBits(_dimensionModeMedium64, 2)
        ..writeBits(width - 1, 6)
        ..writeBits(height - 1, 6);
      return;
    }

    writer.writeBits(_dimensionModeExtended, 2);
    if (width == height) {
      writer
        ..writeBits(0, 1)
        ..writeBits(width - 1, 8);
      return;
    }

    writer
      ..writeBits(1, 1)
      ..writeBits(width - 1, 8)
      ..writeBits(height - 1, 8);
  }

  static _V3Dimensions _readDimensions(_V3BitReader reader) {
    final mode = reader.readBits(2);
    late final int width;
    late final int height;

    switch (mode) {
      case _dimensionModeSquare64:
        width = reader.readBits(6) + 1;
        height = width;
        break;

      case _dimensionModeSmall32:
        width = reader.readBits(5) + 1;
        height = reader.readBits(5) + 1;
        if (width == height) {
          throw const MCOImageInvalidPayloadException(
            'Non-canonical small square dimensions',
          );
        }
        break;

      case _dimensionModeMedium64:
        width = reader.readBits(6) + 1;
        height = reader.readBits(6) + 1;
        if (width == height || width <= 32 && height <= 32) {
          throw const MCOImageInvalidPayloadException(
            'Non-canonical medium dimensions',
          );
        }
        break;

      case _dimensionModeExtended:
        final generalRectangle = reader.readBits(1) != 0;
        if (!generalRectangle) {
          width = reader.readBits(8) + 1;
          height = width;
          if (width <= 64) {
            throw const MCOImageInvalidPayloadException(
              'Non-canonical extended square dimensions',
            );
          }
        } else {
          width = reader.readBits(8) + 1;
          height = reader.readBits(8) + 1;
          if (width == height || width <= 64 && height <= 64) {
            throw const MCOImageInvalidPayloadException(
              'Non-canonical extended dimensions',
            );
          }
        }
        break;

      default:
        throw const MCOImageInvalidPayloadException(
          'Unknown dimension mode',
        );
    }

    _validateDimensions(width, height, payload: true);
    return _V3Dimensions(width: width, height: height);
  }

  static int _headerByte(
    PaletteProfile profile, {
    required ScanMode scan,
    required bool hasTransparentColor,
    required bool implicitWhiteBackground,
  }) {
    if (scan.index >= (1 << 2)) {
      throw const MCOImageInvalidInputException(
        'MCOimg v3 scan id does not fit',
      );
    }
    return (hasTransparentColor ? _transparentFlag : 0) |
        (implicitWhiteBackground ? _implicitWhiteBackgroundFlag : 0) |
        (scan.index << _scanShift) |
        _profileId(profile);
  }

  static ScanMode _scanFromHeader(int header) {
    return _scanFromId((header & _scanMask) >> _scanShift);
  }

  static void _validateTopLevelScan(
    MCOImageV3Container container,
    MCOImageV3BlockAlgorithm algorithm,
    ScanMode scan,
  ) {
    final requiresHorizontalScan = switch (container) {
      MCOImageV3Container.compactBlock ||
      MCOImageV3Container.regions ||
      MCOImageV3Container.compactRegionsStream ||
      MCOImageV3Container.solidBackground ||
      MCOImageV3Container.solidRects => true,
      MCOImageV3Container.compactBoundsBlock =>
        _canUseCompactBlockHeader(algorithm),
      _ => false,
    };
    if (requiresHorizontalScan && scan != ScanMode.h) {
      throw MCOImageInvalidPayloadException(
        '${container.name} requires horizontal top-level scan',
      );
    }
    if (algorithm == MCOImageV3BlockAlgorithm.quadtree &&
        scan != ScanMode.h) {
      throw const MCOImageInvalidPayloadException(
        'Quadtree requires horizontal scan',
      );
    }
  }

  static bool _blockAlgorithmUsesBackgroundRef(
    MCOImageV3BlockAlgorithm algorithm,
  ) {
    return switch (algorithm) {
      MCOImageV3BlockAlgorithm.compactSparse ||
      MCOImageV3BlockAlgorithm.biColorMask => true,
      _ => false,
    };
  }

  static void _validateImplicitWhiteBackground(
    MCOImageV3Container container,
    MCOImageV3BlockAlgorithm algorithm,
    bool implicitWhiteBackground,
  ) {
    if (!implicitWhiteBackground) return;
    final allowed = switch (container) {
      MCOImageV3Container.block ||
      MCOImageV3Container.compactBlock =>
        _blockAlgorithmUsesBackgroundRef(algorithm),
      MCOImageV3Container.boundsBlock ||
      MCOImageV3Container.compactBoundsBlock ||
      MCOImageV3Container.regions ||
      MCOImageV3Container.compactRegionsStream ||
      MCOImageV3Container.solidBackground ||
      MCOImageV3Container.solidRects => true,
    };
    if (!allowed) {
      throw const MCOImageInvalidPayloadException(
        'Implicit white background is not valid for this container',
      );
    }
  }

  static bool _isImplicitWhiteBackground(
    PaletteProfile profile,
    int backgroundColor,
  ) {
    return backgroundColor == MCOImagePalette.whiteIndexFor(profile);
  }

  static void _writeBackgroundRef(
    _V3BitWriter writer,
    PaletteProfile profile,
    int backgroundColor, {
    required bool implicitWhiteBackground,
  }) {
    if (!implicitWhiteBackground) {
      _writeColorRef(writer, profile, backgroundColor);
    }
  }

  static int _readBackgroundRef(
    _V3BitReader reader,
    PaletteProfile profile, {
    required bool implicitWhiteBackground,
  }) {
    return implicitWhiteBackground
        ? MCOImagePalette.whiteIndexFor(profile)
        : _readColorRef(reader, profile);
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
      MCOImageV3BlockAlgorithm.compactRle => ImageMode.rleLocal,
      MCOImageV3BlockAlgorithm.compactSparse => ImageMode.sparseBg,
      MCOImageV3BlockAlgorithm.biColorMask => ImageMode.biColorMask,
      MCOImageV3BlockAlgorithm.rowRepeat => ImageMode.rowRepeat,
      MCOImageV3BlockAlgorithm.rowDelta => ImageMode.rowDelta,
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

  static String _payloadAlgorithmLabel(
    MCOImageV3Container container,
    MCOImageV3BlockAlgorithm algorithm,
  ) {
    if (container == MCOImageV3Container.solidBackground) {
      return 'Solid background';
    }
    if (container == MCOImageV3Container.solidRects) {
      return 'Solid rectangles';
    }
    if (container == MCOImageV3Container.regions ||
        container == MCOImageV3Container.compactRegionsStream) {
      return 'Regions';
    }
    final base = _blockAlgorithmLabel(algorithm);
    return switch (container) {
      MCOImageV3Container.boundsBlock => '$base bounds',
      MCOImageV3Container.compactBoundsBlock => '$base bounds',
      _ => base,
    };
  }

  static String _blockAlgorithmLabel(MCOImageV3BlockAlgorithm algorithm) {
    return switch (algorithm) {
      MCOImageV3BlockAlgorithm.rawGlobal => 'Raw global',
      MCOImageV3BlockAlgorithm.rawLocal => 'Raw local',
      MCOImageV3BlockAlgorithm.compactRle => 'RLE local',
      MCOImageV3BlockAlgorithm.compactSparse => 'Sparse background',
      MCOImageV3BlockAlgorithm.biColorMask => 'Bi-color mask',
      MCOImageV3BlockAlgorithm.rowRepeat => 'Row repeat',
      MCOImageV3BlockAlgorithm.lzPixels => 'LZ pixels',
      MCOImageV3BlockAlgorithm.quadtree => 'Quadtree',
      MCOImageV3BlockAlgorithm.bitplanes => 'Bitplanes',
      MCOImageV3BlockAlgorithm.adaptiveBitplanes => 'Adaptive bitplanes',
      MCOImageV3BlockAlgorithm.directBitplanes => 'Direct bitplanes',
      MCOImageV3BlockAlgorithm.compactRowDelta => 'Compact row delta',
      MCOImageV3BlockAlgorithm.directRowDelta => 'Direct row delta',
      MCOImageV3BlockAlgorithm.rowDelta => 'Row delta',
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

  static bool _localPaletteOrderAffectsBody(
    MCOImageV3BlockAlgorithm algorithm,
  ) {
    return switch (algorithm) {
      MCOImageV3BlockAlgorithm.bitplanes ||
      MCOImageV3BlockAlgorithm.adaptiveBitplanes ||
      MCOImageV3BlockAlgorithm.compactRowDelta ||
      MCOImageV3BlockAlgorithm.rowDelta => true,
      _ => false,
    };
  }

  static int? _localPaletteSizeFor(
    List<int> linear,
    MCOImageV3BlockAlgorithm algorithm,
    int backgroundColor,
  ) {
    return switch (algorithm) {
      MCOImageV3BlockAlgorithm.rawLocal ||
      MCOImageV3BlockAlgorithm.compactRle ||
      MCOImageV3BlockAlgorithm.lzPixels ||
      MCOImageV3BlockAlgorithm.quadtree ||
      MCOImageV3BlockAlgorithm.bitplanes ||
      MCOImageV3BlockAlgorithm.adaptiveBitplanes ||
      MCOImageV3BlockAlgorithm.compactRowDelta ||
      MCOImageV3BlockAlgorithm.rowDelta ||
      MCOImageV3BlockAlgorithm.rowRepeat => linear.toSet().length,
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

      final remaining = pixels.length - position;
      final matchBits = bestLength >= _minLzMatchLength
          ? 1 +
                _rangeCompactUintBitLength(
                  bestDistance - 1,
                  position - 1,
                ) +
                _rangeCompactUintBitLength(
                  bestLength - _minLzMatchLength,
                  remaining - _minLzMatchLength,
                )
          : 0;
      final literalBits = bestLength >= _minLzMatchLength
          ? 1 +
                _rangeCompactUintBitLength(
                  bestLength - 1,
                  remaining - 1,
                ) +
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

  _V3LzTokenCacheEntry _lzTokenCacheEntry(
    List<int> pixels,
    int localBits,
  ) {
    final cacheKey = _lzOptimizationCacheKey(pixels, localBits);
    return _lzTokenCache.entries.putIfAbsent(cacheKey, () {
      final greedyTokens = _buildGreedyLzPixelTokens(pixels, localBits);
      return _V3LzTokenCacheEntry(
        greedyTokens: greedyTokens,
        greedyBitCost: _lzPixelTokensBitCost(
          greedyTokens,
          localBits,
          pixels.length,
        ),
      );
    });
  }

  List<_V3LzPixelToken> _buildGreedyLzPixelTokensCached(
    List<int> pixels,
    int localBits,
  ) {
    return _lzTokenCacheEntry(pixels, localBits).greedyTokens;
  }

  List<_V3LzPixelToken> _buildBestLzPixelTokens(
    List<int> pixels,
    int localBits,
  ) {
    final entry = _lzTokenCacheEntry(pixels, localBits);

    if (pixels.length > _maxOptimalLzPixels) {
      return entry.greedyTokens;
    }

    if (!entry.optimalComputed) {
      entry.optimalTokens = _buildOptimalLzPixelTokens(pixels, localBits);
      entry.optimalBitCost = entry.optimalTokens == null
          ? null
          : _lzPixelTokensBitCost(
              entry.optimalTokens!,
              localBits,
              pixels.length,
            );
      entry.optimalComputed = true;
    }

    final optimalTokens = entry.optimalTokens;
    final optimalBitCost = entry.optimalBitCost;
    if (optimalTokens != null &&
        optimalBitCost != null &&
        optimalBitCost < entry.greedyBitCost &&
        !_lzPixelTokensEqual(optimalTokens, entry.greedyTokens)) {
      return optimalTokens;
    }
    return entry.greedyTokens;
  }

  static String _lzOptimizationCacheKey(
    List<int> pixels,
    int localBits,
  ) {
    return '$localBits:${String.fromCharCodes(
      pixels.map((pixel) => pixel + 1),
    )}';
  }

  static bool _lzPixelTokensEqual(
    List<_V3LzPixelToken> left,
    List<_V3LzPixelToken> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.distance != b.distance ||
          a.length != b.length ||
          a.literals.length != b.literals.length) {
        return false;
      }
      for (var literalIndex = 0;
          literalIndex < a.literals.length;
          literalIndex++) {
        if (a.literals[literalIndex] != b.literals[literalIndex]) {
          return false;
        }
      }
    }
    return true;
  }

  static void _writeLzPixelTokens(
    _V3BitWriter writer,
    List<_V3LzPixelToken> tokens,
    int localBits,
    int totalLength,
  ) {
    var produced = 0;
    for (final token in tokens) {
      final remaining = totalLength - produced;
      if (token.isMatch) {
        if (produced <= 0 ||
            token.distance <= 0 ||
            token.distance > produced ||
            token.length < _minLzMatchLength ||
            token.length > remaining) {
          throw const MCOImageInvalidInputException(
            'Invalid LZ pixel match token',
          );
        }
        writer
          ..writeBits(1, 1)
          ..writeRangeCompactUint(
            token.distance - 1,
            produced - 1,
          )
          ..writeRangeCompactUint(
            token.length - _minLzMatchLength,
            remaining - _minLzMatchLength,
          );
        produced += token.length;
      } else {
        final length = token.literals.length;
        if (length <= 0 || length > remaining) {
          throw const MCOImageInvalidInputException(
            'Invalid LZ pixel literal token',
          );
        }
        writer
          ..writeBits(0, 1)
          ..writeRangeCompactUint(
            length - 1,
            remaining - 1,
          );
        for (final color in token.literals) {
          writer.writeBits(color, localBits);
        }
        produced += length;
      }
    }
    if (produced != totalLength) {
      throw const MCOImageInvalidInputException(
        'LZ pixel tokens do not fill the block',
      );
    }
  }

  static int _lzPixelTokensBitCost(
    List<_V3LzPixelToken> tokens,
    int localBits,
    int totalLength,
  ) {
    var cost = 0;
    var produced = 0;
    for (final token in tokens) {
      final remaining = totalLength - produced;
      if (token.isMatch) {
        if (produced <= 0 ||
            token.distance <= 0 ||
            token.distance > produced ||
            token.length < _minLzMatchLength ||
            token.length > remaining) {
          throw const MCOImageInvalidInputException(
            'Invalid LZ pixel match token',
          );
        }
        cost +=
            1 +
            _rangeCompactUintBitLength(
              token.distance - 1,
              produced - 1,
            ) +
            _rangeCompactUintBitLength(
              token.length - _minLzMatchLength,
              remaining - _minLzMatchLength,
            );
        produced += token.length;
      } else {
        final length = token.literals.length;
        if (length <= 0 || length > remaining) {
          throw const MCOImageInvalidInputException(
            'Invalid LZ pixel literal token',
          );
        }
        cost +=
            1 +
            _rangeCompactUintBitLength(
              length - 1,
              remaining - 1,
            ) +
            length * localBits;
        produced += length;
      }
    }
    if (produced != totalLength) {
      throw const MCOImageInvalidInputException(
        'LZ pixel tokens do not fill the block',
      );
    }
    return cost;
  }

  static List<_V3LzPixelToken>? _buildOptimalLzPixelTokens(
    List<int> pixels,
    int localBits,
  ) {
    if (pixels.isEmpty) return const <_V3LzPixelToken>[];
    final matches = _buildLzMatchOptions(pixels, localBits);
    final pixelCount = pixels.length;
    const infinity = 1 << 60;
    final steps = List<_V3LzParseStep?>.filled(pixelCount, null);
    final rawMin = _V3LzRangeMinimumTree(pixelCount + 1);
    final literalMin = _V3LzRangeMinimumTree(pixelCount + 1);
    rawMin.update(pixelCount, 0);
    literalMin.update(pixelCount, pixelCount * localBits);

    for (var position = pixelCount - 1; position >= 0; position--) {
      var bestCost = infinity;
      _V3LzParseStep? bestStep;
      final remaining = pixelCount - position;

      for (
        final range in _lzLengthCostRanges(
          1,
          remaining,
          remaining,
        )
      ) {
        final result = literalMin.query(
          position + range.minLength,
          position + range.maxLength + 1,
        );
        if (result == null) continue;
        final cost =
            1 + range.bitCost + result.cost - position * localBits;
        if (cost < bestCost ||
            cost == bestCost && result.index > (bestStep?.end ?? -1)) {
          bestCost = cost;
          bestStep = _V3LzParseStep.literal(result.index);
        }
      }

      for (final match in matches[position]) {
        for (
          final range in _lzLengthCostRanges(
            _minLzMatchLength,
            match.maxLength,
            remaining,
          )
        ) {
          final result = rawMin.query(
            position + range.minLength,
            position + range.maxLength + 1,
          );
          if (result == null) continue;
          final cost = 1 + match.distanceBitCost + range.bitCost + result.cost;
          if (cost < bestCost ||
              cost == bestCost && result.index > (bestStep?.end ?? -1)) {
            bestCost = cost;
            bestStep = _V3LzParseStep.match(result.index, match.distance);
          }
        }
      }

      if (bestStep == null) return null;
      steps[position] = bestStep;
      rawMin.update(position, bestCost);
      literalMin.update(position, bestCost + position * localBits);
    }

    final tokens = <_V3LzPixelToken>[];
    var position = 0;
    while (position < pixelCount) {
      final step = steps[position];
      if (step == null || step.end <= position || step.end > pixelCount) {
        return null;
      }
      final length = step.end - position;
      if (step.distance == 0) {
        tokens.add(
          _V3LzPixelToken.literal(pixels.sublist(position, step.end)),
        );
      } else {
        tokens.add(_V3LzPixelToken.match(step.distance, length));
      }
      position = step.end;
    }
    return tokens;
  }

  static List<List<_V3LzMatchOption>> _buildLzMatchOptions(
    List<int> pixels,
    int localBits,
  ) {
    final result = List.generate(
      pixels.length,
      (_) => <_V3LzMatchOption>[],
      growable: false,
    );
    final positionsByKey = <int, List<int>>{};
    for (var position = 0; position < pixels.length; position++) {
      if (position + _minLzMatchLength <= pixels.length) {
        final candidates = positionsByKey[_lzPixelKey(
          pixels,
          position,
          localBits,
        )];
        if (candidates != null) {
          final bestByDistanceCost = <int, _V3LzMatchOption>{};
          final maxPossibleLength = pixels.length - position;
          for (var i = candidates.length - 1; i >= 0; i--) {
            final previous = candidates[i];
            final distance = position - previous;
            final distanceBitCost = _rangeCompactUintBitLength(
              distance - 1,
              position - 1,
            );
            final existing = bestByDistanceCost[distanceBitCost];
            if (existing?.maxLength == maxPossibleLength) continue;
            final maxLength = _lzMatchLength(pixels, position, distance);
            if (maxLength < _minLzMatchLength) continue;
            if (existing == null || maxLength > existing.maxLength) {
              bestByDistanceCost[distanceBitCost] = _V3LzMatchOption(
                distance,
                maxLength,
                distanceBitCost,
              );
            }
          }
          result[position].addAll(bestByDistanceCost.values);
        }
      }
      _addLzPixelPosition(positionsByKey, pixels, position, localBits);
    }
    return result;
  }

  static int _lzMatchLength(
    List<int> pixels,
    int position,
    int distance,
  ) {
    var length = 0;
    while (position + length < pixels.length &&
        pixels[position + length] == pixels[position + length - distance]) {
      length++;
    }
    return length;
  }

  static Iterable<_V3LzLengthCostRange> _lzLengthCostRanges(
    int valueOffset,
    int candidateMaxLength,
    int remainingLength,
  ) sync* {
    if (candidateMaxLength < valueOffset ||
        candidateMaxLength > remainingLength) {
      return;
    }

    final maxValue = remainingLength - valueOffset;
    if (maxValue <= 7) {
      yield _V3LzLengthCostRange(
        valueOffset,
        candidateMaxLength,
        maxValue.bitLength,
      );
      return;
    }

    for (final valueRange in const [
      (min: 0, max: 3),
      (min: 4, max: 19),
      (min: 20, max: 275),
      (min: 276, max: 16383),
      (min: 16384, max: 2097151),
    ]) {
      final minLength = valueRange.min + valueOffset;
      if (minLength > candidateMaxLength) break;
      final rangeMaxLength = math.min(
        valueRange.max + valueOffset,
        candidateMaxLength,
      );
      yield _V3LzLengthCostRange(
        minLength,
        rangeMaxLength,
        _compactUintBitLength(valueRange.min),
      );
    }
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

  static int _rangeCompactUintBitLength(int value, int maxValue) {
    if (maxValue < 0 || value < 0 || value > maxValue) {
      throw const MCOImageInvalidInputException(
        'Range compact uint is out of range',
      );
    }
    if (maxValue <= 7) return maxValue.bitLength;
    return _compactUintBitLength(value);
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
    required bool indexOrderSensitive,
    required bool includeTransitionOrder,
    bool includeBitplaneOptimizedOrder = false,
    bool includeRgbOrder = false,
    int? preferredFirstColor,
    required void Function(
      _V3BitWriter writer,
      List<int> localPixels,
      int bits,
    ) writeBody,
  }) {
    final variants = _localPaletteVariants(
      linear,
      profile,
      indexOrderSensitive: indexOrderSensitive,
      includeTransitionOrder: includeTransitionOrder,
      includeBitplaneOptimizedOrder: includeBitplaneOptimizedOrder,
      includeRgbOrder: includeRgbOrder,
      preferredFirstColor: preferredFirstColor,
    );
    _V3LocalPaletteEncoding? best;
    for (final palette in variants) {
      final _V3LocalPaletteEncoding candidate;
      try {
        candidate = _encodeLocalPaletteBlock(
          linear,
          profile,
          palette,
          writeBody,
        );
      } on MCOImageCodecException {
        continue;
      }
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
    required bool indexOrderSensitive,
    required bool includeTransitionOrder,
    bool includeBitplaneOptimizedOrder = false,
    bool includeRgbOrder = false,
    int? preferredFirstColor,
  }) {
    final variants = <List<int>>[];
    final seen = <String>{};
    void add(List<int> palette) {
      if (palette.isEmpty) return;
      final key = palette.join(',');
      if (seen.add(key)) variants.add(palette);
    }

    final frequencyPalette = _localPalette(pixels);
    add(frequencyPalette);
    if (indexOrderSensitive &&
        preferredFirstColor != null &&
        frequencyPalette.contains(preferredFirstColor)) {
      add(<int>[
        preferredFirstColor,
        ...frequencyPalette.where((color) => color != preferredFirstColor),
      ]);
    }
    if (indexOrderSensitive) {
      add(_firstUseLocalPalette(pixels));
    }
    add(_profileOrderLocalPalette(pixels, profile));
    if (indexOrderSensitive && includeTransitionOrder) {
      final transitionPalette = _transitionLocalPalette(
        pixels,
        preferredFirstColor: preferredFirstColor,
      );
      if (transitionPalette != null) add(transitionPalette);
    }
    if (indexOrderSensitive && includeRgbOrder) {
      final rgbPalette = _rgbOrderLocalPalette(
        pixels,
        profile,
        preferredFirstColor: preferredFirstColor,
      );
      if (rgbPalette != null) add(rgbPalette);
    }
    if (indexOrderSensitive && includeBitplaneOptimizedOrder) {
      final optimizedPalettes = _bitplaneOptimizedLocalPalettes(
        pixels,
        profile,
        preferredFirstColor: preferredFirstColor,
      );
      for (final optimizedPalette in optimizedPalettes) {
        add(optimizedPalette);
      }
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

  static List<int>? _transitionLocalPalette(
    List<int> pixels, {
    required int? preferredFirstColor,
  }) {
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
    final firstColor =
        preferredFirstColor != null && remaining.contains(preferredFirstColor)
            ? preferredFirstColor
            : colors.first;
    final palette = <int>[firstColor];
    remaining.remove(firstColor);
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

  static List<int>? _rgbOrderLocalPalette(
    List<int> pixels,
    PaletteProfile profile, {
    required int? preferredFirstColor,
  }) {
    final colors = pixels.toSet().toList();
    if (colors.length < 3) return null;
    final counts = <int, int>{};
    for (final pixel in pixels) {
      counts[pixel] = (counts[pixel] ?? 0) + 1;
    }
    final remaining = colors.toSet();
    var current =
        preferredFirstColor != null && remaining.contains(preferredFirstColor)
            ? preferredFirstColor
            : colors.reduce(
                (left, right) =>
                    (counts[left] ?? 0) >= (counts[right] ?? 0)
                        ? left
                        : right,
              );
    final result = <int>[];
    while (remaining.isNotEmpty) {
      result.add(current);
      remaining.remove(current);
      if (remaining.isEmpty) break;
      current = remaining.reduce((left, right) {
        final leftDistance = _paletteRgbDistanceSquared(
          profile,
          current,
          left,
        );
        final rightDistance = _paletteRgbDistanceSquared(
          profile,
          current,
          right,
        );
        if (leftDistance != rightDistance) {
          return leftDistance < rightDistance ? left : right;
        }
        final leftCount = counts[left] ?? 0;
        final rightCount = counts[right] ?? 0;
        if (leftCount != rightCount) return leftCount > rightCount ? left : right;
        return left < right ? left : right;
      });
    }
    return result;
  }

  static int _paletteRgbDistanceSquared(
    PaletteProfile profile,
    int left,
    int right,
  ) {
    final colors = profile.isDynamic
        ? MCOImageDynamicPalette.global512
        : MCOImagePalette.colorsFor(profile);
    final leftArgb = colors[left].toARGB32();
    final rightArgb = colors[right].toARGB32();
    final red = ((leftArgb >> 16) & 0xff) - ((rightArgb >> 16) & 0xff);
    final green = ((leftArgb >> 8) & 0xff) - ((rightArgb >> 8) & 0xff);
    final blue = (leftArgb & 0xff) - (rightArgb & 0xff);
    return red * red + green * green + blue * blue;
  }

  static List<List<int>> _bitplaneOptimizedLocalPalettes(
    List<int> pixels,
    PaletteProfile profile, {
    required int? preferredFirstColor,
  }) {
    final basePalette = _localPalette(pixels);
    if (basePalette.length < 2) return const <List<int>>[];

    final backgroundFirstPalette =
        preferredFirstColor != null && basePalette.contains(preferredFirstColor)
            ? <int>[
                preferredFirstColor,
                ...basePalette.where(
                  (color) => color != preferredFirstColor,
                ),
              ]
            : null;
    final seeds = <List<int>>[
      basePalette,
      ?backgroundFirstPalette,
      _profileOrderLocalPalette(pixels, profile),
      if (preferredFirstColor != null)
        _rgbOrderLocalPalette(
              pixels,
              profile,
              preferredFirstColor: preferredFirstColor,
            ) ??
            basePalette,
      _transitionLocalPalette(
            pixels,
            preferredFirstColor: preferredFirstColor,
          ) ??
          basePalette,
    ];

    final optimizedPalettes = <List<int>>[];
    final seenSeeds = <String>{};
    final seenOptimized = <String>{};
    for (final seed in seeds) {
      if (!seenSeeds.add(seed.join(','))) continue;
      final optimized = _optimizeBitplanesPaletteOrder(pixels, seed);
      if (seenOptimized.add(optimized.join(','))) {
        optimizedPalettes.add(optimized);
      }
    }
    return optimizedPalettes;
  }

  static List<int> _optimizeBitplanesPaletteOrder(
    List<int> pixels,
    List<int> palette,
  ) {
    var bestPalette = List<int>.of(palette);
    var bestCost = _adaptiveBitplanesCost(pixels, bestPalette);
    final exhaustiveSwaps = palette.length <= 8;
    final passCount = exhaustiveSwaps ? 2 : 1;
    for (var pass = 0; pass < passCount; pass++) {
      var improved = false;
      var passPalette = bestPalette;
      var passCost = bestCost;
      for (var left = 0; left < bestPalette.length - 1; left++) {
        final rightLimit = exhaustiveSwaps ? bestPalette.length : left + 2;
        for (var right = left + 1; right < rightLimit; right++) {
          final candidate = List<int>.of(bestPalette);
          final value = candidate[left];
          candidate[left] = candidate[right];
          candidate[right] = value;
          final cost = _adaptiveBitplanesCost(pixels, candidate);
          if (cost < passCost) {
            passPalette = candidate;
            passCost = cost;
            improved = true;
          }
        }
      }
      if (!improved) break;
      bestPalette = passPalette;
      bestCost = passCost;
    }
    return bestPalette;
  }

  static int _adaptiveBitplanesCost(List<int> pixels, List<int> palette) {
    final indexByColor = _localIndexMap(palette);
    final localPixels = pixels
        .map((color) => indexByColor[color]!)
        .toList(growable: false);
    var cost = 0;
    for (var bit = 0; bit < _localBits(palette.length); bit++) {
      cost += _chooseAdaptiveBitplaneEncoding(localPixels, bit).bitCost;
    }
    return cost;
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

  static int _residualRunLengthsBitCost(
    List<int> runs,
    int totalLength,
  ) {
    var cost = 0;
    var consumed = 0;
    for (final length in runs) {
      if (length <= 0 || consumed + length > totalLength) {
        throw const MCOImageInvalidInputException(
          'Invalid residual run lengths',
        );
      }
      cost += _rangeCompactUintBitLength(
        length - 1,
        totalLength - consumed - 1,
      );
      consumed += length;
    }
    if (consumed != totalLength) {
      throw const MCOImageInvalidInputException(
        'Residual run lengths do not fill the input',
      );
    }
    return cost;
  }

  static void _writeResidualRunLengths(
    _V3BitWriter writer,
    List<int> runs,
    int totalLength,
  ) {
    var consumed = 0;
    for (final length in runs) {
      if (length <= 0 || consumed + length > totalLength) {
        throw const MCOImageInvalidInputException(
          'Invalid residual run lengths',
        );
      }
      writer.writeRangeCompactUint(
        length - 1,
        totalLength - consumed - 1,
      );
      consumed += length;
    }
    if (consumed != totalLength) {
      throw const MCOImageInvalidInputException(
        'Residual run lengths do not fill the input',
      );
    }
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
          _writeResidualRunLengths(
            writer,
            decision.runs,
            pixels.length,
          );
          break;
        case _V3AdaptiveBitplaneMode.shortRle:
          writer
            ..writeBits(3, 3)
            ..writeBits(decision.startingBit, 1);
          var consumed = 0;
          for (final length in decision.runs) {
            _writeShortBitplaneRunLength(
              writer,
              length,
              pixels.length - consumed,
            );
            consumed += length;
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
          _writeSparseBitplanePositions(
            writer,
            decision.minorityPositions,
            pixels.length,
          );
          break;
        case _V3AdaptiveBitplaneMode.sparseZero:
          writer.writeBits(31, 5);
          _writeSparseBitplanePositions(
            writer,
            decision.minorityPositions,
            pixels.length,
          );
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
        3 + _residualRunLengthsBitCost(runs, pixels.length),
        startingBit: startingBit,
        runs: runs,
      ),
      _V3AdaptiveBitplaneDecision(
        _V3AdaptiveBitplaneMode.shortRle,
        4 + _shortBitplaneRunsBitCost(runs, pixels.length),
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
            5 + _sparseBitplanePositionCost(onePositions, pixels.length),
            startingBit: startingBit,
            runs: runs,
            minorityPositions: onePositions,
          ),
        )
        ..add(
          _V3AdaptiveBitplaneDecision(
            _V3AdaptiveBitplaneMode.sparseZero,
            5 + _sparseBitplanePositionCost(zeroPositions, pixels.length),
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
          ? _readShortBitplaneRunLength(
              reader,
              pixelCount - position,
            )
          : reader.readRangeCompactUint(pixelCount - position - 1) + 1;
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
    final count =
        reader.readRangeCompactUint(pixelCount - 1) + 1;
    if (count > pixelCount) {
      throw const MCOImageInvalidPayloadException(
        'Sparse bitplane count exceeds pixel count',
      );
    }
    var previous = -1;
    for (var i = 0; i < count; i++) {
      final remainingPositions = count - i - 1;
      final maxGap =
          pixelCount - previous - remainingPositions - 2;
      final gap = reader.readRangeCompactUint(maxGap);
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

  static int _sparseBitplanePositionCost(
    List<int> positions,
    int pixelCount,
  ) {
    var cost = _rangeCompactUintBitLength(
      positions.length - 1,
      pixelCount - 1,
    );
    var previous = -1;
    for (var i = 0; i < positions.length; i++) {
      final position = positions[i];
      final remainingPositions = positions.length - i - 1;
      final maxGap =
          pixelCount - previous - remainingPositions - 2;
      cost += _rangeCompactUintBitLength(
        position - previous - 1,
        maxGap,
      );
      previous = position;
    }
    return cost;
  }

  static void _writeSparseBitplanePositions(
    _V3BitWriter writer,
    List<int> positions,
    int pixelCount,
  ) {
    writer.writeRangeCompactUint(
      positions.length - 1,
      pixelCount - 1,
    );
    var previous = -1;
    for (var i = 0; i < positions.length; i++) {
      final position = positions[i];
      final remainingPositions = positions.length - i - 1;
      final maxGap =
          pixelCount - previous - remainingPositions - 2;
      writer.writeRangeCompactUint(
        position - previous - 1,
        maxGap,
      );
      previous = position;
    }
  }

  static void _writeShortBitplaneRunLength(
    _V3BitWriter writer,
    int length,
    int remainingLength,
  ) {
    if (length <= 0 ||
        remainingLength <= 0 ||
        length > remainingLength) {
      throw const MCOImageInvalidInputException('Invalid bitplane run');
    }
    if (length <= 3) {
      writer.writeBits((1 << (length - 1)) - 1, length);
      return;
    }
    writer
      ..writeBits(7, 3)
      ..writeRangeCompactUint(
        length - 4,
        remainingLength - 4,
      );
  }

  static int _readShortBitplaneRunLength(
    _V3BitReader reader,
    int remainingLength,
  ) {
    if (remainingLength <= 0) {
      throw const MCOImageInvalidPayloadException(
        'Invalid remaining bitplane run length',
      );
    }
    if (reader.readBits(1) == 0) return 1;
    if (remainingLength < 2) {
      throw const MCOImageInvalidPayloadException(
        'Bitplane run exceeds remaining pixels',
      );
    }
    if (reader.readBits(1) == 0) return 2;
    if (remainingLength < 3) {
      throw const MCOImageInvalidPayloadException(
        'Bitplane run exceeds remaining pixels',
      );
    }
    if (reader.readBits(1) == 0) return 3;
    if (remainingLength < 4) {
      throw const MCOImageInvalidPayloadException(
        'Bitplane run exceeds remaining pixels',
      );
    }
    return reader.readRangeCompactUint(remainingLength - 4) + 4;
  }

  static int _shortBitplaneRunsBitCost(
    List<int> runs,
    int totalLength,
  ) {
    var cost = 0;
    var consumed = 0;
    for (final length in runs) {
      cost += _shortBitplaneRunBitLength(
        length,
        totalLength - consumed,
      );
      consumed += length;
    }
    if (consumed != totalLength) {
      throw const MCOImageInvalidInputException(
        'Short bitplane runs do not fill the input',
      );
    }
    return cost;
  }

  static int _shortBitplaneRunBitLength(
    int length,
    int remainingLength,
  ) {
    if (length <= 0 ||
        remainingLength <= 0 ||
        length > remainingLength) {
      throw const MCOImageInvalidInputException('Invalid bitplane run');
    }
    if (length <= 3) return length;
    return 3 +
        _rangeCompactUintBitLength(
          length - 4,
          remainingLength - 4,
        );
  }

  static void _writeRowDeltaBody(
    _V3BitWriter writer,
    List<int> values,
    int rowLength,
    int valueBits,
  ) {
    if (rowLength <= 0 || values.length % rowLength != 0) {
      throw const MCOImageInvalidInputException(
        'Invalid row-delta geometry',
      );
    }
    if (values.isEmpty) return;

    final noShiftRawCost = _rowDeltaBodyVariantBitCost(
      values,
      rowLength,
      valueBits,
      useVirtualBaseRow: false,
      allowShiftPredictors: false,
    );
    final noShiftVirtualCost = _rowDeltaBodyVariantBitCost(
      values,
      rowLength,
      valueBits,
      useVirtualBaseRow: true,
      allowShiftPredictors: false,
    );
    final shiftRawCost = _rowDeltaBodyVariantBitCost(
      values,
      rowLength,
      valueBits,
      useVirtualBaseRow: false,
      allowShiftPredictors: true,
    );
    final shiftVirtualCost = _rowDeltaBodyVariantBitCost(
      values,
      rowLength,
      valueBits,
      useVirtualBaseRow: true,
      allowShiftPredictors: true,
    );

    final noShiftCost = math.min(noShiftRawCost, noShiftVirtualCost);
    final shiftCost = math.min(shiftRawCost, shiftVirtualCost);
    final allowShiftPredictors = shiftCost < noShiftCost;
    final useVirtualBaseRow = allowShiftPredictors
        ? shiftVirtualCost < shiftRawCost
        : noShiftVirtualCost < noShiftRawCost;

    writer
      ..writeBits(useVirtualBaseRow ? 1 : 0, 1)
      ..writeBits(allowShiftPredictors ? 1 : 0, 1);
    _writeRowDeltaBodyVariant(
      writer,
      values,
      rowLength,
      valueBits,
      useVirtualBaseRow: useVirtualBaseRow,
      allowShiftPredictors: allowShiftPredictors,
    );
  }

  static int _rowDeltaBodyVariantBitCost(
    List<int> values,
    int rowLength,
    int valueBits, {
    required bool useVirtualBaseRow,
    required bool allowShiftPredictors,
  }) {
    var cost = useVirtualBaseRow ? 0 : rowLength * valueBits;
    final rowCount = values.length ~/ rowLength;
    var row = useVirtualBaseRow ? 0 : 1;
    while (row < rowCount) {
      final repeatCount = _compactRepeatedRowCount(
        values,
        rowLength,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
      );
      if (repeatCount >= 2) {
        final repeatRunCost = _rowDeltaOpBits +
            _rowDeltaExtendedBits +
            _rangeCompactUintBitLength(
              repeatCount - 2,
              rowCount - row - 2,
            );
        if (repeatRunCost < repeatCount * _rowDeltaOpBits) {
          cost += repeatRunCost;
          row += repeatCount;
          continue;
        }
      }

      cost += _bestRowDeltaDecision(
        values,
        rowLength,
        valueBits,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
        allowShiftPredictors: allowShiftPredictors,
      ).bitCost;
      row++;
    }
    return cost;
  }

  static void _writeRowDeltaBodyVariant(
    _V3BitWriter writer,
    List<int> values,
    int rowLength,
    int valueBits, {
    required bool useVirtualBaseRow,
    required bool allowShiftPredictors,
  }) {
    if (!useVirtualBaseRow) {
      for (var x = 0; x < rowLength; x++) {
        writer.writeBits(values[x], valueBits);
      }
    }

    final rowCount = values.length ~/ rowLength;
    var row = useVirtualBaseRow ? 0 : 1;
    while (row < rowCount) {
      final repeatCount = _compactRepeatedRowCount(
        values,
        rowLength,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
      );
      if (repeatCount >= 2) {
        final repeatRunCost = _rowDeltaOpBits +
            _rowDeltaExtendedBits +
            _rangeCompactUintBitLength(
              repeatCount - 2,
              rowCount - row - 2,
            );
        if (repeatRunCost < repeatCount * _rowDeltaOpBits) {
          writer
            ..writeBits(_rowDeltaOpExtended, _rowDeltaOpBits)
            ..writeBits(
              _rowDeltaExtendedRepeatRun,
              _rowDeltaExtendedBits,
            )
            ..writeRangeCompactUint(
              repeatCount - 2,
              rowCount - row - 2,
            );
          row += repeatCount;
          continue;
        }
      }

      final decision = _bestRowDeltaDecision(
        values,
        rowLength,
        valueBits,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
        allowShiftPredictors: allowShiftPredictors,
      );
      _writeRowDeltaDecision(
        writer,
        values,
        rowLength,
        valueBits,
        row,
        decision,
        allowShiftPredictors: allowShiftPredictors,
      );
      row++;
    }
  }

  static _V3RowDeltaDecision _bestRowDeltaDecision(
    List<int> values,
    int rowLength,
    int valueBits,
    int row, {
    required bool useVirtualBaseRow,
    required bool allowShiftPredictors,
  }) {
    _V3RowDeltaDecision best = _V3RowDeltaDecision(
      op: _rowDeltaOpRaw,
      extendedOp: -1,
      predictor: _rowDeltaPredictorSame,
      changes: const <_V3RowDeltaChange>[],
      bitCost: _rowDeltaOpBits + rowLength * valueBits,
    );
    final predictors = allowShiftPredictors
        ? _rowDeltaPredictorsForRow(
            row,
            useVirtualBaseRow: useVirtualBaseRow,
          )
        : const <int>[_rowDeltaPredictorSame];

    for (final predictor in predictors) {
      final changes = _compactRowDeltaChanges(
        values,
        rowLength,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
        predictor: predictor,
      );
      if (changes.isEmpty && predictor == _rowDeltaPredictorSame) {
        final repeat = _V3RowDeltaDecision(
          op: _rowDeltaOpRepeat,
          extendedOp: -1,
          predictor: predictor,
          changes: changes,
          bitCost: _rowDeltaOpBits,
        );
        if (repeat.bitCost < best.bitCost) best = repeat;
        continue;
      }

      final predictorCost = allowShiftPredictors
          ? _compactPredictorBitCost(predictor)
          : 0;
      final positionBits = (rowLength - 1).bitLength;
      final indexedCost = _rowDeltaOpBits +
          predictorCost +
          rowLength.bitLength +
          changes.length * (positionBits + valueBits);
      if (indexedCost < best.bitCost) {
        best = _V3RowDeltaDecision(
          op: _rowDeltaOpIndexed,
          extendedOp: -1,
          predictor: predictor,
          changes: changes,
          bitCost: indexedCost,
        );
      }
      if (changes.isEmpty) continue;

      final maskCost = _rowDeltaOpBits +
          _rowDeltaExtendedBits +
          predictorCost +
          rowLength +
          changes.length * valueBits;
      if (maskCost < best.bitCost) {
        best = _V3RowDeltaDecision(
          op: _rowDeltaOpExtended,
          extendedOp: _rowDeltaExtendedMask,
          predictor: predictor,
          changes: changes,
          bitCost: maskCost,
        );
      }

      final segments = _rowDeltaSegments(changes);
      final segmentGeometryCost = (rowLength - 1).bitLength +
          segments.length * positionBits * 2;
      final segmentCost = _rowDeltaOpBits +
          _rowDeltaExtendedBits +
          predictorCost +
          segmentGeometryCost +
          changes.length * valueBits;
      if (segmentCost < best.bitCost) {
        best = _V3RowDeltaDecision(
          op: _rowDeltaOpExtended,
          extendedOp: _rowDeltaExtendedSegments,
          predictor: predictor,
          changes: changes,
          bitCost: segmentCost,
        );
      }

      final sameValue = _sameRowDeltaChangeValue(changes);
      if (sameValue != null) {
        final sameScalarMaskCost = _rowDeltaOpBits +
            _rowDeltaExtendedBits +
            predictorCost +
            rowLength +
            valueBits;
        if (sameScalarMaskCost < best.bitCost) {
          best = _V3RowDeltaDecision(
            op: _rowDeltaOpExtended,
            extendedOp: _rowDeltaExtendedSameScalarMask,
            predictor: predictor,
            changes: changes,
            bitCost: sameScalarMaskCost,
          );
        }
      }
    }
    return best;
  }

  static void _writeRowDeltaDecision(
    _V3BitWriter writer,
    List<int> values,
    int rowLength,
    int valueBits,
    int row,
    _V3RowDeltaDecision decision, {
    required bool allowShiftPredictors,
  }) {
    writer.writeBits(decision.op, _rowDeltaOpBits);
    if (decision.op == _rowDeltaOpRepeat) return;
    if (decision.op == _rowDeltaOpRaw) {
      final rowStart = row * rowLength;
      for (var x = 0; x < rowLength; x++) {
        writer.writeBits(values[rowStart + x], valueBits);
      }
      return;
    }

    if (decision.op == _rowDeltaOpIndexed) {
      if (allowShiftPredictors) {
        _writeCompactRowDeltaPredictor(writer, decision.predictor);
      }
      final positionBits = (rowLength - 1).bitLength;
      writer.writeBits(decision.changes.length, rowLength.bitLength);
      for (final change in decision.changes) {
        writer
          ..writeBits(change.x, positionBits)
          ..writeBits(change.value, valueBits);
      }
      return;
    }

    if (decision.op != _rowDeltaOpExtended ||
        decision.extendedOp == _rowDeltaExtendedRepeatRun) {
      throw const MCOImageInvalidInputException(
        'Invalid row-delta decision',
      );
    }
    writer.writeBits(decision.extendedOp, _rowDeltaExtendedBits);
    if (allowShiftPredictors) {
      _writeCompactRowDeltaPredictor(writer, decision.predictor);
    }
    switch (decision.extendedOp) {
      case _rowDeltaExtendedMask:
        _writeRowDeltaMask(
          writer,
          decision.changes,
          rowLength,
          valueBits,
        );
        break;
      case _rowDeltaExtendedSegments:
        _writeRowDeltaSegments(
          writer,
          decision.changes,
          rowLength,
          valueBits,
        );
        break;
      case _rowDeltaExtendedSameScalarMask:
        _writeRowDeltaSameScalarMask(
          writer,
          decision.changes,
          rowLength,
          valueBits,
        );
        break;
      default:
        throw const MCOImageInvalidInputException(
          'Invalid row-delta extended op',
        );
    }
  }

  static void _writeRowDeltaMask(
    _V3BitWriter writer,
    List<_V3RowDeltaChange> changes,
    int rowLength,
    int valueBits,
  ) {
    var changeIndex = 0;
    for (var x = 0; x < rowLength; x++) {
      final changed = changeIndex < changes.length &&
          changes[changeIndex].x == x;
      writer.writeBits(changed ? 1 : 0, 1);
      if (changed) changeIndex++;
    }
    for (final change in changes) {
      writer.writeBits(change.value, valueBits);
    }
  }

  static void _writeRowDeltaSameScalarMask(
    _V3BitWriter writer,
    List<_V3RowDeltaChange> changes,
    int rowLength,
    int valueBits,
  ) {
    final value = _sameRowDeltaChangeValue(changes);
    if (value == null) {
      throw const MCOImageInvalidInputException(
        'Row-delta changes are not same-scalar',
      );
    }
    var changeIndex = 0;
    for (var x = 0; x < rowLength; x++) {
      final changed = changeIndex < changes.length &&
          changes[changeIndex].x == x;
      writer.writeBits(changed ? 1 : 0, 1);
      if (changed) changeIndex++;
    }
    writer.writeBits(value, valueBits);
  }

  static void _writeRowDeltaSegments(
    _V3BitWriter writer,
    List<_V3RowDeltaChange> changes,
    int rowLength,
    int valueBits,
  ) {
    final segments = _rowDeltaSegments(changes);
    final positionBits = (rowLength - 1).bitLength;
    writer.writeBits(
      segments.length - 1,
      (rowLength - 1).bitLength,
    );
    for (final segment in segments) {
      writer
        ..writeBits(segment.x, positionBits)
        ..writeBits(segment.length - 1, positionBits);
      for (final value in segment.values) {
        writer.writeBits(value, valueBits);
      }
    }
  }

  static List<int> _readRowDeltaBody(
    _V3BitReader reader,
    int count,
    int rowLength,
    int valueBits, {
    required int maxValue,
  }) {
    if (rowLength <= 0 || count % rowLength != 0) {
      throw const MCOImageInvalidPayloadException(
        'Invalid row-delta geometry',
      );
    }
    if (count == 0) return const <int>[];

    final useVirtualBaseRow = reader.readBits(1) != 0;
    final allowShiftPredictors = reader.readBits(1) != 0;
    final result = List<int>.filled(count, 0);
    if (!useVirtualBaseRow) {
      for (var x = 0; x < rowLength; x++) {
        result[x] = _readRowDeltaValue(reader, valueBits, maxValue);
      }
    }

    final rowCount = count ~/ rowLength;
    var row = useVirtualBaseRow ? 0 : 1;
    while (row < rowCount) {
      final rowStart = row * rowLength;
      final op = reader.readBits(_rowDeltaOpBits);
      if (op == _rowDeltaOpRaw) {
        for (var x = 0; x < rowLength; x++) {
          result[rowStart + x] =
              _readRowDeltaValue(reader, valueBits, maxValue);
        }
        row++;
        continue;
      }
      if (op == _rowDeltaOpRepeat) {
        _copyCompactRowDeltaPredictedRow(
          result,
          rowStart,
          rowLength,
          row,
          _rowDeltaPredictorSame,
          useVirtualBaseRow: useVirtualBaseRow,
        );
        row++;
        continue;
      }
      if (op == _rowDeltaOpIndexed) {
        final predictor = _readRowDeltaPredictor(
          reader,
          row,
          useVirtualBaseRow: useVirtualBaseRow,
          allowShiftPredictors: allowShiftPredictors,
        );
        _copyCompactRowDeltaPredictedRow(
          result,
          rowStart,
          rowLength,
          row,
          predictor,
          useVirtualBaseRow: useVirtualBaseRow,
        );
        final changeCount = reader.readBits(rowLength.bitLength);
        if (changeCount > rowLength) {
          throw const MCOImageInvalidPayloadException(
            'Row-delta change count exceeds row length',
          );
        }
        final positionBits = (rowLength - 1).bitLength;
        var previousX = -1;
        for (var i = 0; i < changeCount; i++) {
          final x = reader.readBits(positionBits);
          if (x >= rowLength || x <= previousX) {
            throw const MCOImageInvalidPayloadException(
              'Invalid row-delta change position',
            );
          }
          result[rowStart + x] =
              _readRowDeltaValue(reader, valueBits, maxValue);
          previousX = x;
        }
        row++;
        continue;
      }
      if (op != _rowDeltaOpExtended) {
        throw const MCOImageInvalidPayloadException(
          'Unknown row-delta row op',
        );
      }

      final extendedOp = reader.readBits(_rowDeltaExtendedBits);
      if (extendedOp == _rowDeltaExtendedRepeatRun) {
        if (row + 2 > rowCount) {
          throw const MCOImageInvalidPayloadException(
            'Invalid row-delta repeat run',
          );
        }
        final repeatCount =
            reader.readRangeCompactUint(rowCount - row - 2) + 2;
        for (var repeat = 0; repeat < repeatCount; repeat++) {
          final repeatRow = row + repeat;
          _copyCompactRowDeltaPredictedRow(
            result,
            repeatRow * rowLength,
            rowLength,
            repeatRow,
            _rowDeltaPredictorSame,
            useVirtualBaseRow: useVirtualBaseRow,
          );
        }
        row += repeatCount;
        continue;
      }

      final predictor = _readRowDeltaPredictor(
        reader,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
        allowShiftPredictors: allowShiftPredictors,
      );
      _copyCompactRowDeltaPredictedRow(
        result,
        rowStart,
        rowLength,
        row,
        predictor,
        useVirtualBaseRow: useVirtualBaseRow,
      );
      switch (extendedOp) {
        case _rowDeltaExtendedMask:
          _readRowDeltaMask(
            reader,
            result,
            rowStart,
            rowLength,
            valueBits,
            maxValue,
            sameScalar: false,
          );
          break;
        case _rowDeltaExtendedSegments:
          _readRowDeltaSegments(
            reader,
            result,
            rowStart,
            rowLength,
            valueBits,
            maxValue,
          );
          break;
        case _rowDeltaExtendedSameScalarMask:
          _readRowDeltaMask(
            reader,
            result,
            rowStart,
            rowLength,
            valueBits,
            maxValue,
            sameScalar: true,
          );
          break;
        default:
          throw const MCOImageInvalidPayloadException(
            'Unknown row-delta extended op',
          );
      }
      row++;
    }
    return result;
  }

  static int _readRowDeltaPredictor(
    _V3BitReader reader,
    int row, {
    required bool useVirtualBaseRow,
    required bool allowShiftPredictors,
  }) {
    if (!allowShiftPredictors) return _rowDeltaPredictorSame;
    final predictor = _readCompactRowDeltaPredictor(reader);
    if (row == 0 &&
        useVirtualBaseRow &&
        predictor != _rowDeltaPredictorSame) {
      throw const MCOImageInvalidPayloadException(
        'Shifted row-delta predictor cannot use virtual row',
      );
    }
    return predictor;
  }

  static int _readRowDeltaValue(
    _V3BitReader reader,
    int valueBits,
    int maxValue,
  ) {
    final value = reader.readBits(valueBits);
    if (value > maxValue) {
      throw const MCOImageInvalidPayloadException(
        'Row-delta value out of range',
      );
    }
    return value;
  }

  static void _readRowDeltaMask(
    _V3BitReader reader,
    List<int> result,
    int rowStart,
    int rowLength,
    int valueBits,
    int maxValue, {
    required bool sameScalar,
  }) {
    final positions = <int>[];
    for (var x = 0; x < rowLength; x++) {
      if (reader.readBits(1) != 0) positions.add(x);
    }
    if (positions.isEmpty) {
      throw const MCOImageInvalidPayloadException(
        'Empty row-delta mask',
      );
    }
    if (sameScalar) {
      final value = _readRowDeltaValue(reader, valueBits, maxValue);
      for (final x in positions) {
        result[rowStart + x] = value;
      }
      return;
    }
    for (final x in positions) {
      result[rowStart + x] =
          _readRowDeltaValue(reader, valueBits, maxValue);
    }
  }

  static void _readRowDeltaSegments(
    _V3BitReader reader,
    List<int> result,
    int rowStart,
    int rowLength,
    int valueBits,
    int maxValue,
  ) {
    final positionBits = (rowLength - 1).bitLength;
    final segmentCount =
        reader.readBits((rowLength - 1).bitLength) + 1;
    var previousEnd = -1;
    for (var i = 0; i < segmentCount; i++) {
      final start = reader.readBits(positionBits);
      final length = reader.readBits(positionBits) + 1;
      if (start <= previousEnd || start + length > rowLength) {
        throw const MCOImageInvalidPayloadException(
          'Invalid row-delta segment',
        );
      }
      for (var x = start; x < start + length; x++) {
        result[rowStart + x] =
            _readRowDeltaValue(reader, valueBits, maxValue);
      }
      previousEnd = start + length - 1;
    }
  }

  static void _writeCompactRowDeltaBody(
    _V3BitWriter writer,
    List<int> values,
    int rowLength,
    int valueBits, {
    required bool directGrayscale,
  }) {
    if (rowLength <= 0 || values.length % rowLength != 0) {
      throw const MCOImageInvalidInputException(
        'Invalid compact row-delta geometry',
      );
    }
    final rawFirstCost = _compactRowDeltaBodyBitCost(
      values,
      rowLength,
      valueBits,
      directGrayscale: directGrayscale,
      useVirtualBaseRow: false,
    );
    final virtualCost = _compactRowDeltaBodyBitCost(
      values,
      rowLength,
      valueBits,
      directGrayscale: directGrayscale,
      useVirtualBaseRow: true,
    );
    final useVirtualBaseRow = virtualCost < rawFirstCost;
    writer.writeBits(useVirtualBaseRow ? 1 : 0, 1);
    if (!useVirtualBaseRow) {
      for (var x = 0; x < rowLength; x++) {
        writer.writeBits(values[x], valueBits);
      }
    }

    final rowCount = values.length ~/ rowLength;
    var row = useVirtualBaseRow ? 0 : 1;
    while (row < rowCount) {
      final repeatCount = _compactRepeatedRowCount(
        values,
        rowLength,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
      );
      if (repeatCount >= 2) {
        writer
          ..writeBits(_compactRowDeltaOpRepeatRun, _compactRowDeltaOpBits)
          ..writeRangeCompactUint(
            repeatCount - 2,
            rowCount - row - 2,
          );
        row += repeatCount;
        continue;
      }

      final decision = _bestCompactRowDeltaDecision(
        values,
        rowLength,
        valueBits,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
        directGrayscale: directGrayscale,
      );
      _writeCompactRowDeltaDecision(
        writer,
        values,
        rowLength,
        valueBits,
        row,
        decision,
        useVirtualBaseRow: useVirtualBaseRow,
        directGrayscale: directGrayscale,
      );
      row++;
    }
  }

  static List<int> _readCompactRowDeltaBody(
    _V3BitReader reader,
    int count,
    int rowLength,
    int valueBits, {
    required bool directGrayscale,
    required int maxValue,
  }) {
    if (rowLength <= 0 || count % rowLength != 0) {
      throw const MCOImageInvalidPayloadException(
        'Invalid compact row-delta geometry',
      );
    }
    final useVirtualBaseRow = reader.readBits(1) != 0;
    final result = List<int>.filled(count, 0);
    if (!useVirtualBaseRow) {
      for (var x = 0; x < rowLength; x++) {
        final value = reader.readBits(valueBits);
        if (value > maxValue) {
          throw const MCOImageInvalidPayloadException(
            'Compact row-delta first row value out of range',
          );
        }
        result[x] = value;
      }
    }

    final rowCount = count ~/ rowLength;
    var row = useVirtualBaseRow ? 0 : 1;
    while (row < rowCount) {
      final rowStart = row * rowLength;
      final op = reader.readBits(_compactRowDeltaOpBits);
      if (op == _compactRowDeltaOpRepeat ||
          op == _compactRowDeltaOpRepeatRun) {
        final repeatCount = op == _compactRowDeltaOpRepeat
            ? 1
            : reader.readRangeCompactUint(rowCount - row - 2) + 2;
        if (row + repeatCount > rowCount) {
          throw const MCOImageInvalidPayloadException(
            'Compact row-delta repeat exceeds row count',
          );
        }
        for (var repeat = 0; repeat < repeatCount; repeat++) {
          final repeatRow = row + repeat;
          final repeatStart = repeatRow * rowLength;
          _copyCompactRowDeltaPredictedRow(
            result,
            repeatStart,
            rowLength,
            repeatRow,
            _rowDeltaPredictorSame,
            useVirtualBaseRow: useVirtualBaseRow,
          );
        }
        row += repeatCount;
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
        row++;
        continue;
      }

      final predictor = _readCompactRowDeltaPredictor(reader);
      if (row == 0 &&
          useVirtualBaseRow &&
          predictor != _rowDeltaPredictorSame) {
        throw const MCOImageInvalidPayloadException(
          'Shifted compact predictor cannot use virtual row',
        );
      }
      _copyCompactRowDeltaPredictedRow(
        result,
        rowStart,
        rowLength,
        row,
        predictor,
        useVirtualBaseRow: useVirtualBaseRow,
      );
      if (op == _compactRowDeltaOpPredicted) {
        row++;
        continue;
      }

      final useResidual = directGrayscale && reader.readBits(1) != 0;
      if (op == _compactRowDeltaOpIndexed ||
          op == _compactRowDeltaOpSameScalar) {
        final changeCount =
            reader.readRangeCompactUint(rowLength - 1) + 1;
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
        if (op == _compactRowDeltaOpSameScalar) {
          final value = _readCompactRowDeltaValue(
            reader,
            result,
            rowLength,
            row,
            positions.first,
            valueBits,
            predictor,
            useVirtualBaseRow: useVirtualBaseRow,
            useResidual: useResidual,
            maxValue: maxValue,
          );
          for (final x in positions) {
            result[rowStart + x] = value;
          }
        } else {
          for (final x in positions) {
            result[rowStart + x] = _readCompactRowDeltaValue(
             reader,
             result,
             rowLength,
             row,
             x,
              valueBits,
              predictor,
              useVirtualBaseRow: useVirtualBaseRow,
              useResidual: useResidual,
              maxValue: maxValue,
            );
          }
        }
        row++;
        continue;
      }

      if (op == _compactRowDeltaOpSegments ||
          op == _compactRowDeltaOpTrimmedMask) {
        final positions = <int>[];
        if (op == _compactRowDeltaOpSegments) {
          final segmentCount =
              reader.readRangeCompactUint(rowLength - 1) + 1;
          if (segmentCount > rowLength) {
            throw const MCOImageInvalidPayloadException(
              'Compact row-delta segment count exceeds row length',
            );
          }
          var previousEnd = 0;
          for (var i = 0; i < segmentCount; i++) {
            final remainingSegments = segmentCount - i - 1;
            final maxGap =
                rowLength - previousEnd - remainingSegments - 1;
            final gap = reader.readRangeCompactUint(maxGap);
            final start = previousEnd + gap;
            final maxLength =
                rowLength - start - remainingSegments;
            final length =
                reader.readRangeCompactUint(maxLength - 1) + 1;
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
          final start =
              reader.readRangeCompactUint(rowLength - 1);
          final span = reader.readRangeCompactUint(
                rowLength - start - 1,
              ) +
              1;
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
          result[rowStart + x] = _readCompactRowDeltaValue(
            reader,
            result,
            rowLength,
            row,
            x,
            valueBits,
            predictor,
            useVirtualBaseRow: useVirtualBaseRow,
            useResidual: useResidual,
            maxValue: maxValue,
          );
        }
        row++;
        continue;
      }
      throw const MCOImageInvalidPayloadException(
        'Unsupported compact row-delta op',
      );
    }
    return result;
  }

  static int _compactRowDeltaBodyBitCost(
    List<int> values,
    int rowLength,
    int valueBits, {
    required bool directGrayscale,
    required bool useVirtualBaseRow,
  }) {
    var cost = useVirtualBaseRow ? 0 : rowLength * valueBits;
    final rowCount = values.length ~/ rowLength;
    var row = useVirtualBaseRow ? 0 : 1;
    while (row < rowCount) {
      final repeatCount = _compactRepeatedRowCount(
        values,
        rowLength,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
      );
      if (repeatCount >= 2) {
        cost += _compactRowDeltaOpBits +
            _rangeCompactUintBitLength(
              repeatCount - 2,
              rowCount - row - 2,
            );
        row += repeatCount;
        continue;
      }
      cost += _bestCompactRowDeltaDecision(
        values,
        rowLength,
        valueBits,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
        directGrayscale: directGrayscale,
      ).bitCost;
      row++;
    }
    return cost;
  }

  static int _compactRepeatedRowCount(
    List<int> values,
    int rowLength,
    int startRow, {
    required bool useVirtualBaseRow,
  }) {
    final rowCount = values.length ~/ rowLength;
    var count = 0;
    for (var row = startRow; row < rowCount; row++) {
      final rowStart = row * rowLength;
      var same = true;
      for (var x = 0; x < rowLength; x++) {
        final expected = row == 0 && useVirtualBaseRow
            ? 0
            : values[rowStart - rowLength + x];
        if (values[rowStart + x] != expected) {
          same = false;
          break;
        }
      }
      if (!same) break;
      count++;
    }
    return count;
  }

  static List<_V3RowDeltaChange> _compactRowDeltaChanges(
    List<int> values,
    int rowLength,
    int row, {
    required bool useVirtualBaseRow,
    required int predictor,
  }) {
    final changes = <_V3RowDeltaChange>[];
    final rowStart = row * rowLength;
    for (var x = 0; x < rowLength; x++) {
      final value = values[rowStart + x];
      if (value !=
          _compactRowDeltaPredictedValue(
            values,
            rowLength,
            row,
            x,
            predictor,
            useVirtualBaseRow: useVirtualBaseRow,
          )) {
        changes.add(_V3RowDeltaChange(x, value));
      }
    }
    return changes;
  }

  static _V3CompactRowDeltaDecision _bestCompactRowDeltaDecision(
    List<int> values,
    int rowLength,
    int valueBits,
    int row, {
    required bool useVirtualBaseRow,
    required bool directGrayscale,
  }) {
    var best = _V3CompactRowDeltaDecision(
      op: _compactRowDeltaOpRaw,
      predictor: _rowDeltaPredictorSame,
      changes: const <_V3RowDeltaChange>[],
      useResidual: false,
      bitCost: _compactRowDeltaOpBits + rowLength * valueBits,
    );

    for (final predictor in _rowDeltaPredictorsForRow(
      row,
      useVirtualBaseRow: useVirtualBaseRow,
    )) {
      final changes = _compactRowDeltaChanges(
        values,
        rowLength,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
        predictor: predictor,
      );
      if (changes.isEmpty) {
        final decision = _V3CompactRowDeltaDecision(
          op: predictor == _rowDeltaPredictorSame
              ? _compactRowDeltaOpRepeat
              : _compactRowDeltaOpPredicted,
          predictor: predictor,
          changes: const <_V3RowDeltaChange>[],
          useResidual: false,
          bitCost: _compactRowDeltaOpBits +
              (predictor == _rowDeltaPredictorSame
                  ? 0
                  : _compactPredictorBitCost(predictor)),
        );
        if (decision.bitCost < best.bitCost) best = decision;
        continue;
      }

      final predictorCost = _compactPredictorBitCost(predictor);
      final indexedCost = _compactRowDeltaOpBits +
          predictorCost +
          _rangeCompactUintBitLength(
            changes.length - 1,
            rowLength - 1,
          ) +
          _compactChangePositionsBitCost(changes, rowLength) +
          _bestCompactValueEncoding(
            values,
            rowLength,
            row,
            changes,
            valueBits,
            predictor,
            useVirtualBaseRow: useVirtualBaseRow,
            directGrayscale: directGrayscale,
          ).bitCost;
      if (indexedCost < best.bitCost) {
        final valuesEncoding = _bestCompactValueEncoding(
          values,
          rowLength,
          row,
          changes,
          valueBits,
          predictor,
          useVirtualBaseRow: useVirtualBaseRow,
          directGrayscale: directGrayscale,
        );
        best = _V3CompactRowDeltaDecision(
          op: _compactRowDeltaOpIndexed,
          predictor: predictor,
          changes: changes,
          useResidual: valuesEncoding.useResidual,
          bitCost: indexedCost,
        );
      }

      final sameScalar = _bestCompactSameScalarEncoding(
        values,
        rowLength,
        row,
        changes,
        valueBits,
        predictor,
        useVirtualBaseRow: useVirtualBaseRow,
        directGrayscale: directGrayscale,
      );
      if (sameScalar != null) {
        final sameScalarCost = _compactRowDeltaOpBits +
            predictorCost +
            _rangeCompactUintBitLength(
            changes.length - 1,
            rowLength - 1,
          ) +
            _compactChangePositionsBitCost(changes, rowLength) +
            sameScalar.bitCost;
        if (sameScalarCost < best.bitCost) {
          best = _V3CompactRowDeltaDecision(
            op: _compactRowDeltaOpSameScalar,
            predictor: predictor,
            changes: changes,
            useResidual: sameScalar.useResidual,
            bitCost: sameScalarCost,
          );
        }
      }

      final valuesEncoding = _bestCompactValueEncoding(
        values,
        rowLength,
        row,
        changes,
        valueBits,
        predictor,
        useVirtualBaseRow: useVirtualBaseRow,
        directGrayscale: directGrayscale,
      );
      final segments = _rowDeltaSegments(changes);
      var segmentGeometryCost = _rangeCompactUintBitLength(
        segments.length - 1,
        rowLength - 1,
      );
      var previousEnd = 0;
      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final remainingSegments = segments.length - i - 1;
        final gap = segment.x - previousEnd;
        final maxGap =
            rowLength - previousEnd - remainingSegments - 1;
        final maxLength =
            rowLength - segment.x - remainingSegments;
        segmentGeometryCost +=
            _rangeCompactUintBitLength(gap, maxGap) +
            _rangeCompactUintBitLength(
              segment.length - 1,
              maxLength - 1,
            );
        previousEnd = segment.x + segment.length;
      }
      final segmentCost = _compactRowDeltaOpBits +
          predictorCost +
          segmentGeometryCost +
          valuesEncoding.bitCost;
      if (segmentCost < best.bitCost) {
        best = _V3CompactRowDeltaDecision(
          op: _compactRowDeltaOpSegments,
          predictor: predictor,
          changes: changes,
          useResidual: valuesEncoding.useResidual,
          bitCost: segmentCost,
        );
      }

      final span = changes.last.x - changes.first.x + 1;
      final maskCost = _compactRowDeltaOpBits +
          predictorCost +
          _rangeCompactUintBitLength(
            changes.first.x,
            rowLength - 1,
          ) +
          _rangeCompactUintBitLength(
            span - 1,
            rowLength - changes.first.x - 1,
          ) +
          span +
          valuesEncoding.bitCost;
      if (maskCost < best.bitCost) {
        best = _V3CompactRowDeltaDecision(
          op: _compactRowDeltaOpTrimmedMask,
          predictor: predictor,
          changes: changes,
          useResidual: valuesEncoding.useResidual,
          bitCost: maskCost,
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
    _V3CompactRowDeltaDecision decision, {
    required bool useVirtualBaseRow,
    required bool directGrayscale,
  }) {
    writer.writeBits(decision.op, _compactRowDeltaOpBits);
    if (decision.op == _compactRowDeltaOpRepeat) return;
    final rowStart = row * rowLength;
    if (decision.op == _compactRowDeltaOpRaw) {
      for (var x = 0; x < rowLength; x++) {
        writer.writeBits(values[rowStart + x], valueBits);
      }
      return;
    }

    _writeCompactRowDeltaPredictor(writer, decision.predictor);
    if (decision.op == _compactRowDeltaOpPredicted) return;
    if (directGrayscale) {
      writer.writeBits(decision.useResidual ? 1 : 0, 1);
    }
    final changes = decision.changes;
    switch (decision.op) {
      case _compactRowDeltaOpIndexed:
        writer.writeRangeCompactUint(
          changes.length - 1,
          rowLength - 1,
        );
        _writeCompactChangePositions(writer, changes, rowLength);
        _writeCompactChangedValues(
          writer,
          values,
          rowLength,
          valueBits,
          row,
          changes,
          decision.predictor,
          useVirtualBaseRow: useVirtualBaseRow,
          useResidual: decision.useResidual,
        );
        break;
      case _compactRowDeltaOpSameScalar:
        writer.writeRangeCompactUint(
          changes.length - 1,
          rowLength - 1,
        );
        _writeCompactChangePositions(writer, changes, rowLength);
        if (decision.useResidual) {
          final delta = _compactGrayscaleDelta(
            values,
            rowLength,
            row,
            changes.first,
            decision.predictor,
            useVirtualBaseRow: useVirtualBaseRow,
          );
          writer.writeCompactUint(_grayscaleDeltaCode(delta) - 1);
        } else {
          writer.writeBits(changes.first.value, valueBits);
        }
        break;
      case _compactRowDeltaOpSegments:
        final segments = _rowDeltaSegments(changes);
        writer.writeRangeCompactUint(
          segments.length - 1,
          rowLength - 1,
        );
        var previousEnd = 0;
        for (var i = 0; i < segments.length; i++) {
          final segment = segments[i];
          final remainingSegments = segments.length - i - 1;
          final gap = segment.x - previousEnd;
          final maxGap =
              rowLength - previousEnd - remainingSegments - 1;
          final maxLength =
              rowLength - segment.x - remainingSegments;
          writer
            ..writeRangeCompactUint(gap, maxGap)
            ..writeRangeCompactUint(
              segment.length - 1,
              maxLength - 1,
            );
          previousEnd = segment.x + segment.length;
        }
        _writeCompactChangedValues(
          writer,
          values,
          rowLength,
          valueBits,
          row,
          changes,
          decision.predictor,
          useVirtualBaseRow: useVirtualBaseRow,
          useResidual: decision.useResidual,
        );
        break;
      case _compactRowDeltaOpTrimmedMask:
        final start = changes.first.x;
        final span = changes.last.x - start + 1;
        writer
          ..writeRangeCompactUint(start, rowLength - 1)
          ..writeRangeCompactUint(
            span - 1,
            rowLength - start - 1,
          );
        var changeIndex = 0;
        for (var offset = 0; offset < span; offset++) {
          final changed = changeIndex < changes.length &&
              changes[changeIndex].x == start + offset;
          writer.writeBits(changed ? 1 : 0, 1);
          if (changed) changeIndex++;
        }
        _writeCompactChangedValues(
          writer,
          values,
          rowLength,
          valueBits,
          row,
          changes,
          decision.predictor,
          useVirtualBaseRow: useVirtualBaseRow,
          useResidual: decision.useResidual,
        );
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
    if (predictor == _rowDeltaPredictorSame) {
      writer.writeBits(0, 1);
      return;
    }
    writer
      ..writeBits(1, 1)
      ..writeBits(predictor == _rowDeltaPredictorLeft ? 0 : 1, 1);
  }

  static int _readCompactRowDeltaPredictor(_V3BitReader reader) {
    if (reader.readBits(1) == 0) return _rowDeltaPredictorSame;
    return reader.readBits(1) == 0
        ? _rowDeltaPredictorLeft
        : _rowDeltaPredictorRight;
  }

  static void _copyCompactRowDeltaPredictedRow(
    List<int> values,
    int rowStart,
    int rowLength,
    int row,
    int predictor, {
    required bool useVirtualBaseRow,
  }) {
    for (var x = 0; x < rowLength; x++) {
      values[rowStart + x] = _compactRowDeltaPredictedValue(
        values,
        rowLength,
        row,
        x,
        predictor,
        useVirtualBaseRow: useVirtualBaseRow,
      );
    }
  }

  static int _compactRowDeltaPredictedValue(
    List<int> values,
    int rowLength,
    int row,
    int x,
    int predictor, {
    required bool useVirtualBaseRow,
  }) {
    if (row == 0 && useVirtualBaseRow) return 0;
    final previousStart = (row - 1) * rowLength;
    return switch (predictor) {
      _rowDeltaPredictorSame => values[previousStart + x],
      _rowDeltaPredictorLeft =>
        values[previousStart + (x == 0 ? rowLength - 1 : x - 1)],
      _rowDeltaPredictorRight =>
        values[previousStart + (x + 1 == rowLength ? 0 : x + 1)],
      _ => values[previousStart + x],
    };
  }

  static int _compactChangePositionsBitCost(
    List<_V3RowDeltaChange> changes,
    int rowLength,
  ) {
    var cost = 0;
    var previousX = -1;
    for (var i = 0; i < changes.length; i++) {
      final change = changes[i];
      final remainingPositions = changes.length - i - 1;
      final maxGap =
          rowLength - previousX - remainingPositions - 2;
      cost += _rangeCompactUintBitLength(
        change.x - previousX - 1,
        maxGap,
      );
      previousX = change.x;
    }
    return cost;
  }

  static void _writeCompactChangePositions(
    _V3BitWriter writer,
    List<_V3RowDeltaChange> changes,
    int rowLength,
  ) {
    var previousX = -1;
    for (var i = 0; i < changes.length; i++) {
      final change = changes[i];
      final remainingPositions = changes.length - i - 1;
      final maxGap =
          rowLength - previousX - remainingPositions - 2;
      writer.writeRangeCompactUint(
        change.x - previousX - 1,
        maxGap,
      );
      previousX = change.x;
    }
  }

  static List<int> _rowDeltaPredictorsForRow(
    int row, {
    required bool useVirtualBaseRow,
  }) {
    if (row == 0 && useVirtualBaseRow) {
      return const <int>[_rowDeltaPredictorSame];
    }
    return const <int>[
      _rowDeltaPredictorSame,
      _rowDeltaPredictorLeft,
      _rowDeltaPredictorRight,
    ];
  }

  static int _compactPredictorBitCost(int predictor) {
    return predictor == _rowDeltaPredictorSame ? 1 : 2;
  }

  static _V3CompactValueEncoding _bestCompactValueEncoding(
    List<int> values,
    int rowLength,
    int row,
    List<_V3RowDeltaChange> changes,
    int valueBits,
    int predictor, {
    required bool useVirtualBaseRow,
    required bool directGrayscale,
  }) {
    final absoluteCost = changes.length * valueBits;
    if (!directGrayscale) {
      return _V3CompactValueEncoding(false, absoluteCost);
    }
    var residualCost = 0;
    for (final change in changes) {
      final delta = _compactGrayscaleDelta(
        values,
        rowLength,
        row,
        change,
        predictor,
        useVirtualBaseRow: useVirtualBaseRow,
      );
      residualCost += _compactUintBitLength(_grayscaleDeltaCode(delta) - 1);
    }
    return residualCost < absoluteCost
        ? _V3CompactValueEncoding(true, 1 + residualCost)
        : _V3CompactValueEncoding(false, 1 + absoluteCost);
  }

  static _V3CompactValueEncoding? _bestCompactSameScalarEncoding(
    List<int> values,
    int rowLength,
    int row,
    List<_V3RowDeltaChange> changes,
    int valueBits,
    int predictor, {
    required bool useVirtualBaseRow,
    required bool directGrayscale,
  }) {
    final absoluteValue = _sameRowDeltaChangeValue(changes);
    _V3CompactValueEncoding? best;
    if (absoluteValue != null) {
      best = _V3CompactValueEncoding(
        false,
        valueBits + (directGrayscale ? 1 : 0),
      );
    }
    if (!directGrayscale) return best;
    int? sharedDelta;
    for (final change in changes) {
      final delta = _compactGrayscaleDelta(
        values,
        rowLength,
        row,
        change,
        predictor,
        useVirtualBaseRow: useVirtualBaseRow,
      );
      if (sharedDelta != null && sharedDelta != delta) return best;
      sharedDelta = delta;
    }
    final residual = _V3CompactValueEncoding(
      true,
      1 + _compactUintBitLength(_grayscaleDeltaCode(sharedDelta!) - 1),
    );
    return best == null || residual.bitCost < best.bitCost ? residual : best;
  }

  static int _compactGrayscaleDelta(
    List<int> values,
    int rowLength,
    int row,
    _V3RowDeltaChange change,
    int predictor, {
    required bool useVirtualBaseRow,
  }) {
    final predicted = _compactRowDeltaPredictedValue(
      values,
      rowLength,
      row,
      change.x,
      predictor,
      useVirtualBaseRow: useVirtualBaseRow,
    );
    return change.value - predicted;
  }

  static int _grayscaleDeltaCode(int delta) {
    if (delta == 0) {
      throw const MCOImageInvalidInputException('Zero grayscale delta');
    }
    return delta > 0 ? delta * 2 - 1 : -delta * 2;
  }

  static int _grayscaleDeltaFromCode(int code) {
    if (code <= 0) {
      throw const MCOImageInvalidPayloadException('Invalid grayscale delta');
    }
    return code.isOdd ? (code + 1) ~/ 2 : -(code ~/ 2);
  }

  static void _writeCompactChangedValues(
    _V3BitWriter writer,
    List<int> values,
    int rowLength,
    int valueBits,
    int row,
    List<_V3RowDeltaChange> changes,
    int predictor, {
    required bool useVirtualBaseRow,
    required bool useResidual,
  }) {
    for (final change in changes) {
      if (useResidual) {
        final delta = _compactGrayscaleDelta(
          values,
          rowLength,
          row,
          change,
          predictor,
          useVirtualBaseRow: useVirtualBaseRow,
        );
        writer.writeCompactUint(_grayscaleDeltaCode(delta) - 1);
      } else {
        writer.writeBits(change.value, valueBits);
      }
    }
  }

  static int _readCompactRowDeltaValue(
    _V3BitReader reader,
    List<int> values,
    int rowLength,
    int row,
    int x,
    int valueBits,
    int predictor, {
    required bool useVirtualBaseRow,
    required bool useResidual,
    required int maxValue,
  }) {
    final value = useResidual
        ? _compactRowDeltaPredictedValue(
              values,
              rowLength,
              row,
              x,
              predictor,
              useVirtualBaseRow: useVirtualBaseRow,
            ) +
            _grayscaleDeltaFromCode(reader.readCompactUint() + 1)
        : reader.readBits(valueBits);
    if (value < 0 || value > maxValue) {
      throw const MCOImageInvalidPayloadException(
        'Compact row-delta value out of range',
      );
    }
    return value;
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
      final remainingPositions = count - i - 1;
      final maxGap =
          rowLength - previousX - remainingPositions - 2;
      final x =
          previousX + 1 + reader.readRangeCompactUint(maxGap);
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
    if (colors.isEmpty || colors.length > _paletteSize(profile)) {
      throw const MCOImageInvalidInputException('Invalid local palette size');
    }
    final descriptor = _bestLocalPaletteDescriptor(profile, colors);
    if (descriptor == null) {
      _writeFlatLocalPalette(writer, profile, colors);
      return;
    }
    final wireDescriptor =
        descriptor == _localPaletteDescriptorOrderedBanked8x64
            ? _localPaletteDescriptorBankBitmaps
            : descriptor;
    _writeLocalPaletteDescriptorPrefix(writer, profile, wireDescriptor);
    _writeLocalPaletteDescriptorBody(writer, profile, colors, descriptor);
  }

  static List<int> _readLocalPalette(
    _V3BitReader reader,
    PaletteProfile profile,
  ) {
    final prefix = _readLocalPalettePrefix(reader, profile);
    final descriptor = prefix.descriptor;
    if (descriptor != null) {
      return _readLocalPaletteDescriptorBody(reader, profile, descriptor);
    }

    final length = prefix.length!;
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

  static void _writeFlatLocalPalette(
    _V3BitWriter writer,
    PaletteProfile profile,
    List<int> colors,
  ) {
    _writeLocalPaletteFlatPrefix(writer, profile, colors.length);
    for (final color in colors) {
      _writeColorRef(writer, profile, color);
    }
  }

  static void _writeLocalPaletteFlatPrefix(
    _V3BitWriter writer,
    PaletteProfile profile,
    int length,
  ) {
    final paletteSize = _paletteSize(profile);
    if (length <= 0 || length > paletteSize) {
      throw const MCOImageInvalidInputException(
        'Invalid local palette size',
      );
    }

    if (paletteSize <= _localPaletteSmallLengthLimit) {
      writer
        ..writeBits(0, 1)
        ..writeBits(length - 1, _globalBits(profile));
      return;
    }

    if (length <= _localPaletteSmallLengthLimit) {
      writer
        ..writeBits(0, 1)
        ..writeBits(length - 1, 6);
      return;
    }
    if (length <= _localPaletteMediumLengthLimit) {
      writer
        ..writeBits(1, 1)
        ..writeBits(0, 1)
        ..writeBits(length - 65, 6);
      return;
    }
    if (length <= _localPaletteLargeLengthLimit) {
      writer
        ..writeBits(1, 1)
        ..writeBits(1, 1)
        ..writeBits(0, 1)
        ..writeBits(length - 129, 8);
      return;
    }
    writer
      ..writeBits(1, 1)
      ..writeBits(1, 1)
      ..writeBits(1, 1)
      ..writeBits(0, 1)
      ..writeBits(length - 385, 7);
  }

  static void _writeLocalPaletteDescriptorPrefix(
    _V3BitWriter writer,
    PaletteProfile profile,
    int descriptor,
  ) {
    if (descriptor < 0 ||
        descriptor >= (1 << _localPaletteDescriptorBits)) {
      throw const MCOImageInvalidInputException(
        'Invalid local palette descriptor',
      );
    }
    if (_paletteSize(profile) <= _localPaletteSmallLengthLimit) {
      writer.writeBits(1, 1);
    } else {
      writer
        ..writeBits(1, 1)
        ..writeBits(1, 1)
        ..writeBits(1, 1)
        ..writeBits(1, 1);
    }
    writer.writeBits(descriptor, _localPaletteDescriptorBits);
  }

  static ({int? length, int? descriptor}) _readLocalPalettePrefix(
    _V3BitReader reader,
    PaletteProfile profile,
  ) {
    final paletteSize = _paletteSize(profile);
    if (paletteSize <= _localPaletteSmallLengthLimit) {
      if (reader.readBits(1) != 0) {
        return (
          length: null,
          descriptor: reader.readBits(_localPaletteDescriptorBits),
        );
      }
      return (
        length: reader.readBits(_globalBits(profile)) + 1,
        descriptor: null,
      );
    }

    if (reader.readBits(1) == 0) {
      return (length: reader.readBits(6) + 1, descriptor: null);
    }
    if (reader.readBits(1) == 0) {
      return (length: reader.readBits(6) + 65, descriptor: null);
    }
    if (reader.readBits(1) == 0) {
      final length = reader.readBits(8) + 129;
      if (length > paletteSize) {
        throw const MCOImageInvalidPayloadException(
          'Invalid local palette size',
        );
      }
      return (length: length, descriptor: null);
    }
    if (reader.readBits(1) == 0) {
      final length = reader.readBits(7) + 385;
      if (length > paletteSize) {
        throw const MCOImageInvalidPayloadException(
          'Invalid local palette size',
        );
      }
      return (length: length, descriptor: null);
    }
    return (
      length: null,
      descriptor: reader.readBits(_localPaletteDescriptorBits),
    );
  }

  static int _localPaletteFlatPrefixBitLength(
    PaletteProfile profile,
    int length,
  ) {
    final paletteSize = _paletteSize(profile);
    if (length <= 0 || length > paletteSize) {
      throw const MCOImageInvalidInputException(
        'Invalid local palette size',
      );
    }
    if (paletteSize <= _localPaletteSmallLengthLimit) {
      return 1 + _globalBits(profile);
    }
    if (length <= _localPaletteSmallLengthLimit) return 7;
    if (length <= _localPaletteMediumLengthLimit) return 8;
    return 11;
  }

  static int _localPaletteDescriptorPrefixBitLength(
    PaletteProfile profile,
  ) {
    return _paletteSize(profile) <= _localPaletteSmallLengthLimit
        ? 1 + _localPaletteDescriptorBits
        : 4 + _localPaletteDescriptorBits;
  }

  static int? _bestLocalPaletteDescriptor(
    PaletteProfile profile,
    List<int> colors,
  ) {
    final flatBits =
        _localPaletteFlatPrefixBitLength(profile, colors.length) +
        colors.length * _globalBits(profile);
    final descriptorPrefixBits =
        _localPaletteDescriptorPrefixBitLength(profile);
    final candidates = <({int descriptor, int bitCost})>[];
    final isSorted = _isProfileSortedLocalPalette(profile, colors);
    if (isSorted) {
      candidates.addAll([
        (
          descriptor: _localPaletteDescriptorBitmap,
          bitCost: descriptorPrefixBits + _paletteSize(profile),
        ),
        (
          descriptor: _localPaletteDescriptorSortedDelta,
          bitCost: _localPaletteSortedDeltaBitCost(profile, colors),
        ),
        (
          descriptor: _localPaletteDescriptorRangeRuns,
          bitCost: _localPaletteRangeRunsBitCost(profile, colors),
        ),
      ]);
    }
    if (profile == PaletteProfile.dynamicGlobal512) {
      if (isSorted) {
        candidates.add(
          (
            descriptor: _localPaletteDescriptorBankBitmaps,
            bitCost: _localPaletteBankBitmapsBitCost(colors),
          ),
        );
      }
      candidates.add(
        (
          descriptor: _localPaletteDescriptorOrderedBanked8x64,
          bitCost: _localPaletteOrderedBanked8x64BitCost(colors),
        ),
      );
    }
    if (candidates.isEmpty) return null;
    var best = candidates.first;
    for (final candidate in candidates.skip(1)) {
      if (candidate.bitCost < best.bitCost) best = candidate;
    }
    return best.bitCost < flatBits ? best.descriptor : null;
  }

  static bool _isProfileSortedLocalPalette(
    PaletteProfile profile,
    List<int> colors,
  ) {
    var previous = -1;
    final seen = <int>{};
    for (final color in colors) {
      _validateColor(color, profile);
      if (!seen.add(color)) {
        throw const MCOImageInvalidInputException('Duplicate local color');
      }
      final ref = _colorRefForProfile(profile, color);
      if (ref <= previous) return false;
      previous = ref;
    }
    return true;
  }

  static int _localPaletteSortedDeltaBitCost(
    PaletteProfile profile,
    List<int> colors,
  ) {
    var cost = _localPaletteDescriptorPrefixBitLength(profile) +
        _localPaletteLengthBitLength(profile, colors.length) +
        _globalBits(profile);
    var previous = _colorRefForProfile(profile, colors.first);
    for (final color in colors.skip(1)) {
      final ref = _colorRefForProfile(profile, color);
      cost += _compactUintBitLength(ref - previous - 1);
      previous = ref;
    }
    return cost;
  }

  static int _localPaletteRangeRunsBitCost(
    PaletteProfile profile,
    List<int> colors,
  ) {
    final runs = _localPaletteRefRanges(profile, colors);
    var cost = _localPaletteDescriptorPrefixBitLength(profile) +
        _rangeCompactUintBitLength(
          runs.length - 1,
          _paletteSize(profile) - 1,
        );
    final refBits = _globalBits(profile);
    for (final run in runs) {
      cost += refBits + _compactUintBitLength(run.length - 1);
    }
    return cost;
  }

  static int _localPaletteBankBitmapsBitCost(List<int> colors) {
    final bankMask = colors.fold<int>(
      0,
      (mask, color) => mask | (1 << (_colorRefForDynamic512(color) >> 6)),
    );
    final bankCount = _bitCount(bankMask);
    return _localPaletteDescriptorPrefixBitLength(
          PaletteProfile.dynamicGlobal512,
        ) +
        1 +
        8 +
        bankCount * 64;
  }

  static int _localPaletteOrderedBanked8x64BitCost(List<int> colors) {
    final refs = colors.map(_colorRefForDynamic512).toList(growable: false);
    final bankMask = refs.fold<int>(
      0,
      (mask, ref) => mask | (1 << (ref >> 6)),
    );
    final bankCount = _bitCount(bankMask);
    final bankChoiceBits = bankCount <= 1 ? 0 : (bankCount - 1).bitLength;
    return _localPaletteDescriptorPrefixBitLength(
          PaletteProfile.dynamicGlobal512,
        ) +
        1 +
        _localPaletteLengthBitLength(
          PaletteProfile.dynamicGlobal512,
          colors.length,
        ) +
        1 +
        (bankCount == 1 ? 3 : 8) +
        colors.length * (6 + bankChoiceBits);
  }

  static void _writeLocalPaletteLength(
    _V3BitWriter writer,
    PaletteProfile profile,
    int length,
  ) {
    final paletteSize = _paletteSize(profile);
    if (length <= 0 || length > paletteSize) {
      throw const MCOImageInvalidInputException(
        'Invalid local palette size',
      );
    }
    if (paletteSize <= _localPaletteSmallLengthLimit) {
      writer.writeBits(length - 1, _globalBits(profile));
      return;
    }
    if (length <= _localPaletteSmallLengthLimit) {
      writer
        ..writeBits(0, 1)
        ..writeBits(length - 1, 6);
      return;
    }
    if (length <= _localPaletteMediumLengthLimit) {
      writer
        ..writeBits(1, 1)
        ..writeBits(0, 1)
        ..writeBits(length - 65, 6);
      return;
    }

    writer
      ..writeBits(1, 1)
      ..writeBits(1, 1)
      ..writeBits(
        length - 129,
        (paletteSize - 129).bitLength,
      );
  }

  static int _readLocalPaletteLength(
    _V3BitReader reader,
    PaletteProfile profile,
  ) {
    final paletteSize = _paletteSize(profile);
    if (paletteSize <= _localPaletteSmallLengthLimit) {
      return reader.readBits(_globalBits(profile)) + 1;
    }
    if (reader.readBits(1) == 0) {
      return reader.readBits(6) + 1;
    }
    if (reader.readBits(1) == 0) {
      return reader.readBits(6) + 65;
    }
    if (paletteSize <= _localPaletteMediumLengthLimit) {
      throw const MCOImageInvalidPayloadException(
        'Invalid local palette length prefix',
      );
    }
    final length =
        reader.readBits((paletteSize - 129).bitLength) + 129;
    if (length > paletteSize) {
      throw const MCOImageInvalidPayloadException(
        'Invalid local palette size',
      );
    }
    return length;
  }

  static int _localPaletteLengthBitLength(
    PaletteProfile profile,
    int length,
  ) {
    final paletteSize = _paletteSize(profile);
    if (length <= 0 || length > paletteSize) {
      throw const MCOImageInvalidInputException(
        'Invalid local palette size',
      );
    }
    if (paletteSize <= _localPaletteSmallLengthLimit) {
      return _globalBits(profile);
    }
    if (length <= _localPaletteSmallLengthLimit) return 7;
    if (length <= _localPaletteMediumLengthLimit) return 8;
    return 2 + (paletteSize - 129).bitLength;
  }

  static void _writeLocalPaletteDescriptorBody(
    _V3BitWriter writer,
    PaletteProfile profile,
    List<int> colors,
    int descriptor,
  ) {
    switch (descriptor) {
      case _localPaletteDescriptorBitmap:
        final selected = colors
            .map((color) => _colorRefForProfile(profile, color))
            .toSet();
        for (var ref = 0; ref < _paletteSize(profile); ref++) {
          writer.writeBits(selected.contains(ref) ? 1 : 0, 1);
        }
        break;
      case _localPaletteDescriptorSortedDelta:
        _writeLocalPaletteLength(writer, profile, colors.length);
        writer.writeBits(
          _colorRefForProfile(profile, colors.first),
          _globalBits(profile),
        );
        var previous = _colorRefForProfile(profile, colors.first);
        for (final color in colors.skip(1)) {
          final ref = _colorRefForProfile(profile, color);
          writer.writeCompactUint(ref - previous - 1);
          previous = ref;
        }
        break;
      case _localPaletteDescriptorRangeRuns:
        final runs = _localPaletteRefRanges(profile, colors);
        writer.writeRangeCompactUint(
          runs.length - 1,
          _paletteSize(profile) - 1,
        );
        for (final run in runs) {
          writer
            ..writeBits(run.start, _globalBits(profile))
            ..writeCompactUint(run.length - 1);
        }
        break;
      case _localPaletteDescriptorBankBitmaps:
        if (profile != PaletteProfile.dynamicGlobal512) {
          throw const MCOImageInvalidInputException(
            'Bank bitmap palette descriptor requires dynamicGlobal512',
          );
        }
        writer.writeBits(_localPaletteBankDescriptorBitmaps, 1);
        final selected = colors.map(_colorRefForDynamic512).toSet();
        final bankMask = selected.fold<int>(
          0,
          (mask, ref) => mask | (1 << (ref >> 6)),
        );
        writer.writeBits(bankMask, 8);
        for (var bank = 0; bank < 8; bank++) {
          if ((bankMask & (1 << bank)) == 0) continue;
          for (var offset = 0; offset < 64; offset++) {
            writer.writeBits(
              selected.contains((bank << 6) | offset) ? 1 : 0,
              1,
            );
          }
        }
        break;
      case _localPaletteDescriptorOrderedBanked8x64:
        if (profile != PaletteProfile.dynamicGlobal512) {
          throw const MCOImageInvalidInputException(
            'Ordered banked palette descriptor requires dynamicGlobal512',
          );
        }
        writer.writeBits(_localPaletteBankDescriptorOrdered8x64, 1);
        _writeLocalPaletteLength(writer, profile, colors.length);
        final refs = colors.map(_colorRefForDynamic512).toList(growable: false);
        final bankMask = refs.fold<int>(
          0,
          (mask, ref) => mask | (1 << (ref >> 6)),
        );
        final banks = <int>[];
        for (var bank = 0; bank < 8; bank++) {
          if ((bankMask & (1 << bank)) != 0) banks.add(bank);
        }
        final singleBank = banks.length == 1;
        writer.writeBits(singleBank ? 0 : 1, 1);
        if (singleBank) {
          writer.writeBits(banks.single, 3);
          for (final ref in refs) {
            writer.writeBits(ref & 0x3f, 6);
          }
          break;
        }
        writer.writeBits(bankMask, 8);
        final bankBits = (banks.length - 1).bitLength;
        final bankIndexes = <int, int>{
          for (var i = 0; i < banks.length; i++) banks[i]: i,
        };
        for (final ref in refs) {
          writer
            ..writeBits(bankIndexes[ref >> 6]!, bankBits)
            ..writeBits(ref & 0x3f, 6);
        }
        break;
      default:
        throw const MCOImageInvalidInputException(
          'Unsupported local palette descriptor',
        );
    }
  }

  static List<int> _readLocalPaletteDescriptorBody(
    _V3BitReader reader,
    PaletteProfile profile,
    int descriptor,
  ) {
    final refs = switch (descriptor) {
      _localPaletteDescriptorBitmap =>
        _readLocalPaletteBitmapDescriptor(reader, profile),
      _localPaletteDescriptorSortedDelta =>
        _readLocalPaletteSortedDeltaDescriptor(reader, profile),
      _localPaletteDescriptorRangeRuns =>
        _readLocalPaletteRangeRunsDescriptor(reader, profile),
      _localPaletteDescriptorBankBitmaps =>
        _readLocalPaletteBankDescriptor(reader, profile),
      _ => throw const MCOImageInvalidPayloadException(
        'Unknown local palette descriptor',
      ),
    };
    if (refs.isEmpty || refs.length > _paletteSize(profile)) {
      throw const MCOImageInvalidPayloadException(
        'Invalid compact local palette size',
      );
    }
    final colors = <int>[];
    final seen = <int>{};
    for (final ref in refs) {
      if (ref < 0 || ref >= _paletteSize(profile) || !seen.add(ref)) {
        throw const MCOImageInvalidPayloadException(
          'Invalid compact local palette',
        );
      }
      colors.add(_globalIndexForProfileRef(profile, ref));
    }
    return colors;
  }

  static List<int> _readLocalPaletteBitmapDescriptor(
    _V3BitReader reader,
    PaletteProfile profile,
  ) {
    final refs = <int>[];
    for (var ref = 0; ref < _paletteSize(profile); ref++) {
      if (reader.readBits(1) != 0) refs.add(ref);
    }
    return refs;
  }

  static List<int> _readLocalPaletteSortedDeltaDescriptor(
    _V3BitReader reader,
    PaletteProfile profile,
  ) {
    final count = _readLocalPaletteLength(reader, profile);
    if (count <= 0 || count > _paletteSize(profile)) {
      throw const MCOImageInvalidPayloadException(
        'Invalid sorted local palette size',
      );
    }
    final refs = <int>[reader.readBits(_globalBits(profile))];
    while (refs.length < count) {
      refs.add(refs.last + reader.readCompactUint() + 1);
    }
    return refs;
  }

  static List<int> _readLocalPaletteRangeRunsDescriptor(
    _V3BitReader reader,
    PaletteProfile profile,
  ) {
    final runCount =
        reader.readRangeCompactUint(_paletteSize(profile) - 1) + 1;
    if (runCount <= 0 || runCount > _paletteSize(profile)) {
      throw const MCOImageInvalidPayloadException(
        'Invalid local palette range count',
      );
    }
    final refs = <int>[];
    var previousEnd = -1;
    for (var i = 0; i < runCount; i++) {
      final start = reader.readBits(_globalBits(profile));
      final length = reader.readCompactUint() + 1;
      final end = start + length - 1;
      if (start <= previousEnd ||
          end >= _paletteSize(profile) ||
          refs.length + length > _paletteSize(profile)) {
        throw const MCOImageInvalidPayloadException(
          'Invalid local palette range',
        );
      }
      for (var offset = 0; offset < length; offset++) {
        refs.add(start + offset);
      }
      previousEnd = end;
    }
    return refs;
  }

  static List<int> _readLocalPaletteBankDescriptor(
    _V3BitReader reader,
    PaletteProfile profile,
  ) {
    if (profile != PaletteProfile.dynamicGlobal512) {
      throw const MCOImageInvalidPayloadException(
        'Bank palette descriptor requires dynamicGlobal512',
      );
    }
    return switch (reader.readBits(1)) {
      _localPaletteBankDescriptorBitmaps =>
        _readLocalPaletteBankBitmapsDescriptor(reader, profile),
      _localPaletteBankDescriptorOrdered8x64 =>
        _readLocalPaletteOrderedBanked8x64Descriptor(reader, profile),
      _ => throw const MCOImageInvalidPayloadException(
        'Unknown bank palette descriptor',
      ),
    };
  }

  static List<int> _readLocalPaletteBankBitmapsDescriptor(
    _V3BitReader reader,
    PaletteProfile profile,
  ) {
    if (profile != PaletteProfile.dynamicGlobal512) {
      throw const MCOImageInvalidPayloadException(
        'Bank bitmap descriptor requires dynamicGlobal512',
      );
    }
    final bankMask = reader.readBits(8);
    if (bankMask == 0) {
      throw const MCOImageInvalidPayloadException('Empty bank bitmap palette');
    }
    final refs = <int>[];
    for (var bank = 0; bank < 8; bank++) {
      if ((bankMask & (1 << bank)) == 0) continue;
      final beforeBank = refs.length;
      for (var offset = 0; offset < 64; offset++) {
        if (reader.readBits(1) != 0) {
          refs.add((bank << 6) | offset);
        }
      }
      if (refs.length == beforeBank) {
        throw const MCOImageInvalidPayloadException(
          'Bank bitmap palette contains an empty bank',
        );
      }
    }
    return refs;
  }

  static List<int> _readLocalPaletteOrderedBanked8x64Descriptor(
    _V3BitReader reader,
    PaletteProfile profile,
  ) {
    if (profile != PaletteProfile.dynamicGlobal512) {
      throw const MCOImageInvalidPayloadException(
        'Ordered banked descriptor requires dynamicGlobal512',
      );
    }
    final count = _readLocalPaletteLength(reader, profile);
    final multipleBanks = reader.readBits(1) != 0;
    if (!multipleBanks) {
      if (count > 64) {
        throw const MCOImageInvalidPayloadException(
          'Single-bank palette contains too many colors',
        );
      }
      final bank = reader.readBits(3);
      return List<int>.generate(
        count,
        (_) => (bank << 6) | reader.readBits(6),
        growable: false,
      );
    }

    final bankMask = reader.readBits(8);
    final bankCount = _bitCount(bankMask);
    if (bankCount <= 1) {
      throw const MCOImageInvalidPayloadException(
        'Invalid ordered banked palette mask',
      );
    }
    if (count > bankCount * 64) {
      throw const MCOImageInvalidPayloadException(
        'Ordered banked palette contains too many colors',
      );
    }
    final banks = <int>[];
    for (var bank = 0; bank < 8; bank++) {
      if ((bankMask & (1 << bank)) != 0) banks.add(bank);
    }
    final bankBits = (bankCount - 1).bitLength;
    final refs = <int>[];
    final usedBankIndexes = <int>{};
    for (var i = 0; i < count; i++) {
      final bankIndex = reader.readBits(bankBits);
      if (bankIndex >= banks.length) {
        throw const MCOImageInvalidPayloadException(
          'Invalid ordered banked palette bank index',
        );
      }
      usedBankIndexes.add(bankIndex);
      refs.add((banks[bankIndex] << 6) | reader.readBits(6));
    }
    if (usedBankIndexes.length != bankCount) {
      throw const MCOImageInvalidPayloadException(
        'Ordered banked palette contains an unused bank',
      );
    }
    return refs;
  }

  static int _colorRefForProfile(PaletteProfile profile, int color) {
    _validateColor(color, profile);
    if (!profile.isDynamic) return color;
    final ref = MCOImageDynamicPalette.profileColorIdForGlobalIndex(
      profile,
      color,
    );
    if (ref == null) {
      throw MCOImageInvalidInputException(
        'Color $color is outside dynamic profile $profile',
      );
    }
    return ref;
  }

  static int _globalIndexForProfileRef(PaletteProfile profile, int ref) {
    if (!profile.isDynamic) return ref;
    return MCOImageDynamicPalette.globalIndexForProfileColorId(profile, ref);
  }

  static int _colorRefForDynamic512(int color) {
    final ref = MCOImageDynamicPalette.profileColorIdForGlobalIndex(
      PaletteProfile.dynamicGlobal512,
      color,
    );
    if (ref == null) {
      throw MCOImageInvalidInputException(
        'Color $color is outside dynamicGlobal512',
      );
    }
    return ref;
  }

  static List<_V3PaletteRefRange> _localPaletteRefRanges(
    PaletteProfile profile,
    List<int> colors,
  ) {
    final refs = colors
        .map((color) => _colorRefForProfile(profile, color))
        .toList(growable: false);
    final ranges = <_V3PaletteRefRange>[];
    var start = refs.first;
    var previous = start;
    for (final ref in refs.skip(1)) {
      if (ref == previous + 1) {
        previous = ref;
        continue;
      }
      ranges.add(_V3PaletteRefRange(start, previous));
      start = ref;
      previous = ref;
    }
    ranges.add(_V3PaletteRefRange(start, previous));
    return ranges;
  }

  static int _bitCount(int value) {
    var current = value;
    var count = 0;
    while (current != 0) {
      count += current & 1;
      current >>= 1;
    }
    return count;
  }

  static int _colorFromProfileRef(
    PaletteProfile profile,
    int colorRef, {
    required bool payload,
  }) {
    final color = profile.isDynamic
        ? MCOImageDynamicPalette.globalIndexForProfileColorId(profile, colorRef)
        : colorRef;
    _validateColor(color, profile, payload: payload);
    return color;
  }

  static void _writeColorRef(
    _V3BitWriter writer,
    PaletteProfile profile,
    int color,
  ) {
    writer.writeBits(
      _colorRefForProfile(profile, color),
      _globalBits(profile),
    );
  }

  static int _readColorRef(_V3BitReader reader, PaletteProfile profile) {
    return _colorFromProfileRef(
      profile,
      reader.readBits(_globalBits(profile)),
      payload: true,
    );
  }

  static void _writeContextualColorRefTail(
    _V3BitWriter writer,
    PaletteProfile profile,
    int colorRef,
  ) {
    final remainingBits = _globalBits(profile) - 5;
    if (remainingBits > 0) {
      writer.writeBits(colorRef >> 5, remainingBits);
    }
  }

  static int _readSolidBackgroundColor(
    _V3BitReader reader,
    PaletteProfile profile,
    int context, {
    required bool implicitWhiteBackground,
  }) {
    if (implicitWhiteBackground) {
      if (context != 0) {
        throw const MCOImageInvalidPayloadException(
          'Implicit white solid background must use zero context',
        );
      }
      return MCOImagePalette.whiteIndexFor(profile);
    }
    return _readContextualColorRef(reader, profile, context);
  }

  static int _readContextualColorRef(
    _V3BitReader reader,
    PaletteProfile profile,
    int context,
  ) {
    final totalBits = _globalBits(profile);
    final lowBits = totalBits < 5 ? totalBits : 5;
    final lowMask = (1 << lowBits) - 1;
    if ((context & ~lowMask) != 0) {
      throw const MCOImageInvalidPayloadException(
        'Solid background color context is out of range',
      );
    }
    final remainingBits = totalBits - lowBits;
    final colorRef = remainingBits > 0
        ? context | (reader.readBits(remainingBits) << lowBits)
        : context;
    return _colorFromProfileRef(
      profile,
      colorRef,
      payload: true,
    );
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

  static List<_V3BackgroundCandidate> _backgroundCandidates(
    MCOImage image,
    int? explicitBackground, {
    required bool exhaustiveSmallImage,
  }) {
    final result = <_V3BackgroundCandidate>[];
    final seen = <int>{};

    void add(int color, int rank) {
      if (!_isColorValid(color, image.paletteProfile)) return;
      if (!seen.add(color)) return;
      result.add(_V3BackgroundCandidate(color, rank));
    }

    if (explicitBackground != null) add(explicitBackground, 0);
    add(
      image.paletteProfile.isDynamic
          ? MCOImageDynamicPalette.whiteGlobalIndexFor(image.paletteProfile)
          : 0,
      1,
    );

    final counts = <int, int>{};
    for (final pixel in image.pixels) {
      counts[pixel] = (counts[pixel] ?? 0) + 1;
    }
    final colors = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    for (
      var i = 0;
      i < math.min(_maxFrequentBackgroundCandidates, colors.length);
      i++
    ) {
      add(colors[i], 2 + i);
    }
    if (exhaustiveSmallImage &&
        image.pixels.length <= _maxExhaustiveBackgroundPixels &&
        colors.length <= _maxExhaustiveBackgroundColors) {
      for (var i = 0; i < colors.length; i++) {
        add(colors[i], 2 + i);
      }
    }
    return result;
  }

  static List<_V3BackgroundCandidate> _backgroundCandidatesFromPublic(
    List<MCOImageBackgroundCandidate> candidates,
    PaletteProfile profile,
  ) {
    final result = <_V3BackgroundCandidate>[];
    final seen = <int>{};
    for (final candidate in candidates) {
      if (!_isColorValid(candidate.color, profile)) continue;
      if (!seen.add(candidate.color)) continue;
      result.add(_V3BackgroundCandidate(candidate.color, candidate.rank));
    }
    return result;
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
    const neighbors = [
      [-1, -1],
      [0, -1],
      [1, -1],
      [-1, 0],
      [1, 0],
      [-1, 1],
      [0, 1],
      [1, 1],
    ];

    for (var start = 0; start < image.pixels.length; start++) {
      if (visited[start] || image.pixels[start] == backgroundColor) continue;
      final queue = <int>[start];
      visited[start] = true;
      var minX = image.width;
      var minY = image.height;
      var maxX = -1;
      var maxY = -1;
      while (queue.isNotEmpty) {
        final index = queue.removeLast();
        final x = index % image.width;
        final y = index ~/ image.width;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);

        for (final neighborOffset in neighbors) {
          final nx = x + neighborOffset[0];
          final ny = y + neighborOffset[1];
          if (nx < 0 || ny < 0 || nx >= image.width || ny >= image.height) {
            continue;
          }
          final neighbor = ny * image.width + nx;
          if (visited[neighbor] ||
              image.pixels[neighbor] == backgroundColor) {
            continue;
          }
          visited[neighbor] = true;
          queue.add(neighbor);
        }
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

  List<_V3RegionVariant> _regionVariantsForBackground(
    MCOImage image,
    int backgroundColor,
    int maxRegions, {
    required bool useHighCompressionExtras,
    required bool useExtremeSearch,
  }) {
    if (maxRegions == 0) return const <_V3RegionVariant>[];
    final connectedRegions = _componentBoundsForBackground(
      image,
      backgroundColor,
    );
    if (connectedRegions.isEmpty) return const <_V3RegionVariant>[];
    final useBoundedExtremeSearch =
        useExtremeSearch &&
        image.pixels.length <= _maxExtremeRegionPixels &&
        connectedRegions.length <= _maxExtremeRegionComponents;
    final beamMaxRegions = useBoundedExtremeSearch
        ? math.min(maxRegions, _maxExtremeRegionSearchRegions)
        : maxRegions;

    if (useExtremeSearch && !useBoundedExtremeSearch) {
      debugPrint(
        '[MCOimg][Extreme][V3 Regions] SKIP; '
        'deep search; '
        'bg=$backgroundColor; '
        'pixels=${image.pixels.length}/$_maxExtremeRegionPixels; '
        'components=${connectedRegions.length}/'
        '$_maxExtremeRegionComponents;',
      );
    }

    final rawVariants = <_V3RegionVariant>[
      _V3RegionVariant(connectedRegions, null),
    ];
    final splitRegions = _splitRegionsByEmptyLines(
      image.pixels,
      image.width,
      backgroundColor,
      connectedRegions,
      maxRegions,
    );
    if (splitRegions.isNotEmpty) {
      rawVariants.add(_V3RegionVariant(splitRegions, 'split'));
    }
    final sparseSplitRegions = _splitRegionsBySparseLines(
      image.pixels,
      image.width,
      backgroundColor,
      connectedRegions,
      maxRegions,
      maxLineNonBackground: 2,
    );
    if (sparseSplitRegions.isNotEmpty) {
      rawVariants.add(_V3RegionVariant(sparseSplitRegions, 'sparse-split'));
    }
    for (final regions in _findGreedyRectRegionVariants(
      image.pixels,
      image.width,
      image.height,
      backgroundColor,
      maxRegions,
    )) {
      rawVariants.add(_V3RegionVariant(regions, 'greedy'));
    }

    final result = <_V3RegionVariant>[];
    final seen = <String>{};
    for (final variant in rawVariants) {
      final regions = _sortedRegions(variant.regions);
      if (regions.isEmpty ||
          regions.length > maxRegions ||
          !_regionsDoNotOverlap(regions)) {
        continue;
      }
      final key = _regionListKey(regions);
      if (seen.add(key)) {
        result.add(_V3RegionVariant(regions, variant.label));
      }
    }

    if (result.isNotEmpty &&
        (useBoundedExtremeSearch ||
            image.pixels.length <= _maxBeamRegionPixels)) {
      final beamVariants = _findPayloadOptimizedRegionVariants(
        image,
        backgroundColor,
        result.map((variant) => variant.regions).toList(growable: false),
        beamMaxRegions,
        useHighCompressionExtras: useHighCompressionExtras,
        useExtremeSearch: useBoundedExtremeSearch,
      );
      for (final state in beamVariants) {
        final key = _regionListKey(state.regions);
        if (seen.add(key)) {
          result.add(_V3RegionVariant(state.regions, 'beam'));
        }
      }
    }
    return result;
  }

  List<_V3RegionBeamState> _findPayloadOptimizedRegionVariants(
    MCOImage image,
    int backgroundColor,
    List<List<_V3Bounds>> initialVariants,
    int maxRegions, {
    required bool useHighCompressionExtras,
    required bool useExtremeSearch,
  }) {
    final initialStates = <_V3RegionBeamState>[];
    final seen = <String>{};
    for (final regions in initialVariants) {
      if (regions.isEmpty ||
          regions.length > maxRegions ||
          !_regionsDoNotOverlap(regions)) {
        continue;
      }
      final normalized = _sortedRegions(regions);
      final key = _regionListKey(normalized);
      if (!seen.add(key)) continue;
      final cost = _regionPayloadByteCost(
        image,
        backgroundColor,
        normalized,
        useHighCompressionExtras: useHighCompressionExtras,
        reducedCostEvaluator: useExtremeSearch,
      );
      if (cost != null) {
        initialStates.add(_V3RegionBeamState(normalized, cost));
      }
    }
    if (initialStates.isEmpty) return const <_V3RegionBeamState>[];
    initialStates.sort((left, right) => left.cost.compareTo(right.cost));
    final bestExistingCost = initialStates.first.cost;
    final beamWidth = useExtremeSearch
        ? _extremeRegionBeamWidth
        : _regionBeamWidth;
    final beamDepth = useExtremeSearch
        ? _extremeRegionBeamDepth
        : _regionBeamDepth;
    final resultLimit = useExtremeSearch
        ? _extremeRegionResultLimit
        : _regionBeamWidth;
    final evaluationBudget = useExtremeSearch
        ? _extremeRegionEvaluationBudget
        : null;
    var evaluatedLayouts = initialStates.length;
    var completedDepths = 0;
    var budgetExhausted = false;
    var beam = initialStates.take(beamWidth).toList();
    final improved = <_V3RegionBeamState>[];
    final evaluatedStates = <_V3RegionBeamState>[];

    if (useExtremeSearch) {
      debugPrint(
        '[MCOimg][Extreme][V3 Regions] START; '
        'budget=$evaluationBudget; '
        'bg=$backgroundColor; '
        'initial=${initialStates.length}; '
        'maxRegions=$maxRegions; '
        'width=$beamWidth; '
        'depth=$beamDepth; '
        'neighbors=$_extremeRegionNeighbors; '
        'cost=reduced;',
      );
    }

    for (var depth = 0; depth < beamDepth; depth++) {
      final next = <_V3RegionBeamState>[];
      for (final state in beam) {
        for (final regions in _regionBeamNeighborsFor(
          image.pixels,
          image.width,
          backgroundColor,
          state.regions,
          maxRegions,
          useExtremeSearch: useExtremeSearch,
        )) {
          if (evaluationBudget != null &&
              evaluatedLayouts >= evaluationBudget) {
            budgetExhausted = true;
            break;
          }
          final key = _regionListKey(regions);
          if (!seen.add(key)) continue;
          evaluatedLayouts++;
          final cost = _regionPayloadByteCost(
            image,
            backgroundColor,
            regions,
            useHighCompressionExtras: useHighCompressionExtras,
            reducedCostEvaluator: useExtremeSearch,
          );
          if (cost == null) continue;
          final candidate = _V3RegionBeamState(regions, cost);
          next.add(candidate);
          evaluatedStates.add(candidate);
          if (cost < bestExistingCost) improved.add(candidate);
        }
        if (budgetExhausted) break;
      }
      if (next.isEmpty) break;
      next.sort((left, right) => left.cost.compareTo(right.cost));
      beam = next.take(beamWidth).toList();
      completedDepths = depth + 1;

      if (useExtremeSearch) {
        final percentage =
            (evaluatedLayouts * 100 / evaluationBudget!).clamp(0, 100);
        debugPrint(
          '[MCOimg][Extreme][V3 Regions] '
          '$completedDepths/$beamDepth '
          '(${(completedDepths * 100 / beamDepth).toStringAsFixed(1)}%); '
          'evaluated=$evaluatedLayouts/$evaluationBudget '
          '(${percentage.toStringAsFixed(1)}% budget); '
          'frontier=${beam.length}; '
          'improved=${improved.length};',
        );
      }
      if (budgetExhausted) break;
    }

    if (useExtremeSearch) {
      final percentage =
          (evaluatedLayouts * 100 / evaluationBudget!).clamp(0, 100);
      debugPrint(
        '[MCOimg][Extreme][V3 Regions] '
        '$completedDepths/$beamDepth '
        '(${(completedDepths * 100 / beamDepth).toStringAsFixed(1)}%); '
        'evaluated=$evaluatedLayouts/$evaluationBudget '
        '(${percentage.toStringAsFixed(1)}% budget); '
        'COMPLETE; '
        'bg=$backgroundColor; '
        'improved=${improved.length}; '
        'budgetExhausted=$budgetExhausted;',
      );
    }

    final resultSource = useExtremeSearch
        ? <_V3RegionBeamState>[...improved, ...evaluatedStates]
        : improved;
    resultSource.sort((left, right) => left.cost.compareTo(right.cost));
    final reducedResult = <_V3RegionBeamState>[];
    final resultKeys = <String>{};
    final reducedResultLimit = useExtremeSearch
        ? _extremeRegionExactRerankPoolSize
        : resultLimit;
    for (final state in resultSource) {
      if (resultKeys.add(_regionListKey(state.regions))) {
        reducedResult.add(state);
      }
      if (reducedResult.length >= reducedResultLimit) break;
    }
    if (!useExtremeSearch || reducedResult.isEmpty) {
      return reducedResult;
    }

    // Reduced cost keeps the beam search affordable, but it does not model
    // every final regions variant (notably shared palettes). Re-rank a wider
    // reduced-cost pool with the exact encoder before returning the top layouts.
    final exactResult = <_V3RegionBeamState>[];
    for (final state in reducedResult) {
      final exactCost = _regionPayloadByteCost(
        image,
        backgroundColor,
        state.regions,
        useHighCompressionExtras: useHighCompressionExtras,
        reducedCostEvaluator: false,
      );
      if (exactCost != null) {
        exactResult.add(_V3RegionBeamState(state.regions, exactCost));
      }
    }
    if (exactResult.isEmpty) {
      return reducedResult.take(resultLimit).toList(growable: false);
    }
    exactResult.sort((left, right) => left.cost.compareTo(right.cost));
    return exactResult.take(resultLimit).toList(growable: false);
  }

  int? _regionPayloadByteCost(
    MCOImage image,
    int backgroundColor,
    List<_V3Bounds> regions, {
    required bool useHighCompressionExtras,
    required bool reducedCostEvaluator,
  }) {
    if (reducedCostEvaluator) {
      return _fastRegionPayloadByteCost(
        image,
        backgroundColor,
        regions,
        useHighCompressionExtras: useHighCompressionExtras,
      );
    }
    final regionPlanCache = _createRegionPlanCache(
      image,
      regions,
      useHighCompressionExtras: useHighCompressionExtras,
      reducedCostEvaluator: reducedCostEvaluator,
    );
    int? best;
    void consider(EncodedMCOImage? candidate) {
      if (candidate == null) return;
      if (best == null || candidate.byteLength < best!) {
        best = candidate.byteLength;
      }
    }

    consider(
      _tryBuildRegionsCandidate(
        image,
        backgroundColor,
        regionsOverride: regions,
        regionPlanCache: regionPlanCache,
        compactGeometry: false,
        useHighCompressionExtras: useHighCompressionExtras,
        reducedCostEvaluator: reducedCostEvaluator,
      ),
    );
    if (!useHighCompressionExtras) return best;
    const optionsList = [
      (
        commonBlockHeader: false,
        hybridCommonHeader: false,
        deltaGeometry: false,
        sharedLocalPalette: false,
      ),
      (
        commonBlockHeader: false,
        hybridCommonHeader: false,
        deltaGeometry: true,
        sharedLocalPalette: false,
      ),
      (
        commonBlockHeader: false,
        hybridCommonHeader: false,
        deltaGeometry: false,
        sharedLocalPalette: true,
      ),
      (
        commonBlockHeader: false,
        hybridCommonHeader: false,
        deltaGeometry: true,
        sharedLocalPalette: true,
      ),
      (
        commonBlockHeader: true,
        hybridCommonHeader: false,
        deltaGeometry: false,
        sharedLocalPalette: false,
      ),
      (
        commonBlockHeader: true,
        hybridCommonHeader: false,
        deltaGeometry: true,
        sharedLocalPalette: false,
      ),
      (
        commonBlockHeader: true,
        hybridCommonHeader: false,
        deltaGeometry: false,
        sharedLocalPalette: true,
      ),
      (
        commonBlockHeader: true,
        hybridCommonHeader: false,
        deltaGeometry: true,
        sharedLocalPalette: true,
      ),
      (
        commonBlockHeader: true,
        hybridCommonHeader: true,
        deltaGeometry: false,
        sharedLocalPalette: false,
      ),
      (
        commonBlockHeader: true,
        hybridCommonHeader: true,
        deltaGeometry: true,
        sharedLocalPalette: false,
      ),
      (
        commonBlockHeader: true,
        hybridCommonHeader: true,
        deltaGeometry: false,
        sharedLocalPalette: true,
      ),
      (
        commonBlockHeader: true,
        hybridCommonHeader: true,
        deltaGeometry: true,
        sharedLocalPalette: true,
      ),
    ];
    for (final options in optionsList) {
      consider(
        _tryBuildRegionsCandidate(
          image,
          backgroundColor,
          regionsOverride: regions,
        regionPlanCache: regionPlanCache,
          compactGeometry: true,
          commonBlockHeader: options.commonBlockHeader,
          hybridCommonHeader: options.hybridCommonHeader,
          deltaGeometry: options.deltaGeometry,
          sharedLocalPalette: options.sharedLocalPalette,
          useHighCompressionExtras: useHighCompressionExtras,
          reducedCostEvaluator: reducedCostEvaluator,
        ),
      );
    }
    return best;
  }

  int? _fastRegionPayloadByteCost(
    MCOImage image,
    int backgroundColor,
    List<_V3Bounds> regions, {
    required bool useHighCompressionExtras,
  }) {
    final regionPlanCache = _createRegionPlanCache(
      image,
      regions,
      useHighCompressionExtras: useHighCompressionExtras,
      reducedCostEvaluator: true,
    );
    final individualPlan = _regionPlanForCandidate(
      image,
      backgroundColor,
      regionPlanCache,
      commonBlockHeader: false,
      hybridCommonHeader: false,
      sharedLocalPalette: false,
    );
    if (individualPlan.blocks == null) return null;
    final individualBits = _regionCandidateBitLength(
      image,
      backgroundColor,
      individualPlan,
      compactGeometry: true,
      commonBlockHeader: false,
      hybridCommonHeader: false,
      deltaGeometry: false,
      sharedLocalPalette: false,
    );

    final commonPlan = _regionPlanForCandidate(
      image,
      backgroundColor,
      regionPlanCache,
      commonBlockHeader: true,
      hybridCommonHeader: false,
      sharedLocalPalette: false,
    );
    if (commonPlan.blocks == null) {
      return (individualBits + 7) ~/ 8;
    }
    final commonBits = _regionCandidateBitLength(
      image,
      backgroundColor,
      commonPlan,
      compactGeometry: true,
      commonBlockHeader: true,
      hybridCommonHeader: false,
      deltaGeometry: true,
      sharedLocalPalette: false,
    );
    return (math.min(individualBits, commonBits) + 7) ~/ 8;
  }


  List<List<_V3Bounds>> _regionBeamNeighborsFor(
    List<int> pixels,
    int fullWidth,
    int backgroundColor,
    List<_V3Bounds> regions,
    int maxRegions, {
    required bool useExtremeSearch,
  }) {
    final mergeNeighbors = <_V3RegionBeamNeighbor>[];
    if (regions.length > 1) {
      for (var left = 0; left < regions.length - 1; left++) {
        for (var right = left + 1; right < regions.length; right++) {
          final merged = _unionBounds(regions[left], regions[right]);
          final candidate = <_V3Bounds>[
            for (var i = 0; i < regions.length; i++)
              if (i != left && i != right) regions[i],
            merged,
          ];
          if (!_regionsDoNotOverlap(candidate)) continue;
          final addedArea =
              merged.area - regions[left].area - regions[right].area;
          mergeNeighbors.add(
            _V3RegionBeamNeighbor(_sortedRegions(candidate), addedArea),
          );
        }
      }
    }
    mergeNeighbors.sort(
      (left, right) => left.heuristic.compareTo(right.heuristic),
    );

    final splitNeighbors = <_V3RegionBeamNeighbor>[];
    if (regions.length < maxRegions) {
      for (var index = 0; index < regions.length; index++) {
        final region = regions[index];
        for (var cut = 1; cut < region.width; cut++) {
          final parts = _tightSplitRegion(
            pixels,
            fullWidth,
            backgroundColor,
            region,
            vertical: true,
            cut: cut,
          );
          _addRegionSplitNeighbor(splitNeighbors, regions, index, region, parts);
        }
        for (var cut = 1; cut < region.height; cut++) {
          final parts = _tightSplitRegion(
            pixels,
            fullWidth,
            backgroundColor,
            region,
            vertical: false,
            cut: cut,
          );
          _addRegionSplitNeighbor(splitNeighbors, regions, index, region, parts);
        }
      }
    }
    splitNeighbors.sort(
      (left, right) => left.heuristic.compareTo(right.heuristic),
    );

    final result = <List<_V3Bounds>>[];
    final seen = <String>{};
    final neighborLimit = useExtremeSearch
        ? _extremeRegionNeighbors
        : _regionBeamNeighbors;
    final perKindLimit = math.max(1, neighborLimit ~/ 2);
    for (final neighbor in [
      ...mergeNeighbors.take(perKindLimit),
      ...splitNeighbors.take(perKindLimit),
    ]) {
      if (seen.add(_regionListKey(neighbor.regions))) {
        result.add(neighbor.regions);
      }
    }
    return result;
  }

  void _addRegionSplitNeighbor(
    List<_V3RegionBeamNeighbor> output,
    List<_V3Bounds> regions,
    int replacedIndex,
    _V3Bounds original,
    List<_V3Bounds> parts,
  ) {
    if (parts.length != 2) return;
    final savedArea = original.area - parts[0].area - parts[1].area;
    if (savedArea <= 0) return;
    final candidate = <_V3Bounds>[
      for (var i = 0; i < regions.length; i++)
        if (i != replacedIndex) regions[i],
      ...parts,
    ];
    if (!_regionsDoNotOverlap(candidate)) return;
    output.add(_V3RegionBeamNeighbor(_sortedRegions(candidate), -savedArea));
  }

  List<_V3Bounds> _tightSplitRegion(
    List<int> pixels,
    int fullWidth,
    int backgroundColor,
    _V3Bounds region, {
    required bool vertical,
    required int cut,
  }) {
    final firstRect = vertical
        ? _V3Bounds(region.x, region.y, cut, region.height)
        : _V3Bounds(region.x, region.y, region.width, cut);
    final secondRect = vertical
        ? _V3Bounds(
            region.x + cut,
            region.y,
            region.width - cut,
            region.height,
          )
        : _V3Bounds(
            region.x,
            region.y + cut,
            region.width,
            region.height - cut,
          );
    return [
      _tightBoundsInRect(pixels, fullWidth, backgroundColor, firstRect),
      _tightBoundsInRect(pixels, fullWidth, backgroundColor, secondRect),
    ].whereType<_V3Bounds>().toList(growable: false);
  }

  static _V3Bounds _unionBounds(_V3Bounds left, _V3Bounds right) {
    final x = math.min(left.x, right.x);
    final y = math.min(left.y, right.y);
    final maxX = math.max(left.x + left.width, right.x + right.width);
    final maxY = math.max(left.y + left.height, right.y + right.height);
    return _V3Bounds(x, y, maxX - x, maxY - y);
  }

  List<_V3Bounds> _splitRegionsByEmptyLines(
    List<int> pixels,
    int fullWidth,
    int background,
    List<_V3Bounds> regions,
    int maxRegions,
  ) {
    final output = <_V3Bounds>[];
    for (final region in regions) {
      _splitRegionByBestEmptyLine(
        pixels,
        fullWidth,
        background,
        region,
        output,
        maxRegions,
      );
      if (output.length > maxRegions) return const <_V3Bounds>[];
    }
    return _sameRegionList(output, regions) ? const <_V3Bounds>[] : output;
  }

  void _splitRegionByBestEmptyLine(
    List<int> pixels,
    int fullWidth,
    int background,
    _V3Bounds region,
    List<_V3Bounds> output,
    int maxRegions,
  ) {
    final horizontalSplit = _bestEmptyRowSplit(
      pixels,
      fullWidth,
      background,
      region,
    );
    final verticalSplit = _bestEmptyColumnSplit(
      pixels,
      fullWidth,
      background,
      region,
    );
    final split = _betterRegionPartition(horizontalSplit, verticalSplit);
    if (split == null) {
      output.add(region);
      return;
    }

    for (final part in split.parts) {
      _splitRegionByBestEmptyLine(
        pixels,
        fullWidth,
        background,
        part,
        output,
        maxRegions,
      );
      if (output.length > maxRegions) return;
    }
  }

  _V3RegionPartition? _bestEmptyRowSplit(
    List<int> pixels,
    int fullWidth,
    int background,
    _V3Bounds region,
  ) {
    _V3RegionPartition? best;
    for (var y = region.y; y < region.y + region.height; y++) {
      if (_regionRowNonBackgroundCount(
            pixels,
            fullWidth,
            background,
            region,
            y,
          ) !=
          0) {
        continue;
      }
      final parts = [
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _V3Bounds(region.x, region.y, region.width, y - region.y),
        ),
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _V3Bounds(
            region.x,
            y + 1,
            region.width,
            region.y + region.height - y - 1,
          ),
        ),
      ].whereType<_V3Bounds>().toList();
      final partition = _partitionIfUseful(region, parts);
      if (partition != null &&
          (best == null || partition.savedArea > best.savedArea)) {
        best = partition;
      }
    }
    return best;
  }

  _V3RegionPartition? _bestEmptyColumnSplit(
    List<int> pixels,
    int fullWidth,
    int background,
    _V3Bounds region,
  ) {
    _V3RegionPartition? best;
    for (var x = region.x; x < region.x + region.width; x++) {
      if (_regionColumnNonBackgroundCount(
            pixels,
            fullWidth,
            background,
            region,
            x,
          ) !=
          0) {
        continue;
      }
      final parts = [
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _V3Bounds(region.x, region.y, x - region.x, region.height),
        ),
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _V3Bounds(
            x + 1,
            region.y,
            region.x + region.width - x - 1,
            region.height,
          ),
        ),
      ].whereType<_V3Bounds>().toList();
      final partition = _partitionIfUseful(region, parts);
      if (partition != null &&
          (best == null || partition.savedArea > best.savedArea)) {
        best = partition;
      }
    }
    return best;
  }

  List<_V3Bounds> _splitRegionsBySparseLines(
    List<int> pixels,
    int fullWidth,
    int background,
    List<_V3Bounds> regions,
    int maxRegions, {
    required int maxLineNonBackground,
  }) {
    final output = <_V3Bounds>[];
    for (final region in regions) {
      _splitRegionByBestSparseLine(
        pixels,
        fullWidth,
        background,
        region,
        output,
        maxRegions,
        maxLineNonBackground: maxLineNonBackground,
      );
      if (output.length > maxRegions) return const <_V3Bounds>[];
    }
    return _sameRegionList(output, regions) ? const <_V3Bounds>[] : output;
  }

  void _splitRegionByBestSparseLine(
    List<int> pixels,
    int fullWidth,
    int background,
    _V3Bounds region,
    List<_V3Bounds> output,
    int maxRegions, {
    required int maxLineNonBackground,
  }) {
    final horizontalSplit = _bestSparseRowSplit(
      pixels,
      fullWidth,
      background,
      region,
      maxLineNonBackground,
    );
    final verticalSplit = _bestSparseColumnSplit(
      pixels,
      fullWidth,
      background,
      region,
      maxLineNonBackground,
    );
    final split = _betterRegionPartition(horizontalSplit, verticalSplit);
    if (split == null) {
      output.add(region);
      return;
    }

    for (final part in split.parts) {
      _splitRegionByBestSparseLine(
        pixels,
        fullWidth,
        background,
        part,
        output,
        maxRegions,
        maxLineNonBackground: maxLineNonBackground,
      );
      if (output.length > maxRegions) return;
    }
  }

  _V3RegionPartition? _bestSparseRowSplit(
    List<int> pixels,
    int fullWidth,
    int background,
    _V3Bounds region,
    int maxLineNonBackground,
  ) {
    _V3RegionPartition? best;
    var y = region.y;
    while (y < region.y + region.height) {
      final count = _regionRowNonBackgroundCount(
        pixels,
        fullWidth,
        background,
        region,
        y,
      );
      if (count > maxLineNonBackground) {
        y++;
        continue;
      }

      final startY = y;
      while (y < region.y + region.height &&
          _regionRowNonBackgroundCount(
                pixels,
                fullWidth,
                background,
                region,
                y,
              ) <=
              maxLineNonBackground) {
        y++;
      }
      final endY = y - 1;
      final parts = [
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _V3Bounds(region.x, region.y, region.width, startY - region.y),
        ),
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _V3Bounds(region.x, startY, region.width, endY - startY + 1),
        ),
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _V3Bounds(
            region.x,
            endY + 1,
            region.width,
            region.y + region.height - endY - 1,
          ),
        ),
      ].whereType<_V3Bounds>().toList();
      final partition = _partitionIfUseful(region, parts);
      if (partition != null &&
          (best == null || partition.savedArea > best.savedArea)) {
        best = partition;
      }
    }
    return best;
  }

  _V3RegionPartition? _bestSparseColumnSplit(
    List<int> pixels,
    int fullWidth,
    int background,
    _V3Bounds region,
    int maxLineNonBackground,
  ) {
    _V3RegionPartition? best;
    var x = region.x;
    while (x < region.x + region.width) {
      final count = _regionColumnNonBackgroundCount(
        pixels,
        fullWidth,
        background,
        region,
        x,
      );
      if (count > maxLineNonBackground) {
        x++;
        continue;
      }

      final startX = x;
      while (x < region.x + region.width &&
          _regionColumnNonBackgroundCount(
                pixels,
                fullWidth,
                background,
                region,
                x,
              ) <=
              maxLineNonBackground) {
        x++;
      }
      final endX = x - 1;
      final parts = [
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _V3Bounds(region.x, region.y, startX - region.x, region.height),
        ),
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _V3Bounds(startX, region.y, endX - startX + 1, region.height),
        ),
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _V3Bounds(
            endX + 1,
            region.y,
            region.x + region.width - endX - 1,
            region.height,
          ),
        ),
      ].whereType<_V3Bounds>().toList();
      final partition = _partitionIfUseful(region, parts);
      if (partition != null &&
          (best == null || partition.savedArea > best.savedArea)) {
        best = partition;
      }
    }
    return best;
  }

  _V3RegionPartition? _partitionIfUseful(
    _V3Bounds original,
    List<_V3Bounds> parts,
  ) {
    if (parts.length < 2) return null;
    var area = 0;
    for (final part in parts) {
      area += part.area;
    }
    final savedArea = original.area - area;
    if (savedArea <= 0) return null;
    return _V3RegionPartition(List.unmodifiable(parts), savedArea);
  }

  _V3RegionPartition? _betterRegionPartition(
    _V3RegionPartition? a,
    _V3RegionPartition? b,
  ) {
    if (a == null) return b;
    if (b == null) return a;
    return a.savedArea >= b.savedArea ? a : b;
  }

  int _regionRowNonBackgroundCount(
    List<int> pixels,
    int fullWidth,
    int background,
    _V3Bounds region,
    int y,
  ) {
    var count = 0;
    for (var x = region.x; x < region.x + region.width; x++) {
      if (pixels[y * fullWidth + x] != background) count++;
    }
    return count;
  }

  int _regionColumnNonBackgroundCount(
    List<int> pixels,
    int fullWidth,
    int background,
    _V3Bounds region,
    int x,
  ) {
    var count = 0;
    for (var y = region.y; y < region.y + region.height; y++) {
      if (pixels[y * fullWidth + x] != background) count++;
    }
    return count;
  }

  _V3Bounds? _tightBoundsInRect(
    List<int> pixels,
    int fullWidth,
    int background,
    _V3Bounds rect,
  ) {
    if (rect.width <= 0 || rect.height <= 0) return null;

    var minX = rect.x + rect.width;
    var minY = rect.y + rect.height;
    var maxX = rect.x - 1;
    var maxY = rect.y - 1;

    for (var y = rect.y; y < rect.y + rect.height; y++) {
      for (var x = rect.x; x < rect.x + rect.width; x++) {
        if (pixels[y * fullWidth + x] == background) continue;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
    }

    if (maxX < minX || maxY < minY) return null;
    return _V3Bounds(minX, minY, maxX - minX + 1, maxY - minY + 1);
  }

  bool _sameRegionList(List<_V3Bounds> a, List<_V3Bounds> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].x != b[i].x ||
          a[i].y != b[i].y ||
          a[i].width != b[i].width ||
          a[i].height != b[i].height) {
        return false;
      }
    }
    return true;
  }

  List<List<_V3Bounds>> _findGreedyRectRegionVariants(
    List<int> pixels,
    int width,
    int height,
    int background,
    int maxRegions,
  ) {
    if (maxRegions == 0) return const <List<_V3Bounds>>[];

    const strategies = <_V3GreedyRectStrategy>[
      _V3GreedyRectStrategy(1, 1, _greedyTieLargestArea),
      _V3GreedyRectStrategy(1, 1, _greedyTieWidest),
      _V3GreedyRectStrategy(1, 1, _greedyTieTallest),
      _V3GreedyRectStrategy(-1, 1, _greedyTieLargestArea),
      _V3GreedyRectStrategy(1, -1, _greedyTieLargestArea),
      _V3GreedyRectStrategy(-1, -1, _greedyTieLargestArea),
    ];

    final variants = <List<_V3Bounds>>[];
    final seen = <String>{};
    for (final strategy in strategies) {
      final regions = _findGreedyRectRegionsWithStrategy(
        pixels,
        width,
        height,
        background,
        maxRegions,
        strategy,
      );
      if (regions.isEmpty) continue;
      final key = _regionListKey(regions);
      if (seen.add(key)) variants.add(regions);
    }
    return variants;
  }

  List<_V3Bounds> _findGreedyRectRegionsWithStrategy(
    List<int> pixels,
    int width,
    int height,
    int background,
    int maxRegions,
    _V3GreedyRectStrategy strategy,
  ) {
    final covered = List<bool>.filled(pixels.length, false);
    final regions = <_V3Bounds>[];

    while (true) {
      final startIndex = _findGreedyStartIndex(
        pixels,
        covered,
        width,
        height,
        background,
        strategy,
      );
      if (startIndex < 0) break;

      final startX = startIndex % width;
      final startY = startIndex ~/ width;
      final rect = _bestGreedyRectAt(
        pixels,
        covered,
        width,
        height,
        background,
        startX,
        startY,
        strategy,
      );

      regions.add(rect);
      if (regions.length > maxRegions) {
        return const <_V3Bounds>[];
      }

      for (var y = rect.y; y < rect.y + rect.height; y++) {
        for (var x = rect.x; x < rect.x + rect.width; x++) {
          covered[y * width + x] = true;
        }
      }
    }

    return _sortedRegions(regions);
  }

  int _findGreedyStartIndex(
    List<int> pixels,
    List<bool> covered,
    int width,
    int height,
    int background,
    _V3GreedyRectStrategy strategy,
  ) {
    final yStart = strategy.verticalDirection > 0 ? 0 : height - 1;
    final yEnd = strategy.verticalDirection > 0 ? height : -1;
    final xStart = strategy.horizontalDirection > 0 ? 0 : width - 1;
    final xEnd = strategy.horizontalDirection > 0 ? width : -1;

    for (var y = yStart; y != yEnd; y += strategy.verticalDirection) {
      for (var x = xStart; x != xEnd; x += strategy.horizontalDirection) {
        final index = y * width + x;
        if (pixels[index] != background && !covered[index]) return index;
      }
    }
    return -1;
  }

  _V3Bounds _bestGreedyRectAt(
    List<int> pixels,
    List<bool> covered,
    int width,
    int height,
    int background,
    int startX,
    int startY,
    _V3GreedyRectStrategy strategy,
  ) {
    var bestWidth = 1;
    var bestHeight = 1;
    var maxCandidateWidth = _greedyRunLength(
      pixels,
      covered,
      width,
      background,
      startX,
      startY,
      strategy.horizontalDirection,
    );

    for (var candidateHeight = 1; ; candidateHeight++) {
      final y = startY + (candidateHeight - 1) * strategy.verticalDirection;
      if (y < 0 || y >= height) break;

      final rowWidth = _greedyRunLength(
        pixels,
        covered,
        width,
        background,
        startX,
        y,
        strategy.horizontalDirection,
      );
      if (rowWidth == 0) break;

      maxCandidateWidth = math.min(maxCandidateWidth, rowWidth);
      if (_isBetterGreedyRect(
        maxCandidateWidth,
        candidateHeight,
        bestWidth,
        bestHeight,
        strategy.tieMode,
      )) {
        bestWidth = maxCandidateWidth;
        bestHeight = candidateHeight;
      }
    }

    final x = strategy.horizontalDirection > 0
        ? startX
        : startX - bestWidth + 1;
    final y = strategy.verticalDirection > 0 ? startY : startY - bestHeight + 1;
    return _V3Bounds(x, y, bestWidth, bestHeight);
  }

  int _greedyRunLength(
    List<int> pixels,
    List<bool> covered,
    int width,
    int background,
    int startX,
    int y,
    int horizontalDirection,
  ) {
    var run = 0;
    for (var x = startX; x >= 0 && x < width; x += horizontalDirection) {
      final index = y * width + x;
      if (pixels[index] == background || covered[index]) break;
      run++;
    }
    return run;
  }

  bool _isBetterGreedyRect(
    int width,
    int height,
    int bestWidth,
    int bestHeight,
    int tieMode,
  ) {
    final area = width * height;
    final bestArea = bestWidth * bestHeight;
    if (area != bestArea) return area > bestArea;
    return switch (tieMode) {
      _greedyTieWidest => width > bestWidth,
      _greedyTieTallest => height > bestHeight,
      _ => height > bestHeight,
    };
  }

  String _regionListKey(List<_V3Bounds> regions) {
    final parts = <String>[];
    for (final region in regions) {
      parts.add('${region.x},${region.y},${region.width},${region.height}');
    }
    return parts.join(';');
  }

  static List<_V3Bounds> _sortedRegions(Iterable<_V3Bounds> regions) {
    return List<_V3Bounds>.of(regions)..sort((left, right) {
      final byY = left.y.compareTo(right.y);
      if (byY != 0) return byY;
      final byX = left.x.compareTo(right.x);
      if (byX != 0) return byX;
      final byHeight = left.height.compareTo(right.height);
      return byHeight != 0 ? byHeight : left.width.compareTo(right.width);
    });
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

  List<List<_V3SolidRect>> _solidRectVariants(
    List<int> pixels,
    int width,
    int height,
    int background, {
    required int maxRects,
  }) {
    final horizontal = <_V3SolidRect>[];
    for (var y = 0; y < height; y++) {
      var x = 0;
      while (x < width) {
        final color = pixels[y * width + x];
        if (color == background) {
          x++;
          continue;
        }
        final start = x;
        while (x < width && pixels[y * width + x] == color) {
          x++;
        }
        horizontal.add(
          _V3SolidRect(_V3Bounds(start, y, x - start, 1), color),
        );
      }
    }

    final vertical = <_V3SolidRect>[];
    for (var x = 0; x < width; x++) {
      var y = 0;
      while (y < height) {
        final color = pixels[y * width + x];
        if (color == background) {
          y++;
          continue;
        }
        final start = y;
        while (y < height && pixels[y * width + x] == color) {
          y++;
        }
        vertical.add(
          _V3SolidRect(_V3Bounds(x, start, 1, y - start), color),
        );
      }
    }

    final mergedHorizontal = _mergeSolidRuns(horizontal, vertical: false);
    final mergedVertical = _mergeSolidRuns(vertical, vertical: true);
    return <List<_V3SolidRect>>[
      if (mergedHorizontal.isNotEmpty && mergedHorizontal.length <= maxRects)
        mergedHorizontal,
      if (mergedVertical.isNotEmpty && mergedVertical.length <= maxRects)
        mergedVertical,
    ];
  }

  List<_V3SolidRect> _mergeSolidRuns(
    List<_V3SolidRect> runs, {
    required bool vertical,
  }) {
    final merged = <_V3SolidRect>[];
    final latestByShape = <String, int>{};
    for (final run in runs) {
      final bounds = run.bounds;
      final key = vertical
          ? '${bounds.y}:${bounds.height}:${run.color}'
          : '${bounds.x}:${bounds.width}:${run.color}';
      final previousIndex = latestByShape[key];
      if (previousIndex != null) {
        final previous = merged[previousIndex];
        final touches = vertical
            ? previous.bounds.x + previous.bounds.width == bounds.x
            : previous.bounds.y + previous.bounds.height == bounds.y;
        if (touches) {
          merged[previousIndex] = _V3SolidRect(
            _V3Bounds(
              previous.bounds.x,
              previous.bounds.y,
              vertical
                  ? previous.bounds.width + bounds.width
                  : previous.bounds.width,
              vertical
                  ? previous.bounds.height
                  : previous.bounds.height + bounds.height,
            ),
            run.color,
          );
          continue;
        }
      }
      latestByShape[key] = merged.length;
      merged.add(run);
    }
    return merged;
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
    if (bounds.x < 0 ||
        bounds.y < 0 ||
        bounds.width <= 0 ||
        bounds.height <= 0 ||
        bounds.x + bounds.width > imageWidth ||
        bounds.y + bounds.height > imageHeight) {
      throw const MCOImageInvalidInputException(
        'Invalid v3 region geometry',
      );
    }

    final xBits = compactGeometry ? _geometryBits(imageWidth) : 8;
    final yBits = compactGeometry ? _geometryBits(imageHeight) : 8;
    writer
      ..writeBits(bounds.x, xBits)
      ..writeBits(bounds.y, yBits);

    if (!compactGeometry) {
      writer
        ..writeBits(bounds.width - 1, xBits)
        ..writeBits(bounds.height - 1, yBits);
      return;
    }

    // Once x/y are known, width/height cannot exceed the remaining image
    // extent. Using that smaller bound is never worse than the old full-axis
    // bit width and becomes cheaper near the right/bottom edges.
    writer
      ..writeBits(
        bounds.width - 1,
        _geometryBits(imageWidth - bounds.x),
      )
      ..writeBits(
        bounds.height - 1,
        _geometryBits(imageHeight - bounds.y),
      );
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
    if (x >= imageWidth || y >= imageHeight) {
      throw const MCOImageInvalidPayloadException('Invalid v3 region origin');
    }

    final widthBits =
        compactGeometry ? _geometryBits(imageWidth - x) : xBits;
    final heightBits =
        compactGeometry ? _geometryBits(imageHeight - y) : yBits;
    final width = reader.readBits(widthBits) + 1;
    final height = reader.readBits(heightBits) + 1;
    final bounds = _V3Bounds(x, y, width, height);
    if (x + width > imageWidth || y + height > imageHeight) {
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
    String? variantLabel,
    required bool commonBlockHeader,
    required bool hybridCommonHeader,
    required bool deltaGeometry,
    required bool sharedLocalPalette,
  }) {
    final suffixes = <String>[
      ?variantLabel,
      if (hybridCommonHeader) 'hybrid'
      else if (commonBlockHeader) 'common',
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

class _V3PaletteRefRange {
  final int start;
  final int end;

  const _V3PaletteRefRange(this.start, this.end);

  int get length => end - start + 1;
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

class _V3LzTokenCache {
  final Map<String, _V3LzTokenCacheEntry> entries =
      <String, _V3LzTokenCacheEntry>{};
}

class _V3LzTokenCacheEntry {
  final List<_V3LzPixelToken> greedyTokens;
  final int greedyBitCost;

  bool optimalComputed = false;
  List<_V3LzPixelToken>? optimalTokens;
  int? optimalBitCost;

  _V3LzTokenCacheEntry({
    required this.greedyTokens,
    required this.greedyBitCost,
  });
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

class _V3LzMatchOption {
  final int distance;
  final int maxLength;
  final int distanceBitCost;

  const _V3LzMatchOption(
    this.distance,
    this.maxLength,
    this.distanceBitCost,
  );
}

class _V3LzParseStep {
  final int end;
  final int distance;

  const _V3LzParseStep.literal(this.end) : distance = 0;

  const _V3LzParseStep.match(this.end, this.distance);
}

class _V3LzLengthCostRange {
  final int minLength;
  final int maxLength;
  final int bitCost;

  const _V3LzLengthCostRange(this.minLength, this.maxLength, this.bitCost);
}

class _V3LzRangeMinimum {
  final int cost;
  final int index;

  const _V3LzRangeMinimum(this.cost, this.index);
}

class _V3LzRangeMinimumTree {
  static const int _infinity = 1 << 60;

  final int _size;
  final List<int> _costs;
  final List<int> _indices;

  factory _V3LzRangeMinimumTree(int length) {
    var size = 1;
    while (size < length) {
      size <<= 1;
    }
    return _V3LzRangeMinimumTree._(
      size,
      List<int>.filled(size * 2, _infinity),
      List<int>.filled(size * 2, -1),
    );
  }

  _V3LzRangeMinimumTree._(this._size, this._costs, this._indices);

  void update(int index, int cost) {
    var node = _size + index;
    _costs[node] = cost;
    _indices[node] = index;
    node >>= 1;
    while (node > 0) {
      _pull(node);
      node >>= 1;
    }
  }

  _V3LzRangeMinimum? query(int start, int end) {
    if (start >= end) return null;
    var left = start + _size;
    var right = end + _size;
    var bestCost = _infinity;
    var bestIndex = -1;
    while (left < right) {
      if (left.isOdd) {
        final candidate = _better(
          bestCost,
          bestIndex,
          _costs[left],
          _indices[left],
        );
        bestCost = candidate.$1;
        bestIndex = candidate.$2;
        left++;
      }
      if (right.isOdd) {
        right--;
        final candidate = _better(
          bestCost,
          bestIndex,
          _costs[right],
          _indices[right],
        );
        bestCost = candidate.$1;
        bestIndex = candidate.$2;
      }
      left >>= 1;
      right >>= 1;
    }
    return bestIndex < 0 ? null : _V3LzRangeMinimum(bestCost, bestIndex);
  }

  void _pull(int node) {
    final best = _better(
      _costs[node * 2],
      _indices[node * 2],
      _costs[node * 2 + 1],
      _indices[node * 2 + 1],
    );
    _costs[node] = best.$1;
    _indices[node] = best.$2;
  }

  static (int, int) _better(
    int leftCost,
    int leftIndex,
    int rightCost,
    int rightIndex,
  ) {
    if (rightCost < leftCost ||
        rightCost == leftCost && rightIndex > leftIndex) {
      return (rightCost, rightIndex);
    }
    return (leftCost, leftIndex);
  }
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

class _V3RowDeltaDecision {
  final int op;
  final int extendedOp;
  final int predictor;
  final List<_V3RowDeltaChange> changes;
  final int bitCost;

  const _V3RowDeltaDecision({
    required this.op,
    required this.extendedOp,
    required this.predictor,
    required this.changes,
    required this.bitCost,
  });
}

class _V3CompactRowDeltaDecision {
  final int op;
  final int predictor;
  final List<_V3RowDeltaChange> changes;
  final bool useResidual;
  final int bitCost;

  const _V3CompactRowDeltaDecision({
    required this.op,
    this.predictor = 0,
    required this.changes,
    this.useResidual = false,
    required this.bitCost,
  });
}

class _V3CompactValueEncoding {
  final bool useResidual;
  final int bitCost;

  const _V3CompactValueEncoding(this.useResidual, this.bitCost);
}

class _V3Bounds {
  final int x;
  final int y;
  final int width;
  final int height;

  const _V3Bounds(this.x, this.y, this.width, this.height);

  int get area => width * height;
}

class _V3RegionVariant {
  final List<_V3Bounds> regions;
  final String? label;

  const _V3RegionVariant(this.regions, this.label);
}

class _V3RegionPartition {
  final List<_V3Bounds> parts;
  final int savedArea;

  const _V3RegionPartition(this.parts, this.savedArea);
}

class _V3RegionBeamState {
  final List<_V3Bounds> regions;
  final int cost;

  const _V3RegionBeamState(this.regions, this.cost);
}

class _V3RegionBeamNeighbor {
  final List<_V3Bounds> regions;
  final int heuristic;

  const _V3RegionBeamNeighbor(this.regions, this.heuristic);
}

class _V3GreedyRectStrategy {
  final int horizontalDirection;
  final int verticalDirection;
  final int tieMode;

  const _V3GreedyRectStrategy(
    this.horizontalDirection,
    this.verticalDirection,
    this.tieMode,
  );
}

class _V3Dimensions {
  final int width;
  final int height;

  const _V3Dimensions({
    required this.width,
    required this.height,
  });
}

class _V3BlockBodyEncoding {
  final Uint8List bytes;
  final int bitLength;

  const _V3BlockBodyEncoding({
    required this.bytes,
    required this.bitLength,
  });
}

class _V3PreparedRegion {
  final _V3Bounds bounds;
  final List<int> cropped;
  final List<List<int>> scanOrders;

  const _V3PreparedRegion({
    required this.bounds,
    required this.cropped,
    required this.scanOrders,
  });

  List<int> linearFor(ScanMode scan) => scanOrders[scan.index];
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

class _V3SolidRect {
  final _V3Bounds bounds;
  final int color;

  const _V3SolidRect(this.bounds, this.color);
}

class _V3Base91 {
  static const String _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
      '!#\$%&()*+,./:;<=>?@[]^_`{|}~"';
  static final Map<int, int> _decodeTable = {
    for (var i = 0; i < _alphabet.length; i++) _alphabet.codeUnitAt(i): i,
  };

  static String encode(Uint8List bytes) {
    final output = StringBuffer();
    var queue = 0;
    var bitCount = 0;
    for (final byte in bytes) {
      queue |= byte << bitCount;
      bitCount += 8;
      if (bitCount > 13) {
        var value = queue & 8191;
        if (value > 88) {
          queue >>= 13;
          bitCount -= 13;
        } else {
          value = queue & 16383;
          queue >>= 14;
          bitCount -= 14;
        }
        output
          ..write(_alphabet[value % 91])
          ..write(_alphabet[value ~/ 91]);
      }
    }
    if (bitCount > 0) {
      output.write(_alphabet[queue % 91]);
      if (bitCount > 7 || queue > 90) {
        output.write(_alphabet[queue ~/ 91]);
      }
    }
    return output.toString();
  }

  static Uint8List decode(String text) {
    final output = <int>[];
    var value = -1;
    var queue = 0;
    var bitCount = 0;
    for (final codeUnit in text.codeUnits) {
      final decoded = _decodeTable[codeUnit];
      if (decoded == null) {
        throw const MCOImageInvalidPayloadException('Invalid basE91 character');
      }
      if (value < 0) {
        value = decoded;
      } else {
        value += decoded * 91;
        queue |= value << bitCount;
        bitCount += (value & 8191) > 88 ? 13 : 14;
        while (bitCount > 7) {
          output.add(queue & 0xff);
          queue >>= 8;
          bitCount -= 8;
        }
        value = -1;
      }
    }
    if (value >= 0) {
      output.add((queue | (value << bitCount)) & 0xff);
    }
    return Uint8List.fromList(output);
  }
}

class _V3BackgroundCandidate {
  final int color;
  final int rank;

  const _V3BackgroundCandidate(this.color, this.rank);
}

class _V3RegionPlanCache {
  final List<_V3PreparedRegion> preparedRegions;
  final bool useHighCompressionExtras;
  final bool reducedCostEvaluator;

  bool individualComputed = false;
  bool commonComputed = false;
  bool hybridComputed = false;
  bool sharedComputed = false;
  bool sharedIndividualComputed = false;
  bool sharedHybridComputed = false;

  _V3RegionPlan? individualPlan;
  _V3RegionPlan? commonPlan;
  _V3RegionPlan? hybridPlan;
  _V3RegionPlan? sharedPlan;
  _V3RegionPlan? sharedIndividualPlan;
  _V3RegionPlan? sharedHybridPlan;

  _V3RegionPlanCache({
    required this.preparedRegions,
    required this.useHighCompressionExtras,
    required this.reducedCostEvaluator,
  });
}

class _V3RegionPlan {
  final List<_V3RegionBlock>? blocks;
  final List<int>? sharedLocalPalette;
  final MCOImageV3BlockAlgorithm? commonAlgorithm;
  final ScanMode? commonScan;
  final List<bool>? usesCommonHeader;

  const _V3RegionPlan({
    required this.blocks,
    this.sharedLocalPalette,
    this.commonAlgorithm,
    this.commonScan,
    this.usesCommonHeader,
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

  void writeBitStream(Uint8List bytes, int bitLength) {
    if (bitLength < 0 || bitLength > bytes.length * 8) {
      throw const MCOImageInvalidInputException(
        'Invalid source bitstream length',
      );
    }
    var remaining = bitLength;
    var byteIndex = 0;
    while (remaining > 0) {
      final take = math.min(8, remaining);
      final mask = (1 << take) - 1;
      writeBits(bytes[byteIndex] & mask, take);
      remaining -= take;
      byteIndex++;
    }
  }

  void writeZeroBits(int bits) {
    if (bits < 0) {
      throw const MCOImageInvalidInputException('Invalid bit length');
    }
    var remaining = bits;
    while (remaining > 0) {
      final take = math.min(remaining, 32);
      writeBits(0, take);
      remaining -= take;
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

  void writeRangeCompactUint(int value, int maxValue) {
    if (maxValue < 0 || value < 0 || value > maxValue) {
      throw const MCOImageInvalidInputException(
        'Range compact uint is out of range',
      );
    }
    if (maxValue <= 7) {
      writeBits(value, maxValue.bitLength);
      return;
    }
    writeCompactUint(value);
  }

  void writeBoundedCompactUint(int value, int maxValue) {
    if (maxValue < 0 || value < 0 || value > maxValue) {
      throw const MCOImageInvalidInputException(
        'Bounded compact uint is out of range',
      );
    }

    // A known range of 0..7 needs at most three fixed bits. This is always
    // no longer than the prefix-based bounded format and can become a
    // zero-bit field when maxValue == 0.
    if (maxValue <= 7) {
      writeBits(value, maxValue.bitLength);
      return;
    }

    if (value <= 3) {
      writeBits(0, 1);
      writeBits(value, 2);
      return;
    }
    if (value <= 19) {
      writeBits(1, 2);
      writeBits(value - 4, 4);
      return;
    }
    if (value <= 275) {
      writeBits(3, 3);
      writeBits(value - 20, 8);
      return;
    }

    writeBits(7, 3);
    final tailBits = (maxValue - 276).bitLength;
    writeBits(value - 276, tailBits);
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

  int readRangeCompactUint(int maxValue) {
    if (maxValue < 0) {
      throw const MCOImageInvalidPayloadException(
        'Invalid range compact uint limit',
      );
    }
    final value = maxValue <= 7
        ? readBits(maxValue.bitLength)
        : readCompactUint();
    if (value > maxValue) {
      throw const MCOImageInvalidPayloadException(
        'Range compact uint exceeds limit',
      );
    }
    return value;
  }

  int readBoundedCompactUint(int maxValue) {
    if (maxValue < 0) {
      throw const MCOImageInvalidPayloadException(
        'Invalid bounded compact uint limit',
      );
    }

    if (maxValue <= 7) {
      return readBits(maxValue.bitLength);
    }

    late final int value;
    if (readBits(1) == 0) {
      value = readBits(2);
    } else if (readBits(1) == 0) {
      value = readBits(4) + 4;
    } else if (readBits(1) == 0) {
      value = readBits(8) + 20;
    } else {
      if (maxValue < 276) {
        throw const MCOImageInvalidPayloadException(
          'Invalid bounded compact uint escape',
        );
      }
      final tailBits = (maxValue - 276).bitLength;
      value = readBits(tailBits) + 276;
    }

    if (value > maxValue) {
      throw const MCOImageInvalidPayloadException(
        'Bounded compact uint exceeds limit',
      );
    }
    return value;
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
