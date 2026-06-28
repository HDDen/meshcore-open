import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:math' as math;
import 'dart:typed_data';

import 'mcoimg_palette.dart';

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

enum MCOImageEncodingVersion { v1Legacy, v2 }

enum MCOImageOutputTarget { text, binary }

enum _AdaptivePaletteOrder {
  frequency,
  bitplaneOptimized,
  profileId,
  rgbProximity,
  transitionFrequency,
  multiStartOptimized,
}

enum _CompactRowDeltaPaletteOrder {
  frequency,
  transitionFrequency,
}

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

  const MCOImageBackgroundCandidate({
    required this.color,
    required this.rank,
  });
}

class EncodedMCOImage {
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
    this.codecVersion = MCOImageCodec._v2EncodeVersion,
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
    this.compressionLevel = MCOImageCodec.compressionLevelHigh,
  });
}

class _MCOImageCandidateDebugEntry {
  final String label;
  final Duration elapsed;
  final EncodedMCOImage candidate;
  final bool wasBest;

  const _MCOImageCandidateDebugEntry({
    required this.label,
    required this.elapsed,
    required this.candidate,
    required this.wasBest,
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

class MCOImageCodec {
  final List<_MCOImageCandidateDebugEntry> _candidateDebugEntries =
      <_MCOImageCandidateDebugEntry>[];

  static const String prefix = 'im:';
  static const int _encodeVersion = 1;
  static const int _v2EncodeVersion = 2;
  static const int compressionLevelHigh = 0;
  static const int compressionLevelNormal = 1;
  static const int compressionLevelExtreme = 2;
  static const int defaultCompressionLevel = compressionLevelHigh;
  static const int _minSupportedVersion = 0;
  static const int _maxSupportedVersion = 2;
  static const int maxSupportedVersion = _maxSupportedVersion;
  static const int _containerBlock = 0;
  static const int _containerRegions = 1;
  static const int _paletteKindFixed = 0;
  static const int _paletteKindDynamic = 1;
  static const int _v2TransparentProfileFlag = 0x10;
  static const int _v2ProfileIdMask = 0x0f;
  static const int _v2FixedBlockExtensionImplicitWhite = 0x01;
  static const int _v2FixedBlockExtensionUnaligned = 0x02;
  static const int _minSize = 1;
  static const int _maxSize = 256;
  static const int _legacyMaxRegions = 8;
  static const int _defaultMaxRegions = 16;
  static const int _maxV2Regions = 32;
  static const int _maxDynamicLocalPalette = 64;
  static const int _dynamicPaletteDescriptorBits = 2;
  static const int _dynamicPaletteDescriptorSortedDelta = 0;
  static const int _dynamicPaletteDescriptorRangeRuns = 1;
  static const int _dynamicPaletteDescriptorProfileBitmap = 2;
  static const int _dynamicPaletteDescriptorBankBitmaps = 3;
  static const int _fixedPaletteDescriptorBits = 2;
  static const int _fixedPaletteDescriptorBitmap = 0;
  static const int _fixedPaletteDescriptorSortedDelta = 1;
  static const int _fixedPaletteDescriptorRangeRuns = 2;
  static const int _maxFrequentBackgroundCandidates = 8;
  static const int _maxExhaustiveBackgroundColors = 64;
  static const int _maxExhaustiveBackgroundPixels = 4096;
  static const int _minLzMatchLength = 3;
  static const int _maxLzMatchCandidates = 32;
  static const int _maxOptimalLzPixels = 1024;
  static const int _maxMultiStartBitplanesPixels = 4096;
  static const int _maxBeamRegionPixels = 4096;
  static const int _regionBeamWidth = 3;
  static const int _regionBeamDepth = 2;
  static const int _regionBeamNeighbors = 8;

  // Extreme region search used to scale its width/depth/neighbour count from
  // maxRegions (32 -> 64/64/128), which made the number of evaluated layouts
  // explode. These balanced limits search noticeably deeper than High while
  // keeping the amount of work bounded and predictable.
  static const int _maxExtremeRegionPixels = 1536;
  static const int _maxExtremeRegionComponents = 20;
  static const int _maxExtremeRegionBackgroundRank = 5;
  static const int _maxExtremeRegionSearchRegions = 20;
  static const int _extremeRegionBeamWidth = 10;
  static const int _extremeRegionBeamDepth = 8;
  static const int _extremeRegionNeighbors = 32;
  static const int _extremeRegionResultLimit = 10;
  static const int _extremeRegionEvaluationBudget = 1536;

  static const int _greedyTieLargestArea = 0;
  static const int _greedyTieWidest = 1;
  static const int _greedyTieTallest = 2;

  static const List<ImageMode> _blockModes = [
    ImageMode.rawGlobal,
    ImageMode.rawLocal,
    ImageMode.rleLocal,
    ImageMode.sparseBg,
  ];

  static const List<ImageMode> _v2BlockModes = [
    ImageMode.rawGlobal,
    ImageMode.rawLocal,
    ImageMode.rleLocal,
    ImageMode.sparseBg,
    ImageMode.biColorMask,
    ImageMode.rowRepeat,
    ImageMode.rowDelta,
  ];

  static const List<ImageMode> _dynamicBlockModes = [
    ImageMode.rawLocal,
    ImageMode.rleLocal,
    ImageMode.sparseBg,
    ImageMode.biColorMask,
    ImageMode.rowRepeat,
    ImageMode.rowDelta,
  ];

  static const List<ImageMode> _modeTieOrder = [
    ImageMode.extended,
    ImageMode.biColorMask,
    ImageMode.sparseBg,
    ImageMode.rowRepeat,
    ImageMode.rowDelta,
    ImageMode.rleLocal,
    ImageMode.rawLocal,
    ImageMode.rawGlobal,
    ImageMode.regionsBg,
  ];

  static const int _extendedSubmodeBits = 3;

  EncodedMCOImage encode(
    MCOImage image, {
    int? maxChars,
    int? backgroundColor,
    List<MCOImageBackgroundCandidate>? backgroundCandidates,
    List<ScanMode>? scanModes,
    bool includeNonScanCandidates = true,
    int maxRegions = _defaultMaxRegions,
    MCOImageEncodingVersion encodingVersion = MCOImageEncodingVersion.v2,
    MCOImageOutputTarget outputTarget = MCOImageOutputTarget.text,
    int compressionLevel = defaultCompressionLevel,
  }) {
    final diagnostics = debugEncode(
      image,
      backgroundColor: backgroundColor,
      backgroundCandidates: backgroundCandidates,
      scanModes: scanModes,
      includeNonScanCandidates: includeNonScanCandidates,
      maxRegions: maxRegions,
      encodingVersion: encodingVersion,
      outputTarget: outputTarget,
      compressionLevel: compressionLevel,
    );
    final result = diagnostics.result;
    if (maxChars != null && result.charLength > maxChars) {
      throw MCOImageTooLargeException(
        'Encoded image is ${result.charLength} chars, max is $maxChars',
      );
    }
    return result;
  }

  MCOImageEncodeDiagnostics debugEncode(
    MCOImage image, {
    int? backgroundColor,
    List<MCOImageBackgroundCandidate>? backgroundCandidates,
    List<ScanMode>? scanModes,
    bool includeNonScanCandidates = true,
    int maxRegions = _defaultMaxRegions,
    MCOImageEncodingVersion encodingVersion = MCOImageEncodingVersion.v2,
    MCOImageOutputTarget outputTarget = MCOImageOutputTarget.text,
    int compressionLevel = defaultCompressionLevel,
  }) {
    _candidateDebugEntries.clear();
    _validateImage(image);
    final effectiveCompressionLevel = _normalizeCompressionLevel(
      compressionLevel,
    );
    if (maxRegions < 0) {
      throw const MCOImageInvalidInputException('maxRegions must be >= 0');
    }
    maxRegions = math.min(maxRegions, _maxV2Regions);
    if (backgroundColor != null) {
      _validateColor(backgroundColor, image.paletteProfile, 'backgroundColor');
    }
    if (backgroundCandidates != null) {
      for (final candidate in backgroundCandidates) {
        _validateColor(
          candidate.color,
          image.paletteProfile,
          'backgroundCandidate',
        );
      }
    }
    if (image.transparentColor != null) {
      _validateColor(
        image.transparentColor!,
        image.paletteProfile,
        'transparentColor',
      );
    }

    if (encodingVersion == MCOImageEncodingVersion.v1Legacy) {
      if (image.transparentColor != null) {
        throw const MCOImageInvalidInputException(
          'Legacy v1 encoding does not support transparency',
        );
      }
      if (image.paletteProfile.isDynamic) {
        throw const MCOImageInvalidInputException(
          'Legacy v1 encoding supports fixed palettes only',
        );
      }
      final timer = Stopwatch()..start();
      final diagnostics = _debugEncodeLegacyV1(
        image,
        backgroundColor: backgroundColor,
        maxRegions: maxRegions,
        outputTarget: outputTarget,
        compressionLevel: effectiveCompressionLevel,
      );
      timer.stop();
      _flushCandidateDebugLog(effectiveCompressionLevel);
      debugPrint(
        '[MCOimg][${_compressionLevelLabel(effectiveCompressionLevel)}] '
        '${diagnostics.candidates.length}/${diagnostics.candidates.length} '
        '(100.0%); '
        'bytes=${diagnostics.result.byteLength}; '
        'chars=${diagnostics.result.charLength}; '
        '${timer.elapsed.inMilliseconds} ms; '
        'COMPLETE; '
        'version=v1; '
        'size=${image.width}x${image.height}; '
        'container=${diagnostics.result.container}; '
        'mode=${diagnostics.result.mode.name}; '
        'scan=${diagnostics.result.scan.name};');
      return diagnostics;
    }

    final useHighCompressionExtras =
        effectiveCompressionLevel != compressionLevelNormal;
    final effectiveMaxRegions = useHighCompressionExtras
        ? (maxRegions == _defaultMaxRegions ? _maxV2Regions : maxRegions)
        : math.min(maxRegions, _defaultMaxRegions);
    final timer = Stopwatch()..start();
    final diagnostics = _debugEncodeV2(
      image,
      backgroundColor: backgroundColor,
      backgroundCandidates: backgroundCandidates,
      scanModes: scanModes,
      includeNonScanCandidates: includeNonScanCandidates,
      maxRegions: effectiveMaxRegions,
      outputTarget: outputTarget,
      compressionLevel: effectiveCompressionLevel,
    );
    timer.stop();
    _flushCandidateDebugLog(effectiveCompressionLevel);
    debugPrint(
      '[MCOimg][${_compressionLevelLabel(effectiveCompressionLevel)}] '
      '${diagnostics.candidates.length}/${diagnostics.candidates.length} '
      '(100.0%); '
      'bytes=${diagnostics.result.byteLength}; '
      'chars=${diagnostics.result.charLength}; '
      '${timer.elapsed.inMilliseconds} ms; '
      'COMPLETE; '
      'version=v2; '
      'size=${image.width}x${image.height}; '
      'container=${diagnostics.result.container}; '
      'mode=${diagnostics.result.mode.name}; '
      'scan=${diagnostics.result.scan.name};');
    return diagnostics;
  }

  static int _normalizeCompressionLevel(int compressionLevel) {
    return switch (compressionLevel) {
      compressionLevelNormal => compressionLevelNormal,
      compressionLevelExtreme => compressionLevelExtreme,
      _ => compressionLevelHigh,
    };
  }

  static String _compressionLevelLabel(int compressionLevel) {
    return switch (_normalizeCompressionLevel(compressionLevel)) {
      compressionLevelNormal => 'Normal',
      compressionLevelExtreme => 'Extreme',
      _ => 'High',
    };
  }

  static String _referenceEncodingLabel(
    DynamicPaletteReferenceEncoding? referenceEncoding,
  ) {
    return referenceEncoding?.name ?? 'none';
  }

  void _logCandidateDebug({
    required int compressionLevel,
    required String label,
    required Duration elapsed,
    required EncodedMCOImage candidate,
    required MCOImageOutputTarget outputTarget,
    required EncodedMCOImage? currentBest,
  }) {
    _candidateDebugEntries.add(
      _MCOImageCandidateDebugEntry(
        label: label,
        elapsed: elapsed,
        candidate: candidate,
        wasBest: _isBetterCandidate(candidate, currentBest, outputTarget),
      ),
    );
  }

  void _flushCandidateDebugLog(int compressionLevel) {
    final total = _candidateDebugEntries.length;
    for (var index = 0; index < total; index++) {
      final entry = _candidateDebugEntries[index];
      final candidate = entry.candidate;
      final completed = index + 1;
      final percentage = total == 0 ? 100.0 : completed * 100 / total;
      debugPrint(
        '[MCOimg][${_compressionLevelLabel(compressionLevel)}] '
        '$completed/$total (${percentage.toStringAsFixed(1)}%); '
        'bytes=${candidate.byteLength}; '
        'chars=${candidate.charLength}; '
        '${entry.elapsed.inMilliseconds} ms; '
        '${entry.wasBest ? 'BEST' : 'not-best'}; '
        '${entry.label}; '
        'container=${candidate.container}; '
        'mode=${candidate.mode.name}; '
        'scan=${candidate.scan.name}; '
        'bg=${candidate.backgroundColor ?? -1}; '
        'bgRank=${candidate.backgroundRank}; '
        'bounds=${candidate.boundsPresent};');
    }
    _candidateDebugEntries.clear();
  }

  static List<MCOImageBackgroundCandidate> backgroundCandidatesFor(
    MCOImage image, {
    int? backgroundColor,
    required int compressionLevel,
  }) {
    _validateImage(image);
    if (backgroundColor != null) {
      _validateColor(backgroundColor, image.paletteProfile, 'backgroundColor');
    }
    final effectiveCompressionLevel = _normalizeCompressionLevel(
      compressionLevel,
    );
    final useHighCompressionExtras =
        effectiveCompressionLevel != compressionLevelNormal;
    final preferredBackgroundColor = backgroundColor ?? image.transparentColor;
    final candidates = image.paletteProfile.isDynamic
        ? _dynamicBackgroundCandidates(
            image,
            preferredBackgroundColor,
            exhaustiveSmallImage: useHighCompressionExtras,
          )
        : _backgroundCandidates(
            image,
            preferredBackgroundColor,
            exhaustiveSmallImage: useHighCompressionExtras,
          );
    return candidates
        .map(
          (candidate) => MCOImageBackgroundCandidate(
            color: candidate.color,
            rank: candidate.rank,
          ),
        )
        .toList(growable: false);
  }

  static EncodedMCOImage selectBestCandidate(
    Iterable<EncodedMCOImage> candidates,
    MCOImageOutputTarget outputTarget,
  ) {
    EncodedMCOImage? best;
    for (final candidate in candidates) {
      if (_isBetterCandidate(candidate, best, outputTarget)) {
        best = candidate;
      }
    }
    if (best == null) {
      throw const MCOImageTooLargeException(
        'No MCOimg candidates were produced',
      );
    }
    return best;
  }

  MCOImageEncodeDiagnostics _debugEncodeLegacyV1(
    MCOImage image, {
    int? backgroundColor,
    int maxRegions = _defaultMaxRegions,
    MCOImageOutputTarget outputTarget = MCOImageOutputTarget.text,
    required int compressionLevel,
  }) {
    final effectiveMaxRegions = maxRegions > _defaultMaxRegions
        ? _defaultMaxRegions
        : maxRegions;
    final backgroundCandidates = _backgroundCandidates(image, backgroundColor);
    final candidates = <EncodedMCOImage>[];
    EncodedMCOImage? best;
    for (final background in backgroundCandidates) {
      final bg = background.color;
      final bounds = _findBounds(image.pixels, image.width, image.height, bg);
      for (final scan in ScanMode.values) {
        final linear = _toScanOrder(
          image.pixels,
          image.width,
          image.height,
          scan,
        );
        for (final mode in _blockModes) {
          final candidateTimer = Stopwatch()..start();
          final payload = _buildPayload(
            image,
            linear,
            mode,
            scan,
            dataWidth: image.width,
            dataHeight: image.height,
            backgroundColor: bg,
          );
          final candidate = _candidateFromPayload(
            payload,
            mode,
            scan,
            backgroundColor: bg,
            backgroundRank: background.rank,
          );
          candidateTimer.stop();
          _logCandidateDebug(
            compressionLevel: compressionLevel,
            label: 'v1 block scan=${scan.name} mode=${mode.name}',
            elapsed: candidateTimer.elapsed,
            candidate: candidate,
            outputTarget: outputTarget,
            currentBest: best,
          );
          candidates.add(candidate);
          if (_isBetterCandidate(candidate, best, outputTarget)) {
            best = candidate;
          }
        }

        if (bounds.area < image.width * image.height) {
          final cropped = _cropPixels(image.pixels, image.width, bounds);
          final boundedLinear = _toScanOrder(
            cropped,
            bounds.width,
            bounds.height,
            scan,
          );
          for (final mode in _blockModes) {
            final candidateTimer = Stopwatch()..start();
            final payload = _buildPayload(
              image,
              boundedLinear,
              mode,
              scan,
              dataWidth: bounds.width,
              dataHeight: bounds.height,
              backgroundColor: bg,
              bounds: bounds,
            );
            final candidate = _candidateFromPayload(
              payload,
              mode,
              scan,
              bounds: bounds,
              backgroundColor: bg,
              backgroundRank: background.rank,
            );
            candidateTimer.stop();
            _logCandidateDebug(
              compressionLevel: compressionLevel,
              label: 'v1 block-bounds scan=${scan.name} mode=${mode.name}',
              elapsed: candidateTimer.elapsed,
              candidate: candidate,
              outputTarget: outputTarget,
              currentBest: best,
            );
            candidates.add(candidate);
            if (_isBetterCandidate(candidate, best, outputTarget)) {
              best = candidate;
            }
          }
        }
      }

      final regionsTimer = Stopwatch()..start();
      final regionsPayload = _tryBuildRegionsPayload(
        image,
        bg,
        effectiveMaxRegions,
      );
      regionsTimer.stop();
      if (regionsPayload != null) {
        final candidate = _candidateFromPayload(
          regionsPayload.payload,
          ImageMode.regionsBg,
          ScanMode.h,
          backgroundColor: bg,
          backgroundRank: background.rank,
          regionCount: regionsPayload.regionCount,
        );
        _logCandidateDebug(
          compressionLevel: compressionLevel,
          label: 'v1 regions',
          elapsed: regionsTimer.elapsed,
          candidate: candidate,
          outputTarget: outputTarget,
          currentBest: best,
        );
        candidates.add(candidate);
        if (_isBetterCandidate(candidate, best, outputTarget)) {
          best = candidate;
        }
      }
    }

    final result = best!;
    return MCOImageEncodeDiagnostics(
      result: result,
      candidates: List.unmodifiable(candidates),
      compressionLevel: compressionLevel,
    );
  }

  MCOImageEncodeDiagnostics _debugEncodeV2(
    MCOImage image, {
    int? backgroundColor,
    List<MCOImageBackgroundCandidate>? backgroundCandidates,
    List<ScanMode>? scanModes,
    bool includeNonScanCandidates = true,
    int maxRegions = _defaultMaxRegions,
    MCOImageOutputTarget outputTarget = MCOImageOutputTarget.text,
    required int compressionLevel,
  }) {
    final preferredBackgroundColor = backgroundColor ?? image.transparentColor;
    final useHighCompressionExtras =
        compressionLevel != compressionLevelNormal;
    final useExtremeCompressionExtras =
        compressionLevel == compressionLevelExtreme;
    final effectiveBackgroundCandidates = backgroundCandidates == null
        ? (image.paletteProfile.isDynamic
              ? _dynamicBackgroundCandidates(
                  image,
                  preferredBackgroundColor,
                  exhaustiveSmallImage: useHighCompressionExtras,
                )
              : _backgroundCandidates(
                  image,
                  preferredBackgroundColor,
                  exhaustiveSmallImage: useHighCompressionExtras,
                ))
        : _backgroundCandidatesFromPublic(backgroundCandidates);
    final List<DynamicPaletteReferenceEncoding?> referenceEncodings =
        image.paletteProfile.isDynamic
        ? _dynamicReferenceEncodings(image.paletteProfile)
        : const <DynamicPaletteReferenceEncoding?>[null];
    final blockModes = image.paletteProfile.isDynamic
        ? _dynamicBlockModes
        : _v2BlockModes;
    final effectiveScanModes = scanModes ?? ScanMode.values;
    final candidates = <EncodedMCOImage>[];
    final optimalLzCache = <String, List<_LzPixelToken>?>{};
    EncodedMCOImage? best;

    for (final background in effectiveBackgroundCandidates) {
      final bg = background.color;
      final bounds = _findBounds(image.pixels, image.width, image.height, bg);
      if (includeNonScanCandidates) {
        for (final referenceEncoding in referenceEncodings) {
        final solidBgTimer = Stopwatch()..start();
        final solidBackgroundPayload = _tryBuildV2SolidBackgroundPayload(
          image,
          bg,
          referenceEncoding,
        );
        solidBgTimer.stop();
        if (solidBackgroundPayload != null) {
          final candidate = _candidateFromPayload(
            solidBackgroundPayload.payload,
            ImageMode.rawGlobal,
            ScanMode.h,
            backgroundColor: bg,
            transparentColor: image.transparentColor,
            backgroundRank: background.rank,
            codecVersion: _v2EncodeVersion,
            dynamicReferenceEncoding: referenceEncoding,
            localPaletteSize: 1,
            bitsPerLocalPixel: 0,
            paletteKind: image.paletteProfile.isDynamic
                ? 'dynamic'
                : 'fixed',
            container: 'solid-bg',
          );
          _logCandidateDebug(
            compressionLevel: compressionLevel,
            label: 'v2 solid-bg ref=${_referenceEncodingLabel(referenceEncoding)}',
            elapsed: solidBgTimer.elapsed,
            candidate: candidate,
            outputTarget: outputTarget,
            currentBest: best,
          );
          candidates.add(candidate);
          if (_isBetterCandidate(candidate, best, outputTarget)) {
            best = candidate;
          }
        }
        final regionsTimer = Stopwatch()..start();
        final regionsPayloads = _tryBuildV2RegionsPayloads(
          image,
          bg,
          referenceEncoding,
          maxRegions,
          includeExtendedFixedBlocks: useHighCompressionExtras,
          useExtremeSearch:
              useExtremeCompressionExtras &&
              background.rank <= _maxExtremeRegionBackgroundRank,
        );
        regionsTimer.stop();
        for (final regionsPayload in regionsPayloads) {
          final candidate = _candidateFromPayload(
            regionsPayload.payload,
            ImageMode.regionsBg,
            ScanMode.h,
            backgroundColor: bg,
            transparentColor: image.transparentColor,
            backgroundRank: background.rank,
            regionCount: regionsPayload.regionCount,
            codecVersion: _v2EncodeVersion,
            dynamicReferenceEncoding: referenceEncoding,
            localPaletteSize: regionsPayload.localPaletteSize,
            usedBankCount: regionsPayload.usedBankCount,
            bitsPerLocalPixel: regionsPayload.bitsPerLocalPixel,
            paletteKind: image.paletteProfile.isDynamic ? 'dynamic' : 'fixed',
            container: regionsPayload.diagnosticContainer ?? 'regions',
          );
          _logCandidateDebug(
            compressionLevel: compressionLevel,
            label:
                "v2 regions ref=${_referenceEncodingLabel(referenceEncoding)} "
                "variant=${regionsPayload.diagnosticContainer ?? 'regions'} "
                "regions=${regionsPayload.regionCount}",
            elapsed: regionsTimer.elapsed,
            candidate: candidate,
            outputTarget: outputTarget,
            currentBest: best,
          );
          candidates.add(candidate);
          if (_isBetterCandidate(candidate, best, outputTarget)) {
            best = candidate;
          }
        }

        final solidRectsTimer = Stopwatch()..start();
        final solidRectsPayload = _tryBuildV2SolidRectsPayload(
          image,
          bg,
          referenceEncoding,
        );
        solidRectsTimer.stop();
        if (solidRectsPayload != null) {
          final candidate = _candidateFromPayload(
            solidRectsPayload.payload,
            ImageMode.extended,
            ScanMode.h,
            backgroundColor: bg,
            transparentColor: image.transparentColor,
            backgroundRank: background.rank,
            codecVersion: _v2EncodeVersion,
            dynamicReferenceEncoding: referenceEncoding,
            localPaletteSize: solidRectsPayload.localPaletteSize,
            usedBankCount: solidRectsPayload.usedBankCount,
            bitsPerLocalPixel: solidRectsPayload.bitsPerLocalPixel,
            paletteKind: image.paletteProfile.isDynamic ? 'dynamic' : 'fixed',
            container: 'solid-rects',
          );
          _logCandidateDebug(
            compressionLevel: compressionLevel,
            label:
                'v2 solid-rects ref=${_referenceEncodingLabel(referenceEncoding)}',
            elapsed: solidRectsTimer.elapsed,
            candidate: candidate,
            outputTarget: outputTarget,
            currentBest: best,
          );
          candidates.add(candidate);
          if (_isBetterCandidate(candidate, best, outputTarget)) {
            best = candidate;
          }
        }

        final quadtreeTimer = Stopwatch()..start();
        final quadtreePayload = _tryBuildV2QuadtreePayload(
          image,
          image.pixels,
          image.width,
          image.height,
          bg,
          referenceEncoding,
        );
        quadtreeTimer.stop();
        if (quadtreePayload != null) {
          final candidate = _candidateFromPayload(
            quadtreePayload.payload,
            ImageMode.extended,
            ScanMode.h,
            backgroundColor: bg,
            transparentColor: image.transparentColor,
            backgroundRank: background.rank,
            codecVersion: _v2EncodeVersion,
            dynamicReferenceEncoding: referenceEncoding,
            localPaletteSize: quadtreePayload.localPaletteSize,
            usedBankCount: quadtreePayload.usedBankCount,
            bitsPerLocalPixel: quadtreePayload.bitsPerLocalPixel,
            paletteKind: image.paletteProfile.isDynamic ? 'dynamic' : 'fixed',
            container: 'quadtree',
          );
          _logCandidateDebug(
            compressionLevel: compressionLevel,
            label: 'v2 quadtree ref=${_referenceEncodingLabel(referenceEncoding)}',
            elapsed: quadtreeTimer.elapsed,
            candidate: candidate,
            outputTarget: outputTarget,
            currentBest: best,
          );
          candidates.add(candidate);
          if (_isBetterCandidate(candidate, best, outputTarget)) {
            best = candidate;
          }
        }

        if (bounds.area < image.width * image.height) {
          final cropped = _cropPixels(image.pixels, image.width, bounds);
          final boundedQuadtreeTimer = Stopwatch()..start();
          final boundedQuadtreePayload = _tryBuildV2QuadtreePayload(
            image,
            cropped,
            bounds.width,
            bounds.height,
            bg,
            referenceEncoding,
            bounds: bounds,
          );
          boundedQuadtreeTimer.stop();
          if (boundedQuadtreePayload != null) {
            final candidate = _candidateFromPayload(
              boundedQuadtreePayload.payload,
              ImageMode.extended,
              ScanMode.h,
              bounds: bounds,
              backgroundColor: bg,
              transparentColor: image.transparentColor,
              backgroundRank: background.rank,
              codecVersion: _v2EncodeVersion,
              dynamicReferenceEncoding: referenceEncoding,
              localPaletteSize: boundedQuadtreePayload.localPaletteSize,
              usedBankCount: boundedQuadtreePayload.usedBankCount,
              bitsPerLocalPixel: boundedQuadtreePayload.bitsPerLocalPixel,
              paletteKind: image.paletteProfile.isDynamic
                  ? 'dynamic'
                  : 'fixed',
              container: 'quadtree-bounds',
            );
            _logCandidateDebug(
              compressionLevel: compressionLevel,
              label:
                  'v2 quadtree-bounds ref=${_referenceEncodingLabel(referenceEncoding)}',
              elapsed: boundedQuadtreeTimer.elapsed,
              candidate: candidate,
              outputTarget: outputTarget,
              currentBest: best,
            );
            candidates.add(candidate);
            if (_isBetterCandidate(candidate, best, outputTarget)) {
              best = candidate;
            }
          }
        }
      }
      }
      for (final scan in effectiveScanModes) {
        final linear = _toScanOrder(
          image.pixels,
          image.width,
          image.height,
          scan,
        );
        for (final mode in blockModes) {
          for (final referenceEncoding in referenceEncodings) {
            final blockTimer = Stopwatch()..start();
            final payload = _tryBuildV2Payload(
              image,
              linear,
              mode,
              scan,
              referenceEncoding,
              dataWidth: image.width,
              dataHeight: image.height,
              backgroundColor: bg,
            );
            blockTimer.stop();
            if (payload == null) continue;
            final candidate = _candidateFromPayload(
              payload.payload,
              mode,
              scan,
              backgroundColor: bg,
              transparentColor: image.transparentColor,
              backgroundRank: background.rank,
              codecVersion: _v2EncodeVersion,
              dynamicReferenceEncoding: referenceEncoding,
              localPaletteSize: payload.localPaletteSize,
              usedBankCount: payload.usedBankCount,
              bitsPerLocalPixel: payload.bitsPerLocalPixel,
              paletteKind: image.paletteProfile.isDynamic ? 'dynamic' : 'fixed',
              container: 'block',
            );
            _logCandidateDebug(
              compressionLevel: compressionLevel,
              label:
                  'v2 block scan=${scan.name} mode=${mode.name} '
                  'ref=${_referenceEncodingLabel(referenceEncoding)}',
              elapsed: blockTimer.elapsed,
              candidate: candidate,
              outputTarget: outputTarget,
              currentBest: best,
            );
            candidates.add(candidate);
            if (_isBetterCandidate(candidate, best, outputTarget)) {
              best = candidate;
            }
          }
        }

        for (final referenceEncoding in referenceEncodings) {
          final compactRleTimer = Stopwatch()..start();
          final payload = _tryBuildV2CompactRlePayload(
            image,
            linear,
            scan,
            referenceEncoding,
            dataWidth: image.width,
            dataHeight: image.height,
            backgroundColor: bg,
          );
          compactRleTimer.stop();
          if (payload != null) {
            final candidate = _candidateFromPayload(
              payload.payload,
              ImageMode.extended,
              scan,
              backgroundColor: bg,
              transparentColor: image.transparentColor,
              backgroundRank: background.rank,
              codecVersion: _v2EncodeVersion,
              dynamicReferenceEncoding: referenceEncoding,
              localPaletteSize: payload.localPaletteSize,
              usedBankCount: payload.usedBankCount,
              bitsPerLocalPixel: payload.bitsPerLocalPixel,
              paletteKind: image.paletteProfile.isDynamic
                  ? 'dynamic'
                  : 'fixed',
              container: 'compact-rle',
            );
            _logCandidateDebug(
              compressionLevel: compressionLevel,
              label:
                  'v2 compact-rle scan=${scan.name} '
                  'ref=${_referenceEncodingLabel(referenceEncoding)}',
              elapsed: compactRleTimer.elapsed,
              candidate: candidate,
              outputTarget: outputTarget,
              currentBest: best,
            );
            candidates.add(candidate);
            if (_isBetterCandidate(candidate, best, outputTarget)) {
              best = candidate;
            }
          }

          final sparseTimer = Stopwatch()..start();
          final sparsePayload = _tryBuildV2CompactSparsePayload(
            image,
            linear,
            scan,
            referenceEncoding,
            dataWidth: image.width,
            dataHeight: image.height,
            backgroundColor: bg,
          );
          sparseTimer.stop();
          if (sparsePayload != null) {
            final sparseCandidate = _candidateFromPayload(
              sparsePayload.payload,
              ImageMode.extended,
              scan,
              backgroundColor: bg,
              transparentColor: image.transparentColor,
              backgroundRank: background.rank,
              codecVersion: _v2EncodeVersion,
              dynamicReferenceEncoding: referenceEncoding,
              localPaletteSize: sparsePayload.localPaletteSize,
              usedBankCount: sparsePayload.usedBankCount,
              bitsPerLocalPixel: sparsePayload.bitsPerLocalPixel,
              paletteKind: image.paletteProfile.isDynamic
                  ? 'dynamic'
                  : 'fixed',
              container: 'compact-sparse',
            );
            _logCandidateDebug(
              compressionLevel: compressionLevel,
              label:
                  'v2 compact-sparse scan=${scan.name} '
                  'ref=${_referenceEncodingLabel(referenceEncoding)}',
              elapsed: sparseTimer.elapsed,
              candidate: sparseCandidate,
              outputTarget: outputTarget,
              currentBest: best,
            );
            candidates.add(sparseCandidate);
            if (_isBetterCandidate(sparseCandidate, best, outputTarget)) {
              best = sparseCandidate;
            }
          }

          for (final lzVariant in const [
            (optimal: false, container: 'lz-pixels'),
            (optimal: true, container: 'lz-pixels-optimal'),
          ]) {
            final lzTimer = Stopwatch()..start();
            final lzPayload = _tryBuildV2LzPixelsPayload(
              image,
              linear,
              scan,
              referenceEncoding,
              dataWidth: image.width,
              dataHeight: image.height,
              backgroundColor: bg,
              optimizeParsing: lzVariant.optimal,
              optimalCache: optimalLzCache,
            );
            lzTimer.stop();
            if (lzPayload != null) {
              final lzCandidate = _candidateFromPayload(
                lzPayload.payload,
                ImageMode.extended,
                scan,
                backgroundColor: bg,
                transparentColor: image.transparentColor,
                backgroundRank: background.rank,
                codecVersion: _v2EncodeVersion,
                dynamicReferenceEncoding: referenceEncoding,
                localPaletteSize: lzPayload.localPaletteSize,
                usedBankCount: lzPayload.usedBankCount,
                bitsPerLocalPixel: lzPayload.bitsPerLocalPixel,
                paletteKind: image.paletteProfile.isDynamic
                    ? 'dynamic'
                    : 'fixed',
                container: lzVariant.container,
              );
              _logCandidateDebug(
                compressionLevel: compressionLevel,
                label:
                    'v2 ${lzVariant.container} scan=${scan.name} '
                    'ref=${_referenceEncodingLabel(referenceEncoding)}',
                elapsed: lzTimer.elapsed,
                candidate: lzCandidate,
                outputTarget: outputTarget,
                currentBest: best,
              );
              candidates.add(lzCandidate);
              if (_isBetterCandidate(lzCandidate, best, outputTarget)) {
                best = lzCandidate;
              }
            }
          }

          final bitplanesTimer = Stopwatch()..start();
          final bitplanesPayload = _tryBuildV2BitplanesPayload(
            image,
            linear,
            scan,
            referenceEncoding,
            dataWidth: image.width,
            dataHeight: image.height,
            backgroundColor: bg,
          );
          bitplanesTimer.stop();
          if (bitplanesPayload != null) {
            final bitplanesCandidate = _candidateFromPayload(
              bitplanesPayload.payload,
              ImageMode.extended,
              scan,
              backgroundColor: bg,
              transparentColor: image.transparentColor,
              backgroundRank: background.rank,
              codecVersion: _v2EncodeVersion,
              dynamicReferenceEncoding: referenceEncoding,
              localPaletteSize: bitplanesPayload.localPaletteSize,
              usedBankCount: bitplanesPayload.usedBankCount,
              bitsPerLocalPixel: bitplanesPayload.bitsPerLocalPixel,
              paletteKind: image.paletteProfile.isDynamic
                  ? 'dynamic'
                  : 'fixed',
              container: 'bitplanes',
            );
            _logCandidateDebug(
              compressionLevel: compressionLevel,
              label:
                  'v2 bitplanes scan=${scan.name} '
                  'ref=${_referenceEncodingLabel(referenceEncoding)}',
              elapsed: bitplanesTimer.elapsed,
              candidate: bitplanesCandidate,
              outputTarget: outputTarget,
              currentBest: best,
            );
            candidates.add(bitplanesCandidate);
            if (_isBetterCandidate(bitplanesCandidate, best, outputTarget)) {
              best = bitplanesCandidate;
            }
          }

          for (final adaptiveVariant in <({
            bool directGrayscale,
            bool directDynamicProfile,
            _AdaptivePaletteOrder paletteOrder,
            String container,
          })>[
            (
              directGrayscale: false,
              directDynamicProfile: false,
              paletteOrder: _AdaptivePaletteOrder.frequency,
              container: 'adaptive-bitplanes',
            ),
            (
              directGrayscale: false,
              directDynamicProfile: false,
              paletteOrder: _AdaptivePaletteOrder.bitplaneOptimized,
              container: 'adaptive-bitplanes-optimized',
            ),
            if (_supportsAlternativeAdaptivePaletteOrders(
              image.paletteProfile,
              referenceEncoding,
            ))
              (
                directGrayscale: false,
                directDynamicProfile: false,
                paletteOrder: _AdaptivePaletteOrder.profileId,
                container: 'adaptive-bitplanes-profile-order',
              ),
            if (_supportsAlternativeAdaptivePaletteOrders(
              image.paletteProfile,
              referenceEncoding,
            ))
              (
                directGrayscale: false,
                directDynamicProfile: false,
                paletteOrder: _AdaptivePaletteOrder.rgbProximity,
                container: 'adaptive-bitplanes-rgb-order',
              ),
            if (_supportsAlternativeAdaptivePaletteOrders(
              image.paletteProfile,
              referenceEncoding,
            ))
              (
                directGrayscale: false,
                directDynamicProfile: false,
                paletteOrder: _AdaptivePaletteOrder.transitionFrequency,
                container: 'adaptive-bitplanes-transition-order',
              ),
            if (_supportsAlternativeAdaptivePaletteOrders(
              image.paletteProfile,
              referenceEncoding,
            ))
              (
                directGrayscale: false,
                directDynamicProfile: false,
                paletteOrder: _AdaptivePaletteOrder.multiStartOptimized,
                container: 'adaptive-bitplanes-multistart',
              ),
            if (_isGrayscaleProfile(image.paletteProfile))
              (
                directGrayscale: true,
                directDynamicProfile: false,
                paletteOrder: _AdaptivePaletteOrder.frequency,
                container: 'direct-grayscale-bitplanes',
              ),
            if (image.paletteProfile.isDynamic &&
                referenceEncoding == DynamicPaletteReferenceEncoding.flat)
              (
                directGrayscale: false,
                directDynamicProfile: true,
                paletteOrder: _AdaptivePaletteOrder.frequency,
                container: 'direct-dynamic-bitplanes',
              ),
          ]) {
            final adaptiveTimer = Stopwatch()..start();
            final adaptivePayload = _tryBuildV2AdaptiveBitplanesPayload(
              image,
              linear,
              scan,
              referenceEncoding,
              dataWidth: image.width,
              dataHeight: image.height,
              backgroundColor: bg,
              directGrayscale: adaptiveVariant.directGrayscale,
              directDynamicProfile: adaptiveVariant.directDynamicProfile,
              paletteOrder: adaptiveVariant.paletteOrder,
              allowLargeMultiStart: useHighCompressionExtras,
            );
            adaptiveTimer.stop();
            if (adaptivePayload == null) continue;
            final adaptiveCandidate = _candidateFromPayload(
              adaptivePayload.payload,
              ImageMode.extended,
              scan,
              backgroundColor: bg,
              transparentColor: image.transparentColor,
              backgroundRank: background.rank,
              codecVersion: _v2EncodeVersion,
              dynamicReferenceEncoding: referenceEncoding,
              localPaletteSize: adaptivePayload.localPaletteSize,
              usedBankCount: adaptivePayload.usedBankCount,
              bitsPerLocalPixel: adaptivePayload.bitsPerLocalPixel,
              paletteKind: image.paletteProfile.isDynamic
                  ? 'dynamic'
                  : 'fixed',
              container: adaptiveVariant.container,
            );
            _logCandidateDebug(
              compressionLevel: compressionLevel,
              label:
                  'v2 ${adaptiveVariant.container} scan=${scan.name} '
                  'ref=${_referenceEncodingLabel(referenceEncoding)} '
                  'order=${adaptiveVariant.paletteOrder.name}',
              elapsed: adaptiveTimer.elapsed,
              candidate: adaptiveCandidate,
              outputTarget: outputTarget,
              currentBest: best,
            );
            candidates.add(adaptiveCandidate);
            if (_isBetterCandidate(adaptiveCandidate, best, outputTarget)) {
              best = adaptiveCandidate;
            }
          }

          for (final rowDeltaVariant in <({
            bool directGrayscale,
            _CompactRowDeltaPaletteOrder paletteOrder,
            String container,
          })>[
            (
              directGrayscale: false,
              paletteOrder: _CompactRowDeltaPaletteOrder.frequency,
              container: 'compact-row-delta',
            ),
            if (_supportsTransitionOptimizedRowDelta(
              image.paletteProfile,
              referenceEncoding,
            ))
              (
                directGrayscale: false,
                paletteOrder: _CompactRowDeltaPaletteOrder.transitionFrequency,
                container: 'compact-row-delta-palette-optimized',
              ),
            if (_isGrayscaleProfile(image.paletteProfile))
              (
                directGrayscale: true,
                paletteOrder: _CompactRowDeltaPaletteOrder.frequency,
                container: 'grayscale-row-delta',
              ),
          ]) {
            final rowDeltaTimer = Stopwatch()..start();
            final rowDeltaPayload = _tryBuildV2CompactRowDeltaPayload(
              image,
              linear,
              scan,
              referenceEncoding,
              dataWidth: image.width,
              dataHeight: image.height,
              backgroundColor: bg,
              directGrayscale: rowDeltaVariant.directGrayscale,
              paletteOrder: rowDeltaVariant.paletteOrder,
            );
            rowDeltaTimer.stop();
            if (rowDeltaPayload == null) continue;
            final rowDeltaCandidate = _candidateFromPayload(
              rowDeltaPayload.payload,
              ImageMode.extended,
              scan,
              backgroundColor: bg,
              transparentColor: image.transparentColor,
              backgroundRank: background.rank,
              codecVersion: _v2EncodeVersion,
              dynamicReferenceEncoding: referenceEncoding,
              localPaletteSize: rowDeltaPayload.localPaletteSize,
              usedBankCount: rowDeltaPayload.usedBankCount,
              bitsPerLocalPixel: rowDeltaPayload.bitsPerLocalPixel,
              paletteKind: image.paletteProfile.isDynamic
                  ? 'dynamic'
                  : 'fixed',
              container: rowDeltaVariant.container,
            );
            _logCandidateDebug(
              compressionLevel: compressionLevel,
              label:
                  'v2 ${rowDeltaVariant.container} scan=${scan.name} '
                  'ref=${_referenceEncodingLabel(referenceEncoding)} '
                  'order=${rowDeltaVariant.paletteOrder.name}',
              elapsed: rowDeltaTimer.elapsed,
              candidate: rowDeltaCandidate,
              outputTarget: outputTarget,
              currentBest: best,
            );
            candidates.add(rowDeltaCandidate);
            if (_isBetterCandidate(rowDeltaCandidate, best, outputTarget)) {
              best = rowDeltaCandidate;
            }
          }
        }

        if (bounds.area < image.width * image.height) {
          final cropped = _cropPixels(image.pixels, image.width, bounds);
          final boundedLinear = _toScanOrder(
            cropped,
            bounds.width,
            bounds.height,
            scan,
          );
          for (final mode in blockModes) {
            for (final referenceEncoding in referenceEncodings) {
              final boundedBlockTimer = Stopwatch()..start();
              final payload = _tryBuildV2Payload(
                image,
                boundedLinear,
                mode,
                scan,
                referenceEncoding,
                dataWidth: bounds.width,
                dataHeight: bounds.height,
                backgroundColor: bg,
                bounds: bounds,
              );
              boundedBlockTimer.stop();
              if (payload == null) continue;
              final candidate = _candidateFromPayload(
                payload.payload,
                mode,
                scan,
                bounds: bounds,
                backgroundColor: bg,
                backgroundRank: background.rank,
                codecVersion: _v2EncodeVersion,
                dynamicReferenceEncoding: referenceEncoding,
                localPaletteSize: payload.localPaletteSize,
                usedBankCount: payload.usedBankCount,
                bitsPerLocalPixel: payload.bitsPerLocalPixel,
                paletteKind: image.paletteProfile.isDynamic
                    ? 'dynamic'
                    : 'fixed',
                container: 'block',
              );
              _logCandidateDebug(
                compressionLevel: compressionLevel,
                label:
                    'v2 block-bounds scan=${scan.name} mode=${mode.name} '
                    'ref=${_referenceEncodingLabel(referenceEncoding)}',
                elapsed: boundedBlockTimer.elapsed,
                candidate: candidate,
                outputTarget: outputTarget,
                currentBest: best,
              );
              candidates.add(candidate);
              if (_isBetterCandidate(candidate, best, outputTarget)) {
                best = candidate;
              }

              final compactBoundsTimer = Stopwatch()..start();
              final compactPayload = _tryBuildV2CompactBoundsPayload(
                image,
                boundedLinear,
                mode,
                scan,
                referenceEncoding,
                bounds: bounds,
                backgroundColor: bg,
              );
              compactBoundsTimer.stop();
              if (compactPayload != null) {
                final compactCandidate = _candidateFromPayload(
                  compactPayload.payload,
                  ImageMode.extended,
                  scan,
                  bounds: bounds,
                  backgroundColor: bg,
                  transparentColor: image.transparentColor,
                  backgroundRank: background.rank,
                  codecVersion: _v2EncodeVersion,
                  dynamicReferenceEncoding: referenceEncoding,
                  localPaletteSize: compactPayload.localPaletteSize,
                  usedBankCount: compactPayload.usedBankCount,
                  bitsPerLocalPixel: compactPayload.bitsPerLocalPixel,
                  paletteKind: image.paletteProfile.isDynamic
                      ? 'dynamic'
                      : 'fixed',
                  container: 'compact-bounds',
                );
                _logCandidateDebug(
                  compressionLevel: compressionLevel,
                  label:
                      'v2 compact-bounds scan=${scan.name} mode=${mode.name} '
                      'ref=${_referenceEncodingLabel(referenceEncoding)}',
                  elapsed: compactBoundsTimer.elapsed,
                  candidate: compactCandidate,
                  outputTarget: outputTarget,
                  currentBest: best,
                );
                candidates.add(compactCandidate);
                if (_isBetterCandidate(
                  compactCandidate,
                  best,
                  outputTarget,
                )) {
                  best = compactCandidate;
                }
              }
            }
          }

          for (final referenceEncoding in referenceEncodings) {
            final boundedRleTimer = Stopwatch()..start();
            final payload = _tryBuildV2CompactRlePayload(
              image,
              boundedLinear,
              scan,
              referenceEncoding,
              dataWidth: bounds.width,
              dataHeight: bounds.height,
              backgroundColor: bg,
              bounds: bounds,
            );
            boundedRleTimer.stop();
            if (payload != null) {
              final candidate = _candidateFromPayload(
                payload.payload,
                ImageMode.extended,
                scan,
                bounds: bounds,
                backgroundColor: bg,
                transparentColor: image.transparentColor,
                backgroundRank: background.rank,
                codecVersion: _v2EncodeVersion,
                dynamicReferenceEncoding: referenceEncoding,
                localPaletteSize: payload.localPaletteSize,
                usedBankCount: payload.usedBankCount,
                bitsPerLocalPixel: payload.bitsPerLocalPixel,
                paletteKind: image.paletteProfile.isDynamic
                    ? 'dynamic'
                    : 'fixed',
                container: 'compact-rle-bounds',
              );
              _logCandidateDebug(
                compressionLevel: compressionLevel,
                label:
                    'v2 compact-rle-bounds scan=${scan.name} '
                    'ref=${_referenceEncodingLabel(referenceEncoding)}',
                elapsed: boundedRleTimer.elapsed,
                candidate: candidate,
                outputTarget: outputTarget,
                currentBest: best,
              );
              candidates.add(candidate);
              if (_isBetterCandidate(candidate, best, outputTarget)) {
                best = candidate;
              }
            }

            final boundedSparseTimer = Stopwatch()..start();
            final sparsePayload = _tryBuildV2CompactSparsePayload(
              image,
              boundedLinear,
              scan,
              referenceEncoding,
              dataWidth: bounds.width,
              dataHeight: bounds.height,
              backgroundColor: bg,
              bounds: bounds,
            );
            boundedSparseTimer.stop();
            if (sparsePayload != null) {
              final sparseCandidate = _candidateFromPayload(
                sparsePayload.payload,
                ImageMode.extended,
                scan,
                bounds: bounds,
                backgroundColor: bg,
                transparentColor: image.transparentColor,
                backgroundRank: background.rank,
                codecVersion: _v2EncodeVersion,
                dynamicReferenceEncoding: referenceEncoding,
                localPaletteSize: sparsePayload.localPaletteSize,
                usedBankCount: sparsePayload.usedBankCount,
                bitsPerLocalPixel: sparsePayload.bitsPerLocalPixel,
                paletteKind: image.paletteProfile.isDynamic
                    ? 'dynamic'
                    : 'fixed',
                container: 'compact-sparse-bounds',
              );
              _logCandidateDebug(
                compressionLevel: compressionLevel,
                label:
                    'v2 compact-sparse-bounds scan=${scan.name} '
                    'ref=${_referenceEncodingLabel(referenceEncoding)}',
                elapsed: boundedSparseTimer.elapsed,
                candidate: sparseCandidate,
                outputTarget: outputTarget,
                currentBest: best,
              );
              candidates.add(sparseCandidate);
              if (_isBetterCandidate(sparseCandidate, best, outputTarget)) {
                best = sparseCandidate;
              }
            }

            for (final lzVariant in const [
              (optimal: false, container: 'lz-pixels-bounds'),
              (optimal: true, container: 'lz-pixels-optimal-bounds'),
            ]) {
              final boundedLzTimer = Stopwatch()..start();
              final lzPayload = _tryBuildV2LzPixelsPayload(
                image,
                boundedLinear,
                scan,
                referenceEncoding,
                dataWidth: bounds.width,
                dataHeight: bounds.height,
                backgroundColor: bg,
                bounds: bounds,
                optimizeParsing: lzVariant.optimal,
                optimalCache: optimalLzCache,
              );
              boundedLzTimer.stop();
              if (lzPayload != null) {
                final lzCandidate = _candidateFromPayload(
                  lzPayload.payload,
                  ImageMode.extended,
                  scan,
                  bounds: bounds,
                  backgroundColor: bg,
                  transparentColor: image.transparentColor,
                  backgroundRank: background.rank,
                  codecVersion: _v2EncodeVersion,
                  dynamicReferenceEncoding: referenceEncoding,
                  localPaletteSize: lzPayload.localPaletteSize,
                  usedBankCount: lzPayload.usedBankCount,
                  bitsPerLocalPixel: lzPayload.bitsPerLocalPixel,
                  paletteKind: image.paletteProfile.isDynamic
                      ? 'dynamic'
                      : 'fixed',
                  container: lzVariant.container,
                );
                _logCandidateDebug(
                  compressionLevel: compressionLevel,
                  label:
                      'v2 ${lzVariant.container} scan=${scan.name} '
                      'ref=${_referenceEncodingLabel(referenceEncoding)}',
                  elapsed: boundedLzTimer.elapsed,
                  candidate: lzCandidate,
                  outputTarget: outputTarget,
                  currentBest: best,
                );
                candidates.add(lzCandidate);
                if (_isBetterCandidate(lzCandidate, best, outputTarget)) {
                  best = lzCandidate;
                }
              }
            }

            final boundedBitplanesTimer = Stopwatch()..start();
            final bitplanesPayload = _tryBuildV2BitplanesPayload(
              image,
              boundedLinear,
              scan,
              referenceEncoding,
              dataWidth: bounds.width,
              dataHeight: bounds.height,
              backgroundColor: bg,
              bounds: bounds,
            );
            boundedBitplanesTimer.stop();
            if (bitplanesPayload != null) {
              final bitplanesCandidate = _candidateFromPayload(
                bitplanesPayload.payload,
                ImageMode.extended,
                scan,
                bounds: bounds,
                backgroundColor: bg,
                transparentColor: image.transparentColor,
                backgroundRank: background.rank,
                codecVersion: _v2EncodeVersion,
                dynamicReferenceEncoding: referenceEncoding,
                localPaletteSize: bitplanesPayload.localPaletteSize,
                usedBankCount: bitplanesPayload.usedBankCount,
                bitsPerLocalPixel: bitplanesPayload.bitsPerLocalPixel,
                paletteKind: image.paletteProfile.isDynamic
                    ? 'dynamic'
                    : 'fixed',
                container: 'bitplanes-bounds',
              );
              _logCandidateDebug(
                compressionLevel: compressionLevel,
                label:
                    'v2 bitplanes-bounds scan=${scan.name} '
                    'ref=${_referenceEncodingLabel(referenceEncoding)}',
                elapsed: boundedBitplanesTimer.elapsed,
                candidate: bitplanesCandidate,
                outputTarget: outputTarget,
                currentBest: best,
              );
              candidates.add(bitplanesCandidate);
              if (_isBetterCandidate(
                bitplanesCandidate,
                best,
                outputTarget,
              )) {
                best = bitplanesCandidate;
              }
            }

            for (final adaptiveVariant in <({
              bool directGrayscale,
              bool directDynamicProfile,
              _AdaptivePaletteOrder paletteOrder,
              String container,
            })>[
              (
                directGrayscale: false,
                directDynamicProfile: false,
                paletteOrder: _AdaptivePaletteOrder.frequency,
                container: 'adaptive-bitplanes-bounds',
              ),
              (
                directGrayscale: false,
                directDynamicProfile: false,
                paletteOrder: _AdaptivePaletteOrder.bitplaneOptimized,
                container: 'adaptive-bitplanes-optimized-bounds',
              ),
              if (_supportsAlternativeAdaptivePaletteOrders(
                image.paletteProfile,
                referenceEncoding,
              ))
                (
                  directGrayscale: false,
                  directDynamicProfile: false,
                  paletteOrder: _AdaptivePaletteOrder.profileId,
                  container: 'adaptive-bitplanes-profile-order-bounds',
                ),
              if (_supportsAlternativeAdaptivePaletteOrders(
                image.paletteProfile,
                referenceEncoding,
              ))
                (
                  directGrayscale: false,
                  directDynamicProfile: false,
                  paletteOrder: _AdaptivePaletteOrder.rgbProximity,
                  container: 'adaptive-bitplanes-rgb-order-bounds',
                ),
              if (_supportsAlternativeAdaptivePaletteOrders(
                image.paletteProfile,
                referenceEncoding,
              ))
                (
                  directGrayscale: false,
                  directDynamicProfile: false,
                  paletteOrder: _AdaptivePaletteOrder.transitionFrequency,
                  container: 'adaptive-bitplanes-transition-order-bounds',
                ),
              if (_supportsAlternativeAdaptivePaletteOrders(
                image.paletteProfile,
                referenceEncoding,
              ))
                (
                  directGrayscale: false,
                  directDynamicProfile: false,
                  paletteOrder: _AdaptivePaletteOrder.multiStartOptimized,
                  container: 'adaptive-bitplanes-multistart-bounds',
                ),
              if (_isGrayscaleProfile(image.paletteProfile))
                (
                  directGrayscale: true,
                  directDynamicProfile: false,
                  paletteOrder: _AdaptivePaletteOrder.frequency,
                  container: 'direct-grayscale-bitplanes-bounds',
                ),
              if (image.paletteProfile.isDynamic &&
                  referenceEncoding == DynamicPaletteReferenceEncoding.flat)
                (
                  directGrayscale: false,
                  directDynamicProfile: true,
                  paletteOrder: _AdaptivePaletteOrder.frequency,
                  container: 'direct-dynamic-bitplanes-bounds',
                ),
            ]) {
              final boundedAdaptiveTimer = Stopwatch()..start();
              final adaptivePayload = _tryBuildV2AdaptiveBitplanesPayload(
                image,
                boundedLinear,
                scan,
                referenceEncoding,
                dataWidth: bounds.width,
                dataHeight: bounds.height,
                backgroundColor: bg,
                bounds: bounds,
                directGrayscale: adaptiveVariant.directGrayscale,
                directDynamicProfile: adaptiveVariant.directDynamicProfile,
                paletteOrder: adaptiveVariant.paletteOrder,
                allowLargeMultiStart: useHighCompressionExtras,
              );
              boundedAdaptiveTimer.stop();
              if (adaptivePayload == null) continue;
              final adaptiveCandidate = _candidateFromPayload(
                adaptivePayload.payload,
                ImageMode.extended,
                scan,
                bounds: bounds,
                backgroundColor: bg,
                transparentColor: image.transparentColor,
                backgroundRank: background.rank,
                codecVersion: _v2EncodeVersion,
                dynamicReferenceEncoding: referenceEncoding,
                localPaletteSize: adaptivePayload.localPaletteSize,
                usedBankCount: adaptivePayload.usedBankCount,
                bitsPerLocalPixel: adaptivePayload.bitsPerLocalPixel,
                paletteKind: image.paletteProfile.isDynamic
                    ? 'dynamic'
                    : 'fixed',
                container: adaptiveVariant.container,
              );
              _logCandidateDebug(
                compressionLevel: compressionLevel,
                label:
                    'v2 ${adaptiveVariant.container} scan=${scan.name} '
                    'ref=${_referenceEncodingLabel(referenceEncoding)} '
                    'order=${adaptiveVariant.paletteOrder.name}',
                elapsed: boundedAdaptiveTimer.elapsed,
                candidate: adaptiveCandidate,
                outputTarget: outputTarget,
                currentBest: best,
              );
              candidates.add(adaptiveCandidate);
              if (_isBetterCandidate(adaptiveCandidate, best, outputTarget)) {
                best = adaptiveCandidate;
              }
            }

            for (final rowDeltaVariant in <({
              bool directGrayscale,
              _CompactRowDeltaPaletteOrder paletteOrder,
              String container,
            })>[
              (
                directGrayscale: false,
                paletteOrder: _CompactRowDeltaPaletteOrder.frequency,
                container: 'compact-row-delta-bounds',
              ),
              if (_supportsTransitionOptimizedRowDelta(
                image.paletteProfile,
                referenceEncoding,
              ))
                (
                  directGrayscale: false,
                  paletteOrder:
                      _CompactRowDeltaPaletteOrder.transitionFrequency,
                  container: 'compact-row-delta-palette-optimized-bounds',
                ),
              if (_isGrayscaleProfile(image.paletteProfile))
                (
                  directGrayscale: true,
                  paletteOrder: _CompactRowDeltaPaletteOrder.frequency,
                  container: 'grayscale-row-delta-bounds',
                ),
            ]) {
              final boundedRowDeltaTimer = Stopwatch()..start();
              final rowDeltaPayload = _tryBuildV2CompactRowDeltaPayload(
                image,
                boundedLinear,
                scan,
                referenceEncoding,
                dataWidth: bounds.width,
                dataHeight: bounds.height,
                backgroundColor: bg,
                bounds: bounds,
                directGrayscale: rowDeltaVariant.directGrayscale,
                paletteOrder: rowDeltaVariant.paletteOrder,
              );
              boundedRowDeltaTimer.stop();
              if (rowDeltaPayload == null) continue;
              final rowDeltaCandidate = _candidateFromPayload(
                rowDeltaPayload.payload,
                ImageMode.extended,
                scan,
                bounds: bounds,
                backgroundColor: bg,
                transparentColor: image.transparentColor,
                backgroundRank: background.rank,
                codecVersion: _v2EncodeVersion,
                dynamicReferenceEncoding: referenceEncoding,
                localPaletteSize: rowDeltaPayload.localPaletteSize,
                usedBankCount: rowDeltaPayload.usedBankCount,
                bitsPerLocalPixel: rowDeltaPayload.bitsPerLocalPixel,
                paletteKind: image.paletteProfile.isDynamic
                    ? 'dynamic'
                    : 'fixed',
                container: rowDeltaVariant.container,
              );
              _logCandidateDebug(
                compressionLevel: compressionLevel,
                label:
                    'v2 ${rowDeltaVariant.container} scan=${scan.name} '
                    'ref=${_referenceEncodingLabel(referenceEncoding)} '
                    'order=${rowDeltaVariant.paletteOrder.name}',
                elapsed: boundedRowDeltaTimer.elapsed,
                candidate: rowDeltaCandidate,
                outputTarget: outputTarget,
                currentBest: best,
              );
              candidates.add(rowDeltaCandidate);
              if (_isBetterCandidate(
                rowDeltaCandidate,
                best,
                outputTarget,
              )) {
                best = rowDeltaCandidate;
              }
            }
          }
        }
      }
    }

    if (best == null) {
      throw const MCOImageTooLargeException(
        'Image uses too many colors for local palette',
      );
    }
    return MCOImageEncodeDiagnostics(
      result: best,
      candidates: List.unmodifiable(candidates),
      compressionLevel: compressionLevel,
    );
  }

  _V2Payload? _tryBuildV2Payload(
    MCOImage image,
    List<int> linear,
    ImageMode mode,
    ScanMode scan,
    DynamicPaletteReferenceEncoding? referenceEncoding, {
    required int dataWidth,
    required int dataHeight,
    required int backgroundColor,
    _ImageBounds? bounds,
  }) {
    final expectedDataLength = dataWidth * dataHeight;
    if (linear.length != expectedDataLength) {
      throw MCOImageInvalidInputException(
        'linear.length must be $expectedDataLength, got ${linear.length}',
      );
    }
    if (image.paletteProfile.isDynamic && referenceEncoding == null) {
      throw const MCOImageInvalidInputException(
        'Dynamic v2 payload requires reference encoding',
      );
    }
    if (image.paletteProfile.isFixed && referenceEncoding != null) return null;

    final block = _tryBuildV2BlockBody(
      linear,
      image.paletteProfile,
      mode,
      referenceEncoding,
      rowLength: _rowLengthForScan(scan, dataWidth, dataHeight),
      backgroundColor: backgroundColor,
      writeSparseBackground: bounds == null,
    );
    if (block == null && !(bounds != null && bounds.area == 0)) return null;

    final writer = _BitWriter();
    _writeV2Header(
      writer,
      profile: image.paletteProfile,
      container: _containerBlock,
      mode: mode,
      scan: scan,
      boundsPresent: bounds != null,
      referenceEncoding: referenceEncoding,
      implicitWhiteBackground:
          (image.paletteProfile.isDynamic ||
              bounds != null ||
              mode == ImageMode.sparseBg ||
              mode == ImageMode.biColorMask) &&
          _isImplicitWhiteBackground(
            image.paletteProfile,
            backgroundColor,
          ),
      width: image.width,
      height: image.height,
      hasTransparentColor: image.transparentColor != null,
    );
    if (image.transparentColor != null) {
      _writeV2ColorRef(writer, image.paletteProfile, image.transparentColor!);
    }

    if (bounds != null) {
      _writeV2BackgroundRef(writer, image.paletteProfile, backgroundColor);
      _writeV2Bounds(writer, bounds);
      if (bounds.area == 0) {
        return _V2Payload(
          writer.toBytes(),
          localPaletteSize: 0,
          bitsPerLocalPixel: 0,
        );
      }
    }

    writer.writeAlignedBytes(block!.payload);
    return _V2Payload(
      writer.toBytes(),
      localPaletteSize: block.localPaletteSize,
      usedBankCount: block.usedBankCount,
      bitsPerLocalPixel: block.bitsPerLocalPixel,
    );
  }

  _V2Payload? _tryBuildV2SolidBackgroundPayload(
    MCOImage image,
    int backgroundColor,
    DynamicPaletteReferenceEncoding? referenceEncoding,
  ) {
    if (image.pixels.any((color) => color != backgroundColor)) return null;
    if (image.paletteProfile.isDynamic && referenceEncoding == null) {
      return null;
    }
    if (image.paletteProfile.isFixed && referenceEncoding != null) return null;

    final implicitWhite = _isImplicitWhiteBackground(
      image.paletteProfile,
      backgroundColor,
    );
    final writer = _BitWriter();
    _writeV2Header(
      writer,
      profile: image.paletteProfile,
      container: _containerBlock,
      mode: ImageMode.rawGlobal,
      scan: image.paletteProfile.isFixed && implicitWhite
          ? ScanMode.v
          : ScanMode.h,
      boundsPresent: false,
      referenceEncoding: referenceEncoding,
      implicitWhiteBackground: implicitWhite,
      width: image.width,
      height: image.height,
      hasTransparentColor: image.transparentColor != null,
      solidBackground: true,
    );
    if (image.transparentColor != null) {
      _writeV2ColorRef(writer, image.paletteProfile, image.transparentColor!);
    }
    _writeV2BackgroundRef(writer, image.paletteProfile, backgroundColor);
    return _V2Payload(
      writer.toBytes(),
      localPaletteSize: 1,
      bitsPerLocalPixel: 0,
      diagnosticContainer: 'solid-bg',
    );
  }

  _V2Payload? _tryBuildV2CompactBoundsPayload(
    MCOImage image,
    List<int> linear,
    ImageMode innerMode,
    ScanMode scan,
    DynamicPaletteReferenceEncoding? referenceEncoding, {
    required _ImageBounds bounds,
    required int backgroundColor,
  }) {
    if (bounds.area == 0 ||
        innerMode == ImageMode.extended ||
        innerMode == ImageMode.regionsBg) {
      return null;
    }
    final block = _tryBuildV2BlockBody(
      linear,
      image.paletteProfile,
      innerMode,
      referenceEncoding,
      rowLength: _rowLengthForScan(scan, bounds.width, bounds.height),
      backgroundColor: backgroundColor,
      writeSparseBackground: false,
    );
    if (block == null) return null;

    final writer = _BitWriter();
    _writeV2Header(
      writer,
      profile: image.paletteProfile,
      container: _containerBlock,
      mode: ImageMode.extended,
      scan: scan,
      boundsPresent: true,
      referenceEncoding: referenceEncoding,
      implicitWhiteBackground: _isImplicitWhiteBackground(
        image.paletteProfile,
        backgroundColor,
      ),
      width: image.width,
      height: image.height,
      hasTransparentColor: image.transparentColor != null,
    );
    if (image.transparentColor != null) {
      _writeV2ColorRef(writer, image.paletteProfile, image.transparentColor!);
    }
    _writeV2BackgroundRef(writer, image.paletteProfile, backgroundColor);
    _writeV2CompactBounds(writer, bounds, image.width, image.height);
    writer
      ..alignToByte()
      ..writeBits(ExtendedImageMode.wrappedBlock.index, _extendedSubmodeBits)
      ..writeBits(_modeBits(innerMode), 3)
      ..writeAlignedBytes(block.payload);
    return _V2Payload(
      writer.toBytes(),
      localPaletteSize: block.localPaletteSize,
      usedBankCount: block.usedBankCount,
      bitsPerLocalPixel: block.bitsPerLocalPixel,
    );
  }

  _V2Payload? _tryBuildV2SolidRectsPayload(
    MCOImage image,
    int backgroundColor,
    DynamicPaletteReferenceEncoding? referenceEncoding,
  ) {
    if (image.paletteProfile.isDynamic && referenceEncoding == null) {
      return null;
    }
    if (image.paletteProfile.isFixed && referenceEncoding != null) return null;

    final variants = _solidRectVariants(
      image.pixels,
      image.width,
      image.height,
      backgroundColor,
      maxRects: 64,
    );
    _V2Payload? best;
    for (final rects in variants) {
      if (rects.isEmpty) continue;
      final writer = _BitWriter();
      _writeV2Header(
        writer,
        profile: image.paletteProfile,
        container: _containerBlock,
        mode: ImageMode.extended,
        scan: ScanMode.h,
        boundsPresent: false,
        referenceEncoding: referenceEncoding,
        implicitWhiteBackground: _isImplicitWhiteBackground(
          image.paletteProfile,
          backgroundColor,
        ),
        width: image.width,
        height: image.height,
        hasTransparentColor: image.transparentColor != null,
        unalignedExtendedBody: image.paletteProfile.isFixed,
      );
      if (image.transparentColor != null) {
        _writeV2ColorRef(writer, image.paletteProfile, image.transparentColor!);
      }
      if (image.paletteProfile.isDynamic) writer.alignToByte();
      writer.writeBits(
        ExtendedImageMode.solidRects.index,
        _extendedSubmodeBits,
      );
      _writeV2BackgroundRef(writer, image.paletteProfile, backgroundColor);

      final rectColors = rects.map((rect) => rect.color).toList();
      final int localPaletteSize;
      final int localBits;
      int? usedBankCount;
      Map<int, int> localIndexByColor;
      if (image.paletteProfile.isDynamic) {
        final profileColorIds = rectColors
            .map(
              (color) => _profileColorIdForGlobalIndex(
                image.paletteProfile,
                color,
              )!,
            )
            .toList();
        final backgroundId = _profileColorIdForGlobalIndex(
          image.paletteProfile,
          backgroundColor,
        )!;
        final localPalette = _buildDynamicLocalPalette(
          image.paletteProfile,
          profileColorIds,
          backgroundId,
          referenceEncoding!,
        );
        if (localPalette.isEmpty ||
            localPalette.length > _maxDynamicLocalPalette) {
          continue;
        }
        _writeDynamicLocalPalette(
          writer,
          image.paletteProfile,
          localPalette,
          referenceEncoding,
        );
        localPaletteSize = localPalette.length;
        localBits = _localBits(localPalette.length);
        localIndexByColor = {
          for (var i = 0; i < localPalette.length; i++)
            _globalIndexForProfileColorId(
              image.paletteProfile,
              localPalette[i],
            ): i,
        };
        usedBankCount =
            referenceEncoding == DynamicPaletteReferenceEncoding.banked8x64
            ? localPalette.map((color) => color >> 6).toSet().length
            : null;
      } else {
        final local = _buildLocalPalette(rectColors);
        if (local.colors.isEmpty) continue;
        final palette = _writeV2FixedLocalPalette(
          writer,
          local.colors,
          image.paletteProfile,
        );
        localPaletteSize = palette.length;
        localBits = _localBits(palette.length);
        localIndexByColor = _localIndexMap(palette);
      }

      writer.writeBitVarUint(rects.length);
      for (final rect in rects) {
        _writeV2CompactBounds(
          writer,
          rect.bounds,
          image.width,
          image.height,
        );
        writer.writeBits(localIndexByColor[rect.color]!, localBits);
      }
      final payload = _V2Payload(
        writer.toBytes(),
        localPaletteSize: localPaletteSize,
        usedBankCount: usedBankCount,
        bitsPerLocalPixel: localBits,
      );
      if (best == null || payload.payload.length < best.payload.length) {
        best = payload;
      }
    }
    return best;
  }

  _V2Payload? _tryBuildV2CompactRlePayload(
    MCOImage image,
    List<int> linear,
    ScanMode scan,
    DynamicPaletteReferenceEncoding? referenceEncoding, {
    required int dataWidth,
    required int dataHeight,
    required int backgroundColor,
    _ImageBounds? bounds,
  }) {
    if (linear.length != dataWidth * dataHeight) {
      throw const MCOImageInvalidInputException(
        'Invalid compact RLE pixel count',
      );
    }
    if (linear.isEmpty) return null;
    if (image.paletteProfile.isDynamic && referenceEncoding == null) {
      return null;
    }
    if (image.paletteProfile.isFixed && referenceEncoding != null) return null;

    final writer = _BitWriter();
    _writeV2Header(
      writer,
      profile: image.paletteProfile,
      container: _containerBlock,
      mode: ImageMode.extended,
      scan: scan,
      boundsPresent: bounds != null,
      referenceEncoding: referenceEncoding,
      implicitWhiteBackground: _isImplicitWhiteBackground(
        image.paletteProfile,
        backgroundColor,
      ),
      width: image.width,
      height: image.height,
      hasTransparentColor: image.transparentColor != null,
      unalignedExtendedBody: image.paletteProfile.isFixed,
    );
    if (image.transparentColor != null) {
      _writeV2ColorRef(writer, image.paletteProfile, image.transparentColor!);
    }
    if (bounds != null) {
      _writeV2BackgroundRef(writer, image.paletteProfile, backgroundColor);
      _writeV2CompactBounds(
        writer,
        bounds,
        image.width,
        image.height,
      );
    }
    if (image.paletteProfile.isDynamic) writer.alignToByte();
    writer.writeBits(ExtendedImageMode.compactRle.index, _extendedSubmodeBits);

    final int localPaletteSize;
    final int localBits;
    int? usedBankCount;
    Map<int, int> localIndexByColor;
    if (image.paletteProfile.isDynamic) {
      final profileColorIds = linear
          .map(
            (color) => _profileColorIdForGlobalIndex(
              image.paletteProfile,
              color,
            )!,
          )
          .toList();
      final backgroundId = _profileColorIdForGlobalIndex(
        image.paletteProfile,
        backgroundColor,
      )!;
      final localPalette = _buildDynamicLocalPalette(
        image.paletteProfile,
        profileColorIds,
        backgroundId,
        referenceEncoding!,
      );
      if (localPalette.isEmpty ||
          localPalette.length > _maxDynamicLocalPalette) {
        return null;
      }
      _writeDynamicLocalPalette(
        writer,
        image.paletteProfile,
        localPalette,
        referenceEncoding,
      );
      localPaletteSize = localPalette.length;
      localBits = _localBits(localPalette.length);
      localIndexByColor = {
        for (var i = 0; i < localPalette.length; i++)
          _globalIndexForProfileColorId(
            image.paletteProfile,
            localPalette[i],
          ): i,
      };
      usedBankCount =
          referenceEncoding == DynamicPaletteReferenceEncoding.banked8x64
          ? localPalette.map((color) => color >> 6).toSet().length
          : null;
    } else {
      final local = _buildLocalPalette(linear);
      if (local.colors.isEmpty) return null;
      final palette = _writeV2FixedLocalPalette(
        writer,
        local.colors,
        image.paletteProfile,
      );
      localPaletteSize = palette.length;
      localBits = _localBits(palette.length);
      localIndexByColor = _localIndexMap(palette);
    }

    for (final run in _buildRuns(linear)) {
      writer.writeBits(localIndexByColor[run.color]!, localBits);
      _writeCompactUint(writer, run.length - 1);
    }
    return _V2Payload(
      writer.toBytes(),
      localPaletteSize: localPaletteSize,
      usedBankCount: usedBankCount,
      bitsPerLocalPixel: localBits,
    );
  }

  _V2Payload? _tryBuildV2CompactSparsePayload(
    MCOImage image,
    List<int> linear,
    ScanMode scan,
    DynamicPaletteReferenceEncoding? referenceEncoding, {
    required int dataWidth,
    required int dataHeight,
    required int backgroundColor,
    _ImageBounds? bounds,
  }) {
    if (linear.length != dataWidth * dataHeight) {
      throw const MCOImageInvalidInputException(
        'Invalid compact sparse pixel count',
      );
    }
    if (linear.isEmpty || linear.every((pixel) => pixel == backgroundColor)) {
      return null;
    }
    if (image.paletteProfile.isDynamic && referenceEncoding == null) {
      return null;
    }
    if (image.paletteProfile.isFixed && referenceEncoding != null) return null;

    final segments = _buildSparseSegments(linear, backgroundColor);
    if (segments.isEmpty) return null;

    final writer = _BitWriter();
    _writeV2Header(
      writer,
      profile: image.paletteProfile,
      container: _containerBlock,
      mode: ImageMode.extended,
      scan: scan,
      boundsPresent: bounds != null,
      referenceEncoding: referenceEncoding,
      implicitWhiteBackground: _isImplicitWhiteBackground(
        image.paletteProfile,
        backgroundColor,
      ),
      width: image.width,
      height: image.height,
      hasTransparentColor: image.transparentColor != null,
      unalignedExtendedBody: image.paletteProfile.isFixed,
    );
    if (image.transparentColor != null) {
      _writeV2ColorRef(writer, image.paletteProfile, image.transparentColor!);
    }
    if (bounds != null) {
      _writeV2BackgroundRef(writer, image.paletteProfile, backgroundColor);
      _writeV2CompactBounds(writer, bounds, image.width, image.height);
    }
    if (image.paletteProfile.isDynamic) writer.alignToByte();
    writer.writeBits(
      ExtendedImageMode.compactSparse.index,
      _extendedSubmodeBits,
    );
    if (bounds == null) {
      _writeV2BackgroundRef(writer, image.paletteProfile, backgroundColor);
    }

    final int localPaletteSize;
    final int localBits;
    int? usedBankCount;
    Map<int, int> localIndexByColor;
    if (image.paletteProfile.isDynamic) {
      final backgroundId = _profileColorIdForGlobalIndex(
        image.paletteProfile,
        backgroundColor,
      )!;
      final profileColorIds = linear
          .where((color) => color != backgroundColor)
          .map(
            (color) => _profileColorIdForGlobalIndex(
              image.paletteProfile,
              color,
            )!,
          )
          .toList(growable: false);
      final localPalette = _buildDynamicLocalPalette(
        image.paletteProfile,
        profileColorIds,
        backgroundId,
        referenceEncoding!,
      );
      if (localPalette.isEmpty ||
          localPalette.length > _maxDynamicLocalPalette) {
        return null;
      }
      _writeDynamicLocalPalette(
        writer,
        image.paletteProfile,
        localPalette,
        referenceEncoding,
      );
      localPaletteSize = localPalette.length;
      localBits = _localBits(localPalette.length);
      localIndexByColor = {
        for (var i = 0; i < localPalette.length; i++)
          _globalIndexForProfileColorId(
            image.paletteProfile,
            localPalette[i],
          ): i,
      };
      usedBankCount =
          referenceEncoding == DynamicPaletteReferenceEncoding.banked8x64
          ? localPalette.map((color) => color >> 6).toSet().length
          : null;
    } else {
      final local = _buildLocalPalette(
        linear.where((color) => color != backgroundColor).toList(),
      );
      if (local.colors.isEmpty) return null;
      final palette = _writeV2FixedLocalPalette(
        writer,
        local.colors,
        image.paletteProfile,
      );
      localPaletteSize = palette.length;
      localBits = _localBits(palette.length);
      localIndexByColor = _localIndexMap(palette);
    }

    _writeCompactUint(writer, segments.length - 1);
    var pos = 0;
    for (final segment in segments) {
      _writeCompactUint(writer, segment.start - pos);
      writer.writeBits(localIndexByColor[segment.color]!, localBits);
      _writeCompactUint(writer, segment.length - 1);
      pos = segment.start + segment.length;
    }
    return _V2Payload(
      writer.toBytes(),
      localPaletteSize: localPaletteSize,
      usedBankCount: usedBankCount,
      bitsPerLocalPixel: localBits,
    );
  }

  _V2Payload? _tryBuildV2LzPixelsPayload(
    MCOImage image,
    List<int> linear,
    ScanMode scan,
    DynamicPaletteReferenceEncoding? referenceEncoding, {
    required int dataWidth,
    required int dataHeight,
    required int backgroundColor,
    required bool optimizeParsing,
    required Map<String, List<_LzPixelToken>?> optimalCache,
    _ImageBounds? bounds,
  }) {
    if (linear.length != dataWidth * dataHeight) {
      throw const MCOImageInvalidInputException('Invalid LZ pixel count');
    }
    if (linear.isEmpty) return null;
    if (image.paletteProfile.isDynamic && referenceEncoding == null) {
      return null;
    }
    if (image.paletteProfile.isFixed && referenceEncoding != null) return null;

    final writer = _BitWriter();
    _writeV2Header(
      writer,
      profile: image.paletteProfile,
      container: _containerBlock,
      mode: ImageMode.extended,
      scan: scan,
      boundsPresent: bounds != null,
      referenceEncoding: referenceEncoding,
      implicitWhiteBackground: _isImplicitWhiteBackground(
        image.paletteProfile,
        backgroundColor,
      ),
      width: image.width,
      height: image.height,
      hasTransparentColor: image.transparentColor != null,
      unalignedExtendedBody: image.paletteProfile.isFixed,
    );
    if (image.transparentColor != null) {
      _writeV2ColorRef(writer, image.paletteProfile, image.transparentColor!);
    }
    if (bounds != null) {
      _writeV2BackgroundRef(writer, image.paletteProfile, backgroundColor);
      _writeV2CompactBounds(writer, bounds, image.width, image.height);
    }
    if (image.paletteProfile.isDynamic) writer.alignToByte();
    writer.writeBits(ExtendedImageMode.lzPixels.index, _extendedSubmodeBits);

    final int localPaletteSize;
    final int localBits;
    int? usedBankCount;
    late final List<int> localPixels;
    if (image.paletteProfile.isDynamic) {
      final profileColorIds = linear
          .map(
            (color) => _profileColorIdForGlobalIndex(
              image.paletteProfile,
              color,
            )!,
          )
          .toList(growable: false);
      final backgroundId = _profileColorIdForGlobalIndex(
        image.paletteProfile,
        backgroundColor,
      )!;
      final localPalette = _buildDynamicLocalPalette(
        image.paletteProfile,
        profileColorIds,
        backgroundId,
        referenceEncoding!,
      );
      if (localPalette.isEmpty ||
          localPalette.length > _maxDynamicLocalPalette) {
        return null;
      }
      _writeDynamicLocalPalette(
        writer,
        image.paletteProfile,
        localPalette,
        referenceEncoding,
      );
      localPaletteSize = localPalette.length;
      localBits = _localBits(localPalette.length);
      final localIndexByProfileColorId = {
        for (var i = 0; i < localPalette.length; i++) localPalette[i]: i,
      };
      localPixels = profileColorIds
          .map((color) => localIndexByProfileColorId[color]!)
          .toList(growable: false);
      usedBankCount =
          referenceEncoding == DynamicPaletteReferenceEncoding.banked8x64
          ? localPalette.map((color) => color >> 6).toSet().length
          : null;
    } else {
      final local = _buildLocalPalette(linear);
      if (local.colors.isEmpty) return null;
      final palette = _writeV2FixedLocalPalette(
        writer,
        local.colors,
        image.paletteProfile,
      );
      localPaletteSize = palette.length;
      localBits = _localBits(palette.length);
      final localIndexByColor = _localIndexMap(palette);
      localPixels = linear
          .map((color) => localIndexByColor[color]!)
          .toList(growable: false);
    }

    final greedyTokens = _buildGreedyLzPixelTokens(localPixels, localBits);
    final List<_LzPixelToken> tokens;
    if (optimizeParsing) {
      if (localPixels.length > _maxOptimalLzPixels) return null;
      final cacheKey = _lzOptimizationCacheKey(localPixels, localBits);
      final optimalTokens = optimalCache.putIfAbsent(
        cacheKey,
        () => _buildOptimalLzPixelTokens(localPixels, localBits),
      );
      if (optimalTokens == null) return null;
      final optimalCost = _lzPixelTokensBitCost(optimalTokens, localBits);
      final greedyCost = _lzPixelTokensBitCost(greedyTokens, localBits);
      if (optimalCost > greedyCost ||
          (optimalCost == greedyCost &&
              _lzPixelTokensEqual(optimalTokens, greedyTokens))) {
        return null;
      }
      tokens = optimalTokens;
    } else {
      tokens = greedyTokens;
    }
    for (final token in tokens) {
      if (token.isMatch) {
        writer.writeBits(1, 1);
        _writeCompactUint(writer, token.distance - 1);
        _writeCompactUint(writer, token.length - _minLzMatchLength);
      } else {
        writer.writeBits(0, 1);
        _writeCompactUint(writer, token.literals.length - 1);
        for (final color in token.literals) {
          writer.writeBits(color, localBits);
        }
      }
    }
    return _V2Payload(
      writer.toBytes(),
      localPaletteSize: localPaletteSize,
      usedBankCount: usedBankCount,
      bitsPerLocalPixel: localBits,
    );
  }

  _V2Payload? _tryBuildV2QuadtreePayload(
    MCOImage image,
    List<int> pixels,
    int dataWidth,
    int dataHeight,
    int backgroundColor,
    DynamicPaletteReferenceEncoding? referenceEncoding, {
    _ImageBounds? bounds,
  }) {
    if (pixels.length != dataWidth * dataHeight || pixels.isEmpty) {
      return null;
    }
    if (image.paletteProfile.isDynamic && referenceEncoding == null) {
      return null;
    }
    if (image.paletteProfile.isFixed && referenceEncoding != null) return null;

    final writer = _BitWriter();
    _writeV2Header(
      writer,
      profile: image.paletteProfile,
      container: _containerBlock,
      mode: ImageMode.extended,
      scan: ScanMode.h,
      boundsPresent: bounds != null,
      referenceEncoding: referenceEncoding,
      implicitWhiteBackground: _isImplicitWhiteBackground(
        image.paletteProfile,
        backgroundColor,
      ),
      width: image.width,
      height: image.height,
      hasTransparentColor: image.transparentColor != null,
      unalignedExtendedBody: image.paletteProfile.isFixed,
    );
    if (image.transparentColor != null) {
      _writeV2ColorRef(writer, image.paletteProfile, image.transparentColor!);
    }
    if (bounds != null) {
      _writeV2BackgroundRef(writer, image.paletteProfile, backgroundColor);
      _writeV2CompactBounds(writer, bounds, image.width, image.height);
    }
    if (image.paletteProfile.isDynamic) writer.alignToByte();
    writer.writeBits(ExtendedImageMode.quadtree.index, _extendedSubmodeBits);

    final int localPaletteSize;
    final int localBits;
    int? usedBankCount;
    late final List<int> localPixels;
    if (image.paletteProfile.isDynamic) {
      final profileColorIds = pixels
          .map(
            (color) => _profileColorIdForGlobalIndex(
              image.paletteProfile,
              color,
            )!,
          )
          .toList(growable: false);
      final backgroundId = _profileColorIdForGlobalIndex(
        image.paletteProfile,
        backgroundColor,
      )!;
      final localPalette = _buildDynamicLocalPalette(
        image.paletteProfile,
        profileColorIds,
        backgroundId,
        referenceEncoding!,
      );
      if (localPalette.isEmpty ||
          localPalette.length > _maxDynamicLocalPalette) {
        return null;
      }
      _writeDynamicLocalPalette(
        writer,
        image.paletteProfile,
        localPalette,
        referenceEncoding,
      );
      localPaletteSize = localPalette.length;
      localBits = _localBits(localPalette.length);
      final localIndexByProfileColorId = {
        for (var i = 0; i < localPalette.length; i++) localPalette[i]: i,
      };
      localPixels = profileColorIds
          .map((color) => localIndexByProfileColorId[color]!)
          .toList(growable: false);
      usedBankCount =
          referenceEncoding == DynamicPaletteReferenceEncoding.banked8x64
          ? localPalette.map((color) => color >> 6).toSet().length
          : null;
    } else {
      final local = _buildLocalPalette(pixels);
      if (local.colors.isEmpty) return null;
      final palette = _writeV2FixedLocalPalette(
        writer,
        local.colors,
        image.paletteProfile,
      );
      localPaletteSize = palette.length;
      localBits = _localBits(palette.length);
      final localIndexByColor = _localIndexMap(palette);
      localPixels = pixels
          .map((color) => localIndexByColor[color]!)
          .toList(growable: false);
    }

    _writeQuadtreeNode(
      writer,
      localPixels,
      dataWidth,
      0,
      0,
      dataWidth,
      dataHeight,
      localBits,
    );
    return _V2Payload(
      writer.toBytes(),
      localPaletteSize: localPaletteSize,
      usedBankCount: usedBankCount,
      bitsPerLocalPixel: localBits,
    );
  }

  _V2Payload? _tryBuildV2BitplanesPayload(
    MCOImage image,
    List<int> linear,
    ScanMode scan,
    DynamicPaletteReferenceEncoding? referenceEncoding, {
    required int dataWidth,
    required int dataHeight,
    required int backgroundColor,
    _ImageBounds? bounds,
  }) {
    if (linear.length != dataWidth * dataHeight || linear.isEmpty) {
      return null;
    }
    if (image.paletteProfile.isDynamic && referenceEncoding == null) {
      return null;
    }
    if (image.paletteProfile.isFixed && referenceEncoding != null) return null;

    final writer = _BitWriter();
    _writeV2Header(
      writer,
      profile: image.paletteProfile,
      container: _containerBlock,
      mode: ImageMode.extended,
      scan: scan,
      boundsPresent: bounds != null,
      referenceEncoding: referenceEncoding,
      implicitWhiteBackground: _isImplicitWhiteBackground(
        image.paletteProfile,
        backgroundColor,
      ),
      width: image.width,
      height: image.height,
      hasTransparentColor: image.transparentColor != null,
      unalignedExtendedBody: image.paletteProfile.isFixed,
    );
    if (image.transparentColor != null) {
      _writeV2ColorRef(writer, image.paletteProfile, image.transparentColor!);
    }
    if (bounds != null) {
      _writeV2BackgroundRef(writer, image.paletteProfile, backgroundColor);
      _writeV2CompactBounds(writer, bounds, image.width, image.height);
    }
    if (image.paletteProfile.isDynamic) writer.alignToByte();
    writer.writeBits(ExtendedImageMode.bitplanes.index, _extendedSubmodeBits);

    final int localPaletteSize;
    final int localBits;
    int? usedBankCount;
    late final List<int> localPixels;
    if (image.paletteProfile.isDynamic) {
      final profileColorIds = linear
          .map(
            (color) => _profileColorIdForGlobalIndex(
              image.paletteProfile,
              color,
            )!,
          )
          .toList(growable: false);
      final backgroundId = _profileColorIdForGlobalIndex(
        image.paletteProfile,
        backgroundColor,
      )!;
      final localPalette = _buildDynamicLocalPalette(
        image.paletteProfile,
        profileColorIds,
        backgroundId,
        referenceEncoding!,
      );
      if (localPalette.isEmpty ||
          localPalette.length > _maxDynamicLocalPalette) {
        return null;
      }
      _writeDynamicLocalPalette(
        writer,
        image.paletteProfile,
        localPalette,
        referenceEncoding,
      );
      localPaletteSize = localPalette.length;
      localBits = _localBits(localPalette.length);
      final localIndexByProfileColorId = {
        for (var i = 0; i < localPalette.length; i++) localPalette[i]: i,
      };
      localPixels = profileColorIds
          .map((color) => localIndexByProfileColorId[color]!)
          .toList(growable: false);
      usedBankCount =
          referenceEncoding == DynamicPaletteReferenceEncoding.banked8x64
          ? localPalette.map((color) => color >> 6).toSet().length
          : null;
    } else {
      final local = _buildLocalPalette(linear);
      if (local.colors.isEmpty) return null;
      final palette = _writeV2FixedLocalPalette(
        writer,
        local.colors,
        image.paletteProfile,
      );
      localPaletteSize = palette.length;
      localBits = _localBits(palette.length);
      final localIndexByColor = _localIndexMap(palette);
      localPixels = linear
          .map((color) => localIndexByColor[color]!)
          .toList(growable: false);
    }

    for (var bit = 0; bit < localBits; bit++) {
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
          _writeCompactUint(writer, length - 1);
        }
      } else {
        writer.writeBits(0, 1);
        for (final pixel in localPixels) {
          writer.writeBits((pixel >> bit) & 1, 1);
        }
      }
    }
    return _V2Payload(
      writer.toBytes(),
      localPaletteSize: localPaletteSize,
      usedBankCount: usedBankCount,
      bitsPerLocalPixel: localBits,
    );
  }

  _V2Payload? _tryBuildV2AdaptiveBitplanesPayload(
    MCOImage image,
    List<int> linear,
    ScanMode scan,
    DynamicPaletteReferenceEncoding? referenceEncoding, {
    required int dataWidth,
    required int dataHeight,
    required int backgroundColor,
    required bool directGrayscale,
    required bool directDynamicProfile,
    required _AdaptivePaletteOrder paletteOrder,
    required bool allowLargeMultiStart,
    _ImageBounds? bounds,
  }) {
    if (linear.length != dataWidth * dataHeight || linear.isEmpty) return null;
    if (directGrayscale && directDynamicProfile) return null;
    if (directGrayscale && !_isGrayscaleProfile(image.paletteProfile)) {
      return null;
    }
    if (directDynamicProfile && !image.paletteProfile.isDynamic) return null;
    if ((directGrayscale || directDynamicProfile) &&
        paletteOrder != _AdaptivePaletteOrder.frequency) {
      return null;
    }
    if (directDynamicProfile &&
        referenceEncoding != DynamicPaletteReferenceEncoding.flat) {
      return null;
    }
    if (image.paletteProfile.isDynamic &&
        referenceEncoding != null &&
        _usesExtendedDynamicPaletteDescriptor(referenceEncoding)) {
      return null;
    }
    if (image.paletteProfile.isDynamic && referenceEncoding == null) {
      return null;
    }
    if (image.paletteProfile.isFixed && referenceEncoding != null) return null;

    final writer = _BitWriter();
    _writeV2Header(
      writer,
      profile: image.paletteProfile,
      container: _containerBlock,
      mode: ImageMode.extended,
      scan: scan,
      boundsPresent: bounds != null,
      referenceEncoding: referenceEncoding,
      implicitWhiteBackground: _isImplicitWhiteBackground(
        image.paletteProfile,
        backgroundColor,
      ),
      width: image.width,
      height: image.height,
      hasTransparentColor: image.transparentColor != null,
      unalignedExtendedBody: image.paletteProfile.isFixed,
    );
    if (image.transparentColor != null) {
      _writeV2ColorRef(writer, image.paletteProfile, image.transparentColor!);
    }
    if (bounds != null) {
      _writeV2BackgroundRef(writer, image.paletteProfile, backgroundColor);
      _writeV2CompactBounds(writer, bounds, image.width, image.height);
    }
    if (image.paletteProfile.isDynamic) writer.alignToByte();
    writer.writeBits(ExtendedImageMode.bitplanes.index, _extendedSubmodeBits);

    if (directGrayscale) {
      writer.writeBits(0xc0, 8);
      _writeAdaptiveBitplanesBody(
        writer,
        linear,
        _globalBits(image.paletteProfile),
      );
      return _V2Payload(
        writer.toBytes(),
        bitsPerLocalPixel: _globalBits(image.paletteProfile),
      );
    }

    if (directDynamicProfile) {
      final profilePixels = linear
          .map(
            (color) => _profileColorIdForGlobalIndex(
              image.paletteProfile,
              color,
            )!,
          )
          .toList(growable: false);
      final profileSize = _dynamicProfileSize(image.paletteProfile);
      final profileBits = _dynamicProfileColorBits(image.paletteProfile);
      writer.writeBits(0xc0, 8);
      _writeAdaptiveBitplanesBody(writer, profilePixels, profileBits);
      return _V2Payload(
        writer.toBytes(),
        localPaletteSize: profileSize,
        bitsPerLocalPixel: profileBits,
      );
    }

    late final List<int> palette;
    if (image.paletteProfile.isDynamic) {
      final profileColorIds = linear
          .map(
            (color) => _profileColorIdForGlobalIndex(
              image.paletteProfile,
              color,
            )!,
          )
          .toList(growable: false);
      final backgroundId = _profileColorIdForGlobalIndex(
        image.paletteProfile,
        backgroundColor,
      )!;
      final profilePalette = _buildDynamicLocalPalette(
        image.paletteProfile,
        profileColorIds,
        backgroundId,
        referenceEncoding!,
      );
      if (profilePalette.isEmpty ||
          profilePalette.length > _maxDynamicLocalPalette) {
        return null;
      }
      palette = profilePalette
          .map(
            (color) => _globalIndexForProfileColorId(
              image.paletteProfile,
              color,
            ),
          )
          .toList(growable: false);
    } else {
      palette = _buildLocalPalette(linear).colors;
    }
    final orderedPalette = switch (paletteOrder) {
      _AdaptivePaletteOrder.frequency => palette,
      _AdaptivePaletteOrder.bitplaneOptimized =>
        _optimizeBitplanesPaletteOrder(linear, palette),
      _AdaptivePaletteOrder.profileId => _orderPaletteByProfileId(
        image.paletteProfile,
        palette,
      ),
      _AdaptivePaletteOrder.rgbProximity => _orderPaletteByRgb(
        image.paletteProfile,
        linear,
        palette,
        backgroundColor,
      ),
      _AdaptivePaletteOrder.transitionFrequency =>
        _optimizeTransitionPaletteOrder(
          linear,
          palette,
          backgroundColor,
        ),
      _AdaptivePaletteOrder.multiStartOptimized =>
        _optimizeBitplanesPaletteOrderMultiStart(
          image.paletteProfile,
          linear,
          palette,
          backgroundColor,
          allowLargeImage: allowLargeMultiStart,
        ),
    };
    if (paletteOrder != _AdaptivePaletteOrder.frequency &&
        _intListsEqual(orderedPalette, palette)) {
      return null;
    }

    writer.writeBits(0x80 | (orderedPalette.length - 1), 8);
    int? usedBankCount;
    if (image.paletteProfile.isDynamic) {
      final profilePalette = orderedPalette
          .map(
            (color) => _profileColorIdForGlobalIndex(
              image.paletteProfile,
              color,
            )!,
          )
          .toList(growable: false);
      _writeDynamicLocalPaletteBody(
        writer,
        image.paletteProfile,
        profilePalette,
        referenceEncoding!,
      );
      usedBankCount =
          referenceEncoding == DynamicPaletteReferenceEncoding.banked8x64
          ? profilePalette.map((color) => color >> 6).toSet().length
          : null;
    } else {
      _writePalette(writer, orderedPalette, image.paletteProfile);
    }
    final localIndex = _localIndexMap(orderedPalette);
    final localPixels = linear
        .map((color) => localIndex[color]!)
        .toList(growable: false);
    final localBits = _localBits(orderedPalette.length);
    _writeAdaptiveBitplanesBody(writer, localPixels, localBits);
    return _V2Payload(
      writer.toBytes(),
      localPaletteSize: orderedPalette.length,
      usedBankCount: usedBankCount,
      bitsPerLocalPixel: localBits,
    );
  }

  _V2Payload? _tryBuildV2CompactRowDeltaPayload(
    MCOImage image,
    List<int> linear,
    ScanMode scan,
    DynamicPaletteReferenceEncoding? referenceEncoding, {
    required int dataWidth,
    required int dataHeight,
    required int backgroundColor,
    required bool directGrayscale,
    required _CompactRowDeltaPaletteOrder paletteOrder,
    _ImageBounds? bounds,
  }) {
    if (linear.length != dataWidth * dataHeight || linear.isEmpty) return null;
    if (directGrayscale && !_isGrayscaleProfile(image.paletteProfile)) {
      return null;
    }
    if (paletteOrder != _CompactRowDeltaPaletteOrder.frequency &&
        image.paletteProfile.isDynamic &&
        referenceEncoding != DynamicPaletteReferenceEncoding.flat) {
      return null;
    }
    if (image.paletteProfile.isDynamic && referenceEncoding == null) {
      return null;
    }
    if (image.paletteProfile.isFixed && referenceEncoding != null) return null;

    final writer = _BitWriter();
    _writeV2Header(
      writer,
      profile: image.paletteProfile,
      container: _containerBlock,
      mode: ImageMode.extended,
      scan: scan,
      boundsPresent: bounds != null,
      referenceEncoding: referenceEncoding,
      implicitWhiteBackground: _isImplicitWhiteBackground(
        image.paletteProfile,
        backgroundColor,
      ),
      width: image.width,
      height: image.height,
      hasTransparentColor: image.transparentColor != null,
      unalignedExtendedBody: image.paletteProfile.isFixed,
    );
    if (image.transparentColor != null) {
      _writeV2ColorRef(writer, image.paletteProfile, image.transparentColor!);
    }
    if (bounds != null) {
      _writeV2BackgroundRef(writer, image.paletteProfile, backgroundColor);
      _writeV2CompactBounds(writer, bounds, image.width, image.height);
    }
    if (image.paletteProfile.isDynamic) writer.alignToByte();
    writer
      ..writeBits(
        ExtendedImageMode.compactRowDelta.index,
        _extendedSubmodeBits,
      )
      ..writeBits(directGrayscale ? 1 : 0, 1);

    final int valueBits;
    int? localPaletteSize;
    int? usedBankCount;
    late final List<int> values;
    if (directGrayscale) {
      valueBits = _globalBits(image.paletteProfile);
      values = linear;
    } else if (image.paletteProfile.isDynamic) {
      final profileColorIds = linear
          .map(
            (color) => _profileColorIdForGlobalIndex(
              image.paletteProfile,
              color,
            )!,
          )
          .toList(growable: false);
      final backgroundId = _profileColorIdForGlobalIndex(
        image.paletteProfile,
        backgroundColor,
      )!;
      var palette = _buildDynamicLocalPalette(
        image.paletteProfile,
        profileColorIds,
        backgroundId,
        referenceEncoding!,
      );
      if (paletteOrder != _CompactRowDeltaPaletteOrder.frequency) {
        final optimized = _optimizeTransitionPaletteOrder(
          profileColorIds,
          palette,
          backgroundId,
        );
        if (_intListsEqual(optimized, palette)) return null;
        palette = optimized;
      }
      if (palette.isEmpty || palette.length > _maxDynamicLocalPalette) {
        return null;
      }
      _writeDynamicLocalPalette(
        writer,
        image.paletteProfile,
        palette,
        referenceEncoding,
      );
      localPaletteSize = palette.length;
      valueBits = _localBits(palette.length);
      final localIndex = {
        for (var i = 0; i < palette.length; i++) palette[i]: i,
      };
      values = profileColorIds
          .map((color) => localIndex[color]!)
          .toList(growable: false);
      usedBankCount =
          referenceEncoding == DynamicPaletteReferenceEncoding.banked8x64
          ? palette.map((color) => color >> 6).toSet().length
          : null;
    } else {
      final local = _buildLocalPalette(
        linear,
        preferredFirstColor: backgroundColor,
      );
      if (local.colors.isEmpty) return null;
      var palette = local.colors;
      if (paletteOrder != _CompactRowDeltaPaletteOrder.frequency) {
        final optimized = _optimizeTransitionPaletteOrder(
          linear,
          palette,
          backgroundColor,
        );
        if (_intListsEqual(optimized, palette)) return null;
        palette = optimized;
      }
      palette = _writeV2FixedLocalPalette(
        writer,
        palette,
        image.paletteProfile,
      );
      localPaletteSize = palette.length;
      valueBits = _localBits(palette.length);
      final localIndex = _localIndexMap(palette);
      values = linear
          .map((color) => localIndex[color]!)
          .toList(growable: false);
    }

    _writeCompactRowDeltaBody(
      writer,
      values,
      _rowLengthForScan(scan, dataWidth, dataHeight),
      valueBits,
      directGrayscale: directGrayscale,
    );
    return _V2Payload(
      writer.toBytes(),
      localPaletteSize: localPaletteSize,
      usedBankCount: usedBankCount,
      bitsPerLocalPixel: valueBits,
    );
  }

  List<_V2Payload> _tryBuildV2RegionsPayloads(
    MCOImage image,
    int backgroundColor,
    DynamicPaletteReferenceEncoding? referenceEncoding,
    int maxRegions, {
    required bool includeExtendedFixedBlocks,
    required bool useExtremeSearch,
  }) {
    if (maxRegions == 0) return const <_V2Payload>[];
    final connectedRegions = _findRegions(
      image.pixels,
      image.width,
      image.height,
      backgroundColor,
    );
    final useBoundedExtremeSearch =
        useExtremeSearch &&
        image.pixels.length <= _maxExtremeRegionPixels &&
        connectedRegions.length <= _maxExtremeRegionComponents;
    final beamMaxRegions = useBoundedExtremeSearch
        ? math.min(maxRegions, _maxExtremeRegionSearchRegions)
        : maxRegions;

    if (useExtremeSearch && !useBoundedExtremeSearch) {
      debugPrint(
        '[MCOimg][Extreme][Regions] SKIP; '
        'deep search; '
        'bg=$backgroundColor; '
        'pixels=${image.pixels.length}/$_maxExtremeRegionPixels; '
        'components=${connectedRegions.length}/'
        '$_maxExtremeRegionComponents;');
    }

    final splitRegions = _splitRegionsByEmptyLines(
      image.pixels,
      image.width,
      backgroundColor,
      connectedRegions,
      maxRegions,
    );
    final sparseSplitRegions = _splitRegionsBySparseLines(
      image.pixels,
      image.width,
      backgroundColor,
      connectedRegions,
      maxRegions,
      maxLineNonBackground: 2,
    );
    final greedyRegionVariants = _findGreedyRectRegionVariants(
      image.pixels,
      image.width,
      image.height,
      backgroundColor,
      maxRegions,
    );

    final rawVariants = <List<_ImageBounds>>[
      connectedRegions,
      if (splitRegions.isNotEmpty) splitRegions,
      if (sparseSplitRegions.isNotEmpty) sparseSplitRegions,
      ...greedyRegionVariants,
    ];
    final variants = <List<_ImageBounds>>[];
    final seenVariants = <String>{};
    for (final regions in rawVariants) {
      if (regions.isEmpty) continue;
      if (seenVariants.add(_regionListKey(regions))) {
        variants.add(regions);
      }
    }
    final beamVariantCosts = <String, int>{};
    if ((useBoundedExtremeSearch ||
            image.pixels.length <= _maxBeamRegionPixels) &&
        (image.paletteProfile.isFixed ||
            referenceEncoding == DynamicPaletteReferenceEncoding.flat)) {
      final beamVariants = _findPayloadOptimizedRegionVariants(
        image,
        backgroundColor,
        referenceEncoding,
        variants,
        beamMaxRegions,
        useExtremeSearch: useBoundedExtremeSearch,
      );
      for (final state in beamVariants) {
        final key = _regionListKey(state.regions);
        if (seenVariants.add(key)) {
          variants.add(state.regions);
          beamVariantCosts[key] = state.cost;
        }
      }
    }

    final payloads = <_V2Payload>[];
    for (final regions in variants) {
      final regionKey = _regionListKey(regions);
      final beamCost = beamVariantCosts[regionKey];
      for (final compactGeometry in const [false, true]) {
          final payload = _tryBuildV2RegionsPayloadFromRegions(
            image,
            backgroundColor,
            referenceEncoding,
            regions,
            maxRegions,
            compactGeometry: compactGeometry,
            includeExtendedFixedBlocks: false,
            diagnosticContainer: beamCost == null ? null : 'regions-beam',
          );
        if (payload == null) continue;
        if (beamCost != null && payload.payload.length != beamCost) continue;
        payloads.add(payload);
        if (includeExtendedFixedBlocks && image.paletteProfile.isFixed) {
          final extendedPayload = _tryBuildV2RegionsPayloadFromRegions(
            image,
            backgroundColor,
            referenceEncoding,
            regions,
            maxRegions,
            compactGeometry: compactGeometry,
            includeExtendedFixedBlocks: true,
            diagnosticContainer: beamCost == null
                ? 'regions-extended'
                : 'regions-beam-extended',
          );
          if (extendedPayload != null) payloads.add(extendedPayload);
        }
        if (image.paletteProfile.isFixed) {
          final sharedPayload = _tryBuildV2RegionsPayloadFromRegions(
            image,
            backgroundColor,
            referenceEncoding,
            regions,
            maxRegions,
            compactGeometry: compactGeometry,
            sharedFixedPalette: true,
            includeExtendedFixedBlocks: false,
            diagnosticContainer: beamCost == null
                ? 'regions-shared-fixed'
                : 'regions-beam-shared-fixed',
          );
          if (sharedPayload != null) payloads.add(sharedPayload);
        }
      }
    }
    return payloads;
  }

  List<_RegionBeamState> _findPayloadOptimizedRegionVariants(
    MCOImage image,
    int backgroundColor,
    DynamicPaletteReferenceEncoding? referenceEncoding,
    List<List<_ImageBounds>> initialVariants,
    int maxRegions, {
    required bool useExtremeSearch,
  }) {
    final initialStates = <_RegionBeamState>[];
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
        referenceEncoding,
        normalized,
        maxRegions,
        includeExtendedFixedBlocks: false,
      );
      if (cost != null) initialStates.add(_RegionBeamState(normalized, cost));
    }
    if (initialStates.isEmpty) return const <_RegionBeamState>[];
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
    final improved = <_RegionBeamState>[];

    if (useExtremeSearch) {
      debugPrint(
        '[MCOimg][Extreme][Regions] START; '
        'budget=$evaluationBudget; '
        'bg=$backgroundColor; '
        'initial=${initialStates.length}; '
        'maxRegions=$maxRegions; '
        'width=$beamWidth; '
        'depth=$beamDepth; '
        'neighbors=$_extremeRegionNeighbors;');
    }

    for (var depth = 0; depth < beamDepth; depth++) {
      final next = <_RegionBeamState>[];
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
            referenceEncoding,
            regions,
            maxRegions,
            includeExtendedFixedBlocks: false,
          );
          if (cost == null) continue;
          final candidate = _RegionBeamState(regions, cost);
          next.add(candidate);
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
          '[MCOimg][Extreme][Regions] '
          '$completedDepths/$beamDepth '
          '(${(completedDepths * 100 / beamDepth).toStringAsFixed(1)}%); '
          'evaluated=$evaluatedLayouts/$evaluationBudget '
          '(${percentage.toStringAsFixed(1)}% budget); '
          'frontier=${beam.length}; '
          'improved=${improved.length};');
      }
      if (budgetExhausted) break;
    }

    if (useExtremeSearch) {
      final percentage =
          (evaluatedLayouts * 100 / evaluationBudget!).clamp(0, 100);
      debugPrint(
        '[MCOimg][Extreme][Regions] '
        '$completedDepths/$beamDepth '
        '(${(completedDepths * 100 / beamDepth).toStringAsFixed(1)}%); '
        'evaluated=$evaluatedLayouts/$evaluationBudget '
        '(${percentage.toStringAsFixed(1)}% budget); '
        'COMPLETE; '
        'bg=$backgroundColor; '
        'improved=${improved.length}; '
        'budgetExhausted=$budgetExhausted;');
    }

    improved.sort((left, right) => left.cost.compareTo(right.cost));
    final result = <_RegionBeamState>[];
    final resultKeys = <String>{};
    for (final state in improved) {
      if (resultKeys.add(_regionListKey(state.regions))) {
        result.add(state);
      }
      if (result.length >= resultLimit) break;
    }
    return result;
  }

  int? _regionPayloadByteCost(
    MCOImage image,
    int backgroundColor,
    DynamicPaletteReferenceEncoding? referenceEncoding,
    List<_ImageBounds> regions,
    int maxRegions, {
    required bool includeExtendedFixedBlocks,
  }) {
    int? best;
    for (final compactGeometry in const [false, true]) {
      final payload = _tryBuildV2RegionsPayloadFromRegions(
        image,
        backgroundColor,
        referenceEncoding,
        regions,
        maxRegions,
        compactGeometry: compactGeometry,
        includeExtendedFixedBlocks: false,
      );
      if (payload != null && (best == null || payload.payload.length < best)) {
        best = payload.payload.length;
      }
      if (includeExtendedFixedBlocks && image.paletteProfile.isFixed) {
        final extendedPayload = _tryBuildV2RegionsPayloadFromRegions(
          image,
          backgroundColor,
          referenceEncoding,
          regions,
          maxRegions,
          compactGeometry: compactGeometry,
          includeExtendedFixedBlocks: true,
        );
        if (extendedPayload != null &&
            (best == null || extendedPayload.payload.length < best)) {
          best = extendedPayload.payload.length;
        }
      }
    }
    return best;
  }

  List<List<_ImageBounds>> _regionBeamNeighborsFor(
    List<int> pixels,
    int fullWidth,
    int backgroundColor,
    List<_ImageBounds> regions,
    int maxRegions, {
    required bool useExtremeSearch,
  }) {
    final mergeNeighbors = <_RegionBeamNeighbor>[];
    if (regions.length > 1) {
      for (var left = 0; left < regions.length - 1; left++) {
        for (var right = left + 1; right < regions.length; right++) {
          final merged = _unionBounds(regions[left], regions[right]);
          final candidate = <_ImageBounds>[
            for (var i = 0; i < regions.length; i++)
              if (i != left && i != right) regions[i],
            merged,
          ];
          if (!_regionsDoNotOverlap(candidate)) continue;
          final addedArea =
              merged.area - regions[left].area - regions[right].area;
          mergeNeighbors.add(
            _RegionBeamNeighbor(_sortedRegions(candidate), addedArea),
          );
        }
      }
    }
    mergeNeighbors.sort(
      (left, right) => left.heuristic.compareTo(right.heuristic),
    );

    final splitNeighbors = <_RegionBeamNeighbor>[];
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

    final result = <List<_ImageBounds>>[];
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
    List<_RegionBeamNeighbor> output,
    List<_ImageBounds> regions,
    int replacedIndex,
    _ImageBounds original,
    List<_ImageBounds> parts,
  ) {
    if (parts.length != 2) return;
    final savedArea = original.area - parts[0].area - parts[1].area;
    if (savedArea <= 0) return;
    final candidate = <_ImageBounds>[
      for (var i = 0; i < regions.length; i++)
        if (i != replacedIndex) regions[i],
      ...parts,
    ];
    if (!_regionsDoNotOverlap(candidate)) return;
    output.add(_RegionBeamNeighbor(_sortedRegions(candidate), -savedArea));
  }

  List<_ImageBounds> _tightSplitRegion(
    List<int> pixels,
    int fullWidth,
    int backgroundColor,
    _ImageBounds region, {
    required bool vertical,
    required int cut,
  }) {
    final firstRect = vertical
        ? _ImageBounds(
            x: region.x,
            y: region.y,
            width: cut,
            height: region.height,
          )
        : _ImageBounds(
            x: region.x,
            y: region.y,
            width: region.width,
            height: cut,
          );
    final secondRect = vertical
        ? _ImageBounds(
            x: region.x + cut,
            y: region.y,
            width: region.width - cut,
            height: region.height,
          )
        : _ImageBounds(
            x: region.x,
            y: region.y + cut,
            width: region.width,
            height: region.height - cut,
          );
    return [
      _tightBoundsInRect(pixels, fullWidth, backgroundColor, firstRect),
      _tightBoundsInRect(pixels, fullWidth, backgroundColor, secondRect),
    ].whereType<_ImageBounds>().toList(growable: false);
  }

  static _ImageBounds _unionBounds(_ImageBounds left, _ImageBounds right) {
    final x = math.min(left.x, right.x);
    final y = math.min(left.y, right.y);
    final maxX = math.max(left.x + left.width, right.x + right.width);
    final maxY = math.max(left.y + left.height, right.y + right.height);
    return _ImageBounds(x: x, y: y, width: maxX - x, height: maxY - y);
  }

  static List<_ImageBounds> _sortedRegions(Iterable<_ImageBounds> regions) {
    return List<_ImageBounds>.of(regions)..sort((left, right) {
      final byY = left.y.compareTo(right.y);
      if (byY != 0) return byY;
      final byX = left.x.compareTo(right.x);
      if (byX != 0) return byX;
      final byHeight = left.height.compareTo(right.height);
      return byHeight != 0 ? byHeight : left.width.compareTo(right.width);
    });
  }

  static bool _regionsDoNotOverlap(List<_ImageBounds> regions) {
    for (var left = 0; left < regions.length - 1; left++) {
      final a = regions[left];
      for (var right = left + 1; right < regions.length; right++) {
        final b = regions[right];
        final overlaps =
            a.x < b.x + b.width &&
            b.x < a.x + a.width &&
            a.y < b.y + b.height &&
            b.y < a.y + a.height;
        if (overlaps) return false;
      }
    }
    return true;
  }

  _V2Payload? _tryBuildV2RegionsPayloadFromRegions(
    MCOImage image,
    int backgroundColor,
    DynamicPaletteReferenceEncoding? referenceEncoding,
    List<_ImageBounds> regions,
    int maxRegions, {
    required bool compactGeometry,
    bool sharedFixedPalette = false,
    required bool includeExtendedFixedBlocks,
    String? diagnosticContainer,
  }) {
    if (regions.isEmpty ||
        regions.length > maxRegions ||
        !_regionsDoNotOverlap(regions)) {
      return null;
    }
    if (image.paletteProfile.isDynamic && referenceEncoding == null) {
      throw const MCOImageInvalidInputException(
        'Dynamic v2 regions require reference encoding',
      );
    }
    if (image.paletteProfile.isFixed && referenceEncoding != null) return null;
    if (sharedFixedPalette && !image.paletteProfile.isFixed) return null;

    final writer = _BitWriter();
    _writeV2Header(
      writer,
      profile: image.paletteProfile,
      container: _containerRegions,
      mode: compactGeometry ? ImageMode.extended : ImageMode.rawGlobal,
      scan: ScanMode.h,
      boundsPresent: false,
      referenceEncoding: referenceEncoding,
      implicitWhiteBackground: _isImplicitWhiteBackground(
        image.paletteProfile,
        backgroundColor,
      ),
      width: image.width,
      height: image.height,
      hasTransparentColor: image.transparentColor != null,
      sharedFixedRegionsPalette: sharedFixedPalette,
    );
    if (image.transparentColor != null) {
      _writeV2ColorRef(writer, image.paletteProfile, image.transparentColor!);
    }
    final implicitFixedRegionsBackground =
        sharedFixedPalette &&
        _isImplicitWhiteBackground(image.paletteProfile, backgroundColor);
    if (sharedFixedPalette) {
      writer.writeBits(implicitFixedRegionsBackground ? 1 : 0, 1);
    }
    if (image.paletteProfile.isDynamic || implicitFixedRegionsBackground) {
      _writeV2BackgroundRef(writer, image.paletteProfile, backgroundColor);
    } else {
      _writeV2ColorRef(writer, image.paletteProfile, backgroundColor);
    }

    _DynamicLocalPalette? sharedDynamicPalette;
    _DynamicLocalPalette? sharedFixedLocalPalette;
    Map<int, int>? localIndexByProfileColorId;
    Map<int, int>? localIndexByFixedColor;
    int? usedBankCount;
    int? bitsPerLocalPixel;
    if (image.paletteProfile.isDynamic) {
      final allRegionProfileColorIds = <int>[];
      for (final region in regions) {
        final regionPixels = _cropPixels(image.pixels, image.width, region);
        for (final globalIndex in regionPixels) {
          final profileColorId = _profileColorIdForGlobalIndex(
            image.paletteProfile,
            globalIndex,
          );
          if (profileColorId == null) {
            throw MCOImageInvalidInputException(
              'Pixel globalIndex $globalIndex is not available in '
              '${image.paletteProfile.name}',
            );
          }
          allRegionProfileColorIds.add(profileColorId);
        }
      }
      final backgroundProfileColorId = _profileColorIdForGlobalIndex(
        image.paletteProfile,
        backgroundColor,
      )!;
      final localPalette = _buildDynamicLocalPalette(
        image.paletteProfile,
        allRegionProfileColorIds,
        backgroundProfileColorId,
        referenceEncoding!,
      );
      if (localPalette.isEmpty ||
          localPalette.length > _maxDynamicLocalPalette) {
        return null;
      }
      _writeDynamicLocalPalette(
        writer,
        image.paletteProfile,
        localPalette,
        referenceEncoding,
      );
      sharedDynamicPalette = _DynamicLocalPalette(
        localPalette
            .map(
              (profileColorId) => _globalIndexForProfileColorId(
                image.paletteProfile,
                profileColorId,
              ),
            )
            .toList(growable: false),
      );
      localIndexByProfileColorId = {
        for (var i = 0; i < localPalette.length; i++) localPalette[i]: i,
      };
      bitsPerLocalPixel = _localBits(localPalette.length);
      usedBankCount =
          referenceEncoding == DynamicPaletteReferenceEncoding.banked8x64
          ? localPalette
                .map((profileColorId) => profileColorId >> 6)
                .toSet()
                .length
          : null;
    } else if (sharedFixedPalette) {
      final colors = <int>[];
      for (final region in regions) {
        colors.addAll(_cropPixels(image.pixels, image.width, region));
      }
      final local = _buildLocalPalette(
        colors,
        preferredFirstColor: backgroundColor,
      );
      if (local.colors.isEmpty) return null;
      final palette = _writeV2FixedLocalPalette(
        writer,
        local.colors,
        image.paletteProfile,
      );
      sharedFixedLocalPalette = _DynamicLocalPalette(palette);
      localIndexByFixedColor = _localIndexMap(palette);
      bitsPerLocalPixel = _localBits(palette.length);
    }

    if (compactGeometry) {
      writer.writeBits(
        regions.length - 1,
        _bitsForChoiceCount(_maxV2Regions),
      );
    } else {
      writer.writeBitVarUint(regions.length);
    }
    for (final region in regions) {
      final regionPixels = _cropPixels(image.pixels, image.width, region);
      final block = image.paletteProfile.isDynamic
          ? _bestV2DynamicSharedBlockPayload(
              regionPixels,
              region.width,
              region.height,
              image.paletteProfile,
              backgroundColor,
              localIndexByProfileColorId!,
              includeExtendedBlocks: includeExtendedFixedBlocks,
            )
          : sharedFixedPalette
          ? _bestV2FixedSharedBlockPayload(
              regionPixels,
              region.width,
              region.height,
              backgroundColor,
              localIndexByFixedColor!,
              includeExtendedBlocks: includeExtendedFixedBlocks,
            )
          : _bestV2BlockPayload(
              regionPixels,
              region.width,
              region.height,
              image.paletteProfile,
              backgroundColor,
              includeExtendedBlocks: includeExtendedFixedBlocks,
            );
      if (compactGeometry) {
        _writeV2CompactBounds(
          writer,
          region,
          image.width,
          image.height,
        );
      } else {
        writer
          ..writeBitVarUint(region.x)
          ..writeBitVarUint(region.y)
          ..writeBitVarUint(region.width)
          ..writeBitVarUint(region.height);
      }
      writer
        ..writeAlignedByte(
          (_modeBits(block.mode) << 5) | (_scanBits(block.scan) << 3),
        )
        ..writeBitVarUint(block.payload.length)
        ..writeAlignedBytes(block.payload);
    }

    return _V2Payload(
      writer.toBytes(),
      regionCount: regions.length,
      localPaletteSize:
          sharedDynamicPalette?.globalColors.length ??
          sharedFixedLocalPalette?.globalColors.length,
      usedBankCount: usedBankCount,
      bitsPerLocalPixel: bitsPerLocalPixel,
      diagnosticContainer: diagnosticContainer,
    );
  }

  _V2BlockPayload? _tryBuildV2BlockBody(
    List<int> linear,
    PaletteProfile profile,
    ImageMode mode,
    DynamicPaletteReferenceEncoding? referenceEncoding, {
    required int rowLength,
    required int backgroundColor,
    required bool writeSparseBackground,
  }) {
    if (profile.isDynamic) {
      if (mode == ImageMode.rawGlobal) return null;
      if (referenceEncoding == null) {
        throw const MCOImageInvalidInputException(
          'Dynamic block requires reference encoding',
        );
      }
      return _tryBuildV2DynamicBlockBody(
        linear,
        profile,
        mode,
        referenceEncoding,
        rowLength: rowLength,
        backgroundColor: backgroundColor,
        writeSparseBackground: writeSparseBackground,
      );
    }

    if (referenceEncoding != null) return null;
    final writer = _BitWriter();
    switch (mode) {
      case ImageMode.rawGlobal:
        _encodeRawGlobal(writer, linear, profile);
        return _V2BlockPayload(
          writer.toBytes(),
          localPaletteSize: null,
          bitsPerLocalPixel: _globalBits(profile),
        );
      case ImageMode.rawLocal:
        final local = _buildLocalPalette(linear);
        if (local.colors.isEmpty) return null;
        final palette = _writeV2FixedLocalPalette(
          writer,
          local.colors,
          profile,
        );
        final map = _localIndexMap(palette);
        final localBits = _localBits(palette.length);
        for (final pixel in linear) {
          writer.writeBits(map[pixel]!, localBits);
        }
        return _V2BlockPayload(
          writer.toBytes(),
          localPaletteSize: palette.length,
          bitsPerLocalPixel: localBits,
        );
      case ImageMode.rleLocal:
        final local = _buildLocalPalette(linear);
        if (local.colors.isEmpty) return null;
        final palette = _writeV2FixedLocalPalette(
          writer,
          local.colors,
          profile,
        );
        final map = _localIndexMap(palette);
        final localBits = _localBits(palette.length);
        final runs = _buildRuns(linear);
        writer.writeBitVarUint(runs.length);
        for (final run in runs) {
          writer.writeBits(map[run.color]!, localBits);
          writer.writeBitVarUint(run.length);
        }
        return _V2BlockPayload(
          writer.toBytes(),
          localPaletteSize: palette.length,
          bitsPerLocalPixel: localBits,
        );
      case ImageMode.sparseBg:
        final nonBgColors = linear.where((p) => p != backgroundColor).toList();
        if (nonBgColors.isEmpty) return null;
        final local = _buildLocalPalette(nonBgColors);
        final segments = _buildSparseSegments(linear, backgroundColor);
        if (writeSparseBackground) {
          _writeV2BackgroundRef(writer, profile, backgroundColor);
        }
        final palette = _writeV2FixedLocalPalette(
          writer,
          local.colors,
          profile,
        );
        final map = _localIndexMap(palette);
        final localBits = _localBits(palette.length);
        writer.writeBitVarUint(segments.length);
        var pos = 0;
        for (final segment in segments) {
          writer.writeBitVarUint(segment.start - pos);
          writer.writeBits(map[segment.color]!, localBits);
          writer.writeBitVarUint(segment.length);
          pos = segment.start + segment.length;
        }
        return _V2BlockPayload(
          writer.toBytes(),
          localPaletteSize: palette.length,
          bitsPerLocalPixel: localBits,
        );
      case ImageMode.rowRepeat:
        final local = _buildLocalPalette(linear);
        if (local.colors.isEmpty) return null;
        final palette = _writeV2FixedLocalPalette(
          writer,
          local.colors,
          profile,
        );
        final map = _localIndexMap(palette);
        final localBits = _localBits(palette.length);
        _writeRowRepeatBody(
          writer,
          linear.map((pixel) => map[pixel]!).toList(growable: false),
          rowLength,
          localBits,
        );
        return _V2BlockPayload(
          writer.toBytes(),
          localPaletteSize: palette.length,
          bitsPerLocalPixel: localBits,
        );
      case ImageMode.rowDelta:
        final local = _buildLocalPalette(
          linear,
          preferredFirstColor: backgroundColor,
        );
        if (local.colors.isEmpty) return null;
        final palette = _writeV2FixedLocalPalette(
          writer,
          local.colors,
          profile,
        );
        final map = _localIndexMap(palette);
        final localBits = _localBits(palette.length);
        _writeRowDeltaBody(
          writer,
          linear.map((pixel) => map[pixel]!).toList(growable: false),
          rowLength,
          localBits,
        );
        return _V2BlockPayload(
          writer.toBytes(),
          localPaletteSize: palette.length,
          bitsPerLocalPixel: localBits,
        );
      case ImageMode.biColorMask:
        final foregroundColor = _biColorForeground(linear, backgroundColor);
        if (foregroundColor == null) return null;
        if (writeSparseBackground) {
          _writeV2BackgroundRef(writer, profile, backgroundColor);
        }
        _writeV2ColorRef(writer, profile, foregroundColor);
        _writeBiColorMask(writer, linear, backgroundColor, foregroundColor);
        return _V2BlockPayload(
          writer.toBytes(),
          localPaletteSize: 2,
          bitsPerLocalPixel: 1,
        );
      case ImageMode.extended:
      case ImageMode.regionsBg:
        throw const MCOImageInvalidInputException(
          'REGIONS_BG is not a block mode',
        );
    }
  }

  _V2BlockPayload? _tryBuildV2DynamicBlockBody(
    List<int> linear,
    PaletteProfile profile,
    ImageMode mode,
    DynamicPaletteReferenceEncoding referenceEncoding, {
    required int rowLength,
    required int backgroundColor,
    required bool writeSparseBackground,
  }) {
    if (referenceEncoding == DynamicPaletteReferenceEncoding.banked8x64 &&
        profile != PaletteProfile.dynamicGlobal512) {
      return null;
    }

    if (mode == ImageMode.biColorMask) {
      if (_usesExtendedDynamicPaletteDescriptor(referenceEncoding)) {
        return null;
      }
      final foregroundColor = _biColorForeground(linear, backgroundColor);
      if (foregroundColor == null) return null;
      final foregroundProfileColorId = _profileColorIdForGlobalIndex(
        profile,
        foregroundColor,
      );
      final backgroundProfileColorId = _profileColorIdForGlobalIndex(
        profile,
        backgroundColor,
      );
      if (foregroundProfileColorId == null ||
          backgroundProfileColorId == null) {
        throw MCOImageInvalidInputException(
          'Bi-color mask color is not available in ${profile.name}',
        );
      }
      final writer = _BitWriter();
      if (writeSparseBackground) {
        _writeV2BackgroundRef(writer, profile, backgroundColor);
      }
      _writeV2ColorRef(writer, profile, foregroundColor);
      _writeBiColorMask(writer, linear, backgroundColor, foregroundColor);
      final usedBankCount =
          referenceEncoding == DynamicPaletteReferenceEncoding.banked8x64
          ? {
              backgroundProfileColorId >> 6,
              foregroundProfileColorId >> 6,
            }.length
          : null;
      return _V2BlockPayload(
        writer.toBytes(),
        localPaletteSize: 2,
        usedBankCount: usedBankCount,
        bitsPerLocalPixel: 1,
      );
    }

    final profileColorIds = <int>[];
    for (final globalIndex in linear) {
      if (mode == ImageMode.sparseBg && globalIndex == backgroundColor) {
        continue;
      }
      final profileColorId = _profileColorIdForGlobalIndex(
        profile,
        globalIndex,
      );
      if (profileColorId == null) {
        throw MCOImageInvalidInputException(
          'Pixel globalIndex $globalIndex is not available in ${profile.name}',
        );
      }
      profileColorIds.add(profileColorId);
    }
    final backgroundProfileColorId = _profileColorIdForGlobalIndex(
      profile,
      backgroundColor,
    );
    if (backgroundProfileColorId == null) {
      throw MCOImageInvalidInputException(
        'backgroundColor $backgroundColor is not available in ${profile.name}',
      );
    }
    if (profileColorIds.isEmpty) return null;

    final localPalette = _buildDynamicLocalPalette(
      profile,
      profileColorIds,
      backgroundProfileColorId,
      referenceEncoding,
    );
    if (localPalette.length > _maxDynamicLocalPalette) return null;
    final localIndexByProfileColorId = {
      for (var i = 0; i < localPalette.length; i++) localPalette[i]: i,
    };
    final localBits = _localBits(localPalette.length);
    final writer = _BitWriter();
    if (mode == ImageMode.sparseBg && writeSparseBackground) {
      _writeV2BackgroundRef(writer, profile, backgroundColor);
    }
    _writeDynamicLocalPalette(writer, profile, localPalette, referenceEncoding);

    switch (mode) {
      case ImageMode.rawLocal:
        for (final globalIndex in linear) {
          final profileColorId = _profileColorIdForGlobalIndex(
            profile,
            globalIndex,
          )!;
          writer.writeBits(
            localIndexByProfileColorId[profileColorId]!,
            localBits,
          );
        }
        break;
      case ImageMode.rleLocal:
        final localPixels = linear.map((globalIndex) {
          final profileColorId = _profileColorIdForGlobalIndex(
            profile,
            globalIndex,
          )!;
          return localIndexByProfileColorId[profileColorId]!;
        }).toList();
        final runs = _buildRuns(localPixels);
        writer.writeBitVarUint(runs.length);
        for (final run in runs) {
          writer.writeBits(run.color, localBits);
          writer.writeBitVarUint(run.length);
        }
        break;
      case ImageMode.sparseBg:
        final segments = _buildDynamicSparseSegments(
          linear,
          profile,
          backgroundColor,
          localIndexByProfileColorId,
        );
        writer.writeBitVarUint(segments.length);
        var pos = 0;
        for (final segment in segments) {
          writer.writeBitVarUint(segment.start - pos);
          writer.writeBits(segment.color, localBits);
          writer.writeBitVarUint(segment.length);
          pos = segment.start + segment.length;
        }
        break;
      case ImageMode.rowRepeat:
        final localPixels = linear
            .map((globalIndex) {
              final profileColorId = _profileColorIdForGlobalIndex(
                profile,
                globalIndex,
              )!;
              return localIndexByProfileColorId[profileColorId]!;
            })
            .toList(growable: false);
        _writeRowRepeatBody(writer, localPixels, rowLength, localBits);
        break;
      case ImageMode.rowDelta:
        final localPixels = linear
            .map((globalIndex) {
              final profileColorId = _profileColorIdForGlobalIndex(
                profile,
                globalIndex,
              )!;
              return localIndexByProfileColorId[profileColorId]!;
            })
            .toList(growable: false);
        _writeRowDeltaBody(writer, localPixels, rowLength, localBits);
        break;
      case ImageMode.rawGlobal:
      case ImageMode.extended:
      case ImageMode.regionsBg:
      case ImageMode.biColorMask:
        return null;
    }

    final usedBankCount =
        referenceEncoding == DynamicPaletteReferenceEncoding.banked8x64
        ? localPalette
              .map((profileColorId) => profileColorId >> 6)
              .toSet()
              .length
        : null;
    return _V2BlockPayload(
      writer.toBytes(),
      localPaletteSize: localPalette.length,
      usedBankCount: usedBankCount,
      bitsPerLocalPixel: localBits,
    );
  }

  _BlockPayload _bestV2BlockPayload(
    List<int> pixels,
    int width,
    int height,
    PaletteProfile profile,
    int backgroundColor, {
    bool includeExtendedBlocks = false,
  }) {
    _BlockPayload? best;
    for (final scan in ScanMode.values) {
      final linear = _toScanOrder(pixels, width, height, scan);
      for (final mode in _v2BlockModes) {
        final block = _tryBuildV2BlockBody(
          linear,
          profile,
          mode,
          null,
          rowLength: _rowLengthForScan(scan, width, height),
          backgroundColor: backgroundColor,
          writeSparseBackground: false,
        );
        if (block == null) continue;
        final candidate = _BlockPayload(block.payload, mode, scan);
        if (best == null ||
            candidate.payload.length < best.payload.length ||
            (candidate.payload.length == best.payload.length &&
                _modeTieOrder.indexOf(candidate.mode) <
                    _modeTieOrder.indexOf(best.mode))) {
          best = candidate;
        }
      }
      if (includeExtendedBlocks && profile.isFixed) {
        for (final block in _tryBuildV2FixedExtendedBlockBodies(
          linear,
          profile,
          backgroundColor,
          rowLength: _rowLengthForScan(scan, width, height),
        )) {
          final candidate = _BlockPayload(
            block.payload,
            ImageMode.extended,
            scan,
          );
          if (best == null ||
              candidate.payload.length < best.payload.length ||
              (candidate.payload.length == best.payload.length &&
                  _modeTieOrder.indexOf(candidate.mode) <
                      _modeTieOrder.indexOf(best.mode))) {
            best = candidate;
          }
        }
      }
    }
    return best!;
  }

  List<_V2BlockPayload> _tryBuildV2FixedExtendedBlockBodies(
    List<int> linear,
    PaletteProfile profile,
    int backgroundColor, {
    required int rowLength,
  }) {
    if (!profile.isFixed || linear.isEmpty) return const <_V2BlockPayload>[];
    final result = <_V2BlockPayload>[];
    final compactRle = _tryBuildV2FixedCompactRleBlockBody(linear, profile);
    if (compactRle != null) result.add(compactRle);
    final compactSparse = _tryBuildV2FixedCompactSparseBlockBody(
      linear,
      profile,
      backgroundColor,
    );
    if (compactSparse != null) result.add(compactSparse);
    final bitplanes = _tryBuildV2FixedBitplanesBlockBody(linear, profile);
    if (bitplanes != null) result.add(bitplanes);
    final lzPixels = _tryBuildV2FixedLzPixelsBlockBody(
      linear,
      profile,
      optimizeParsing: false,
    );
    if (lzPixels != null) result.add(lzPixels);
    final optimalLzPixels = _tryBuildV2FixedLzPixelsBlockBody(
      linear,
      profile,
      optimizeParsing: true,
    );
    if (optimalLzPixels != null) result.add(optimalLzPixels);
    if (rowLength > 0) {
      final quadtree = _tryBuildV2FixedQuadtreeBlockBody(
        linear,
        width: rowLength,
        height: linear.length ~/ rowLength,
        profile: profile,
      );
      if (quadtree != null) result.add(quadtree);
    }
    final compactRowDelta = _tryBuildV2FixedCompactRowDeltaBlockBody(
      linear,
      profile,
      backgroundColor,
      rowLength: rowLength,
      directGrayscale: false,
      paletteOrder: _CompactRowDeltaPaletteOrder.frequency,
    );
    if (compactRowDelta != null) result.add(compactRowDelta);
    final optimizedCompactRowDelta = _tryBuildV2FixedCompactRowDeltaBlockBody(
      linear,
      profile,
      backgroundColor,
      rowLength: rowLength,
      directGrayscale: false,
      paletteOrder: _CompactRowDeltaPaletteOrder.transitionFrequency,
    );
    if (optimizedCompactRowDelta != null) {
      result.add(optimizedCompactRowDelta);
    }
    if (_isGrayscaleProfile(profile)) {
      final directGrayscaleRowDelta = _tryBuildV2FixedCompactRowDeltaBlockBody(
        linear,
        profile,
        backgroundColor,
        rowLength: rowLength,
        directGrayscale: true,
        paletteOrder: _CompactRowDeltaPaletteOrder.frequency,
      );
      if (directGrayscaleRowDelta != null) result.add(directGrayscaleRowDelta);
    }
    return result;
  }

  _V2BlockPayload? _tryBuildV2FixedLzPixelsBlockBody(
    List<int> linear,
    PaletteProfile profile, {
    required bool optimizeParsing,
  }) {
    if (!profile.isFixed || linear.isEmpty) return null;
    final local = _buildLocalPalette(linear);
    if (local.colors.isEmpty) return null;
    final writer = _BitWriter()
      ..writeBits(ExtendedImageMode.lzPixels.index, _extendedSubmodeBits);
    final palette = _writeV2FixedLocalPalette(
      writer,
      local.colors,
      profile,
    );
    final localBits = _localBits(palette.length);
    final localIndexByColor = _localIndexMap(palette);
    final localPixels = linear
        .map((color) => localIndexByColor[color]!)
        .toList(growable: false);
    final greedyTokens = _buildGreedyLzPixelTokens(localPixels, localBits);
    final List<_LzPixelToken> tokens;
    if (optimizeParsing) {
      if (localPixels.length > _maxOptimalLzPixels) return null;
      final optimalTokens = _buildOptimalLzPixelTokens(localPixels, localBits);
      if (optimalTokens == null) return null;
      final optimalCost = _lzPixelTokensBitCost(optimalTokens, localBits);
      final greedyCost = _lzPixelTokensBitCost(greedyTokens, localBits);
      if (optimalCost > greedyCost ||
          (optimalCost == greedyCost &&
              _lzPixelTokensEqual(optimalTokens, greedyTokens))) {
        return null;
      }
      tokens = optimalTokens;
    } else {
      tokens = greedyTokens;
    }
    for (final token in tokens) {
      if (token.isMatch) {
        writer.writeBits(1, 1);
        _writeCompactUint(writer, token.distance - 1);
        _writeCompactUint(writer, token.length - _minLzMatchLength);
      } else {
        writer.writeBits(0, 1);
        _writeCompactUint(writer, token.literals.length - 1);
        for (final color in token.literals) {
          writer.writeBits(color, localBits);
        }
      }
    }
    return _V2BlockPayload(
      writer.toBytes(),
      localPaletteSize: palette.length,
      bitsPerLocalPixel: localBits,
    );
  }

  _V2BlockPayload? _tryBuildV2FixedQuadtreeBlockBody(
    List<int> linear, {
    required int width,
    required int height,
    required PaletteProfile profile,
  }) {
    if (!profile.isFixed ||
        linear.isEmpty ||
        width <= 0 ||
        height <= 0 ||
        linear.length != width * height) {
      return null;
    }
    final local = _buildLocalPalette(linear);
    if (local.colors.isEmpty) return null;
    final writer = _BitWriter()
      ..writeBits(ExtendedImageMode.quadtree.index, _extendedSubmodeBits);
    final palette = _writeV2FixedLocalPalette(
      writer,
      local.colors,
      profile,
    );
    final localBits = _localBits(palette.length);
    final localIndexByColor = _localIndexMap(palette);
    final localPixels = linear
        .map((color) => localIndexByColor[color]!)
        .toList(growable: false);
    _writeQuadtreeNode(
      writer,
      localPixels,
      width,
      0,
      0,
      width,
      height,
      localBits,
    );
    return _V2BlockPayload(
      writer.toBytes(),
      localPaletteSize: palette.length,
      bitsPerLocalPixel: localBits,
    );
  }

  _V2BlockPayload? _tryBuildV2FixedCompactRleBlockBody(
    List<int> linear,
    PaletteProfile profile,
  ) {
    if (!profile.isFixed || linear.isEmpty) return null;
    final local = _buildLocalPalette(linear);
    if (local.colors.isEmpty) return null;
    final writer = _BitWriter()
      ..writeBits(ExtendedImageMode.compactRle.index, _extendedSubmodeBits);
    final palette = _writeV2FixedLocalPalette(
      writer,
      local.colors,
      profile,
    );
    final localBits = _localBits(palette.length);
    final localIndexByColor = _localIndexMap(palette);
    for (final run in _buildRuns(linear)) {
      writer.writeBits(localIndexByColor[run.color]!, localBits);
      _writeCompactUint(writer, run.length - 1);
    }
    return _V2BlockPayload(
      writer.toBytes(),
      localPaletteSize: palette.length,
      bitsPerLocalPixel: localBits,
    );
  }

  _V2BlockPayload? _tryBuildV2FixedCompactSparseBlockBody(
    List<int> linear,
    PaletteProfile profile,
    int backgroundColor,
  ) {
    if (!profile.isFixed || linear.isEmpty) return null;
    final segments = _buildSparseSegments(linear, backgroundColor);
    if (segments.isEmpty) return null;
    final nonBgColors = linear
        .where((color) => color != backgroundColor)
        .toList(growable: false);
    final local = _buildLocalPalette(nonBgColors);
    if (local.colors.isEmpty) return null;
    final writer = _BitWriter()
      ..writeBits(ExtendedImageMode.compactSparse.index, _extendedSubmodeBits);
    final palette = _writeV2FixedLocalPalette(
      writer,
      local.colors,
      profile,
    );
    final localBits = _localBits(palette.length);
    final localIndexByColor = _localIndexMap(palette);
    _writeCompactUint(writer, segments.length - 1);
    var pos = 0;
    for (final segment in segments) {
      _writeCompactUint(writer, segment.start - pos);
      writer.writeBits(localIndexByColor[segment.color]!, localBits);
      _writeCompactUint(writer, segment.length - 1);
      pos = segment.start + segment.length;
    }
    return _V2BlockPayload(
      writer.toBytes(),
      localPaletteSize: palette.length,
      bitsPerLocalPixel: localBits,
    );
  }

  _V2BlockPayload? _tryBuildV2FixedBitplanesBlockBody(
    List<int> linear,
    PaletteProfile profile,
  ) {
    if (!profile.isFixed || linear.isEmpty) return null;
    final local = _buildLocalPalette(linear);
    if (local.colors.isEmpty) return null;
    final writer = _BitWriter()
      ..writeBits(ExtendedImageMode.bitplanes.index, _extendedSubmodeBits);
    final palette = _writeV2FixedLocalPalette(
      writer,
      local.colors,
      profile,
    );
    final localBits = _localBits(palette.length);
    final localIndexByColor = _localIndexMap(palette);
    final localPixels = linear
        .map((color) => localIndexByColor[color]!)
        .toList(growable: false);
    for (var bit = 0; bit < localBits; bit++) {
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
          _writeCompactUint(writer, length - 1);
        }
      } else {
        writer.writeBits(0, 1);
        for (final pixel in localPixels) {
          writer.writeBits((pixel >> bit) & 1, 1);
        }
      }
    }
    return _V2BlockPayload(
      writer.toBytes(),
      localPaletteSize: palette.length,
      bitsPerLocalPixel: localBits,
    );
  }

  _V2BlockPayload? _tryBuildV2FixedCompactRowDeltaBlockBody(
    List<int> linear,
    PaletteProfile profile,
    int backgroundColor, {
    required int rowLength,
    required bool directGrayscale,
    required _CompactRowDeltaPaletteOrder paletteOrder,
  }) {
    if (!profile.isFixed || linear.isEmpty) return null;
    if (directGrayscale && !_isGrayscaleProfile(profile)) return null;
    final writer = _BitWriter()
      ..writeBits(
        ExtendedImageMode.compactRowDelta.index,
        _extendedSubmodeBits,
      )
      ..writeBits(directGrayscale ? 1 : 0, 1);
    final int valueBits;
    int? localPaletteSize;
    late final List<int> values;
    if (directGrayscale) {
      valueBits = _globalBits(profile);
      values = linear;
    } else {
      final local = _buildLocalPalette(
        linear,
        preferredFirstColor: backgroundColor,
      );
      if (local.colors.isEmpty) return null;
      var palette = local.colors;
      if (paletteOrder != _CompactRowDeltaPaletteOrder.frequency) {
        final optimized = _optimizeTransitionPaletteOrder(
          linear,
          palette,
          backgroundColor,
        );
        if (_intListsEqual(optimized, palette)) return null;
        palette = optimized;
      }
      palette = _writeV2FixedLocalPalette(writer, palette, profile);
      localPaletteSize = palette.length;
      valueBits = _localBits(palette.length);
      final localIndexByColor = _localIndexMap(palette);
      values = linear
          .map((color) => localIndexByColor[color]!)
          .toList(growable: false);
    }
    _writeCompactRowDeltaBody(
      writer,
      values,
      rowLength,
      valueBits,
      directGrayscale: directGrayscale,
    );
    return _V2BlockPayload(
      writer.toBytes(),
      localPaletteSize: localPaletteSize,
      bitsPerLocalPixel: valueBits,
    );
  }

  _BlockPayload _bestV2DynamicSharedBlockPayload(
    List<int> pixels,
    int width,
    int height,
    PaletteProfile profile,
    int backgroundColor,
    Map<int, int> localIndexByProfileColorId, {
    required bool includeExtendedBlocks,
  }) {
    _BlockPayload? best;
    for (final scan in ScanMode.values) {
      final linear = _toScanOrder(pixels, width, height, scan);
      final localBits = _localBits(localIndexByProfileColorId.length);
      final localPixels = linear
          .map((globalIndex) {
            final profileColorId = _profileColorIdForGlobalIndex(
              profile,
              globalIndex,
            );
            final localIndex = localIndexByProfileColorId[profileColorId];
            if (localIndex == null) {
              throw MCOImageInvalidInputException(
                'Dynamic shared palette is missing globalIndex $globalIndex',
              );
            }
            return localIndex;
          })
          .toList(growable: false);
      final backgroundProfileColorId = _profileColorIdForGlobalIndex(
        profile,
        backgroundColor,
      )!;
      final backgroundIndex =
          localIndexByProfileColorId[backgroundProfileColorId];
      for (final mode in _dynamicBlockModes) {
        if (mode == ImageMode.biColorMask &&
            _biColorForeground(linear, backgroundColor) == null) {
          continue;
        }
        final writer = _BitWriter();
        _writeV2DynamicBlockWithLocalPalette(
          writer,
          linear,
          mode,
          profile,
          rowLength: _rowLengthForScan(scan, width, height),
          backgroundColor: backgroundColor,
          localIndexByProfileColorId: localIndexByProfileColorId,
        );
        final candidate = _BlockPayload(writer.toBytes(), mode, scan);
        if (best == null ||
            candidate.payload.length < best.payload.length ||
            (candidate.payload.length == best.payload.length &&
                _modeTieOrder.indexOf(candidate.mode) <
                    _modeTieOrder.indexOf(best.mode))) {
          best = candidate;
        }
      }
      if (includeExtendedBlocks) {
        for (final block in _tryBuildV2SharedPaletteExtendedBlockBodies(
          localPixels,
          localBits,
          backgroundIndex,
          rowLength: _rowLengthForScan(scan, width, height),
          width: width,
          height: height,
        )) {
          final candidate = _BlockPayload(
            block.payload,
            ImageMode.extended,
            scan,
          );
          if (best == null ||
              candidate.payload.length < best.payload.length ||
              (candidate.payload.length == best.payload.length &&
                  _modeTieOrder.indexOf(candidate.mode) <
                      _modeTieOrder.indexOf(best.mode))) {
            best = candidate;
          }
        }
      }
    }
    return best!;
  }

  _BlockPayload _bestV2FixedSharedBlockPayload(
    List<int> pixels,
    int width,
    int height,
    int backgroundColor,
    Map<int, int> localIndexByColor, {
    required bool includeExtendedBlocks,
  }) {
    _BlockPayload? best;
    for (final scan in ScanMode.values) {
      final linear = _toScanOrder(pixels, width, height, scan);
      final localBits = _localBits(localIndexByColor.length);
      final localPixels = linear
          .map((color) => localIndexByColor[color]!)
          .toList(growable: false);
      final backgroundIndex = localIndexByColor[backgroundColor];
      for (final mode in _dynamicBlockModes) {
        if (mode == ImageMode.biColorMask &&
            _biColorForeground(linear, backgroundColor) == null) {
          continue;
        }
        final writer = _BitWriter();
        _writeV2FixedBlockWithSharedPalette(
          writer,
          linear,
          mode,
          rowLength: _rowLengthForScan(scan, width, height),
          backgroundColor: backgroundColor,
          localIndexByColor: localIndexByColor,
        );
        final candidate = _BlockPayload(writer.toBytes(), mode, scan);
        if (best == null ||
            candidate.payload.length < best.payload.length ||
            (candidate.payload.length == best.payload.length &&
                _modeTieOrder.indexOf(candidate.mode) <
                    _modeTieOrder.indexOf(best.mode))) {
          best = candidate;
        }
      }
      if (includeExtendedBlocks) {
        for (final block in _tryBuildV2SharedPaletteExtendedBlockBodies(
          localPixels,
          localBits,
          backgroundIndex,
          rowLength: _rowLengthForScan(scan, width, height),
          width: width,
          height: height,
        )) {
          final candidate = _BlockPayload(
            block.payload,
            ImageMode.extended,
            scan,
          );
          if (best == null ||
              candidate.payload.length < best.payload.length ||
              (candidate.payload.length == best.payload.length &&
                  _modeTieOrder.indexOf(candidate.mode) <
                      _modeTieOrder.indexOf(best.mode))) {
            best = candidate;
          }
        }
      }
    }
    return best!;
  }

  List<_V2BlockPayload> _tryBuildV2SharedPaletteExtendedBlockBodies(
    List<int> localPixels,
    int localBits,
    int? backgroundIndex, {
    required int rowLength,
    required int width,
    required int height,
  }) {
    if (localPixels.isEmpty) return const <_V2BlockPayload>[];
    final result = <_V2BlockPayload>[];

    final compactRle = _tryBuildV2SharedCompactRleBlockBody(
      localPixels,
      localBits,
    );
    if (compactRle != null) result.add(compactRle);

    if (backgroundIndex != null) {
      final compactSparse = _tryBuildV2SharedCompactSparseBlockBody(
        localPixels,
        localBits,
        backgroundIndex,
      );
      if (compactSparse != null) result.add(compactSparse);
    }

    final bitplanes = _tryBuildV2SharedBitplanesBlockBody(
      localPixels,
      localBits,
    );
    if (bitplanes != null) result.add(bitplanes);

    final lzPixels = _tryBuildV2SharedLzPixelsBlockBody(
      localPixels,
      localBits,
      optimizeParsing: false,
    );
    if (lzPixels != null) result.add(lzPixels);

    final optimalLzPixels = _tryBuildV2SharedLzPixelsBlockBody(
      localPixels,
      localBits,
      optimizeParsing: true,
    );
    if (optimalLzPixels != null) result.add(optimalLzPixels);

    if (width > 0 && height > 0 && localPixels.length == width * height) {
      final quadtree = _tryBuildV2SharedQuadtreeBlockBody(
        localPixels,
        localBits,
        width: width,
        height: height,
      );
      if (quadtree != null) result.add(quadtree);
    }

    if (rowLength > 0) {
      final compactRowDelta = _tryBuildV2SharedCompactRowDeltaBlockBody(
        localPixels,
        localBits,
        rowLength,
      );
      if (compactRowDelta != null) result.add(compactRowDelta);
    }

    return result;
  }

  _V2BlockPayload? _tryBuildV2SharedCompactRleBlockBody(
    List<int> localPixels,
    int localBits,
  ) {
    if (localPixels.isEmpty) return null;
    final writer = _BitWriter()
      ..writeBits(ExtendedImageMode.compactRle.index, _extendedSubmodeBits);
    for (final run in _buildRuns(localPixels)) {
      writer.writeBits(run.color, localBits);
      _writeCompactUint(writer, run.length - 1);
    }
    return _V2BlockPayload(
      writer.toBytes(),
      bitsPerLocalPixel: localBits,
    );
  }

  _V2BlockPayload? _tryBuildV2SharedCompactSparseBlockBody(
    List<int> localPixels,
    int localBits,
    int backgroundIndex,
  ) {
    if (localPixels.isEmpty ||
        localPixels.every((pixel) => pixel == backgroundIndex)) {
      return null;
    }
    final segments = _buildSparseSegments(localPixels, backgroundIndex);
    if (segments.isEmpty) return null;
    final writer = _BitWriter()
      ..writeBits(ExtendedImageMode.compactSparse.index, _extendedSubmodeBits);
    _writeCompactUint(writer, segments.length - 1);
    var pos = 0;
    for (final segment in segments) {
      _writeCompactUint(writer, segment.start - pos);
      writer.writeBits(segment.color, localBits);
      _writeCompactUint(writer, segment.length - 1);
      pos = segment.start + segment.length;
    }
    return _V2BlockPayload(
      writer.toBytes(),
      bitsPerLocalPixel: localBits,
    );
  }

  _V2BlockPayload? _tryBuildV2SharedBitplanesBlockBody(
    List<int> localPixels,
    int localBits,
  ) {
    if (localPixels.isEmpty) return null;
    final writer = _BitWriter()
      ..writeBits(ExtendedImageMode.bitplanes.index, _extendedSubmodeBits);
    _writeAdaptiveBitplanesBody(writer, localPixels, localBits);
    return _V2BlockPayload(
      writer.toBytes(),
      bitsPerLocalPixel: localBits,
    );
  }

  _V2BlockPayload? _tryBuildV2SharedLzPixelsBlockBody(
    List<int> localPixels,
    int localBits, {
    required bool optimizeParsing,
  }) {
    if (localPixels.isEmpty) return null;
    final greedyTokens = _buildGreedyLzPixelTokens(localPixels, localBits);
    final List<_LzPixelToken> tokens;
    if (optimizeParsing) {
      if (localPixels.length > _maxOptimalLzPixels) return null;
      final optimalTokens = _buildOptimalLzPixelTokens(localPixels, localBits);
      if (optimalTokens == null) return null;
      final optimalCost = _lzPixelTokensBitCost(optimalTokens, localBits);
      final greedyCost = _lzPixelTokensBitCost(greedyTokens, localBits);
      if (optimalCost > greedyCost ||
          (optimalCost == greedyCost &&
              _lzPixelTokensEqual(optimalTokens, greedyTokens))) {
        return null;
      }
      tokens = optimalTokens;
    } else {
      tokens = greedyTokens;
    }
    final writer = _BitWriter()
      ..writeBits(ExtendedImageMode.lzPixels.index, _extendedSubmodeBits);
    for (final token in tokens) {
      if (token.isMatch) {
        writer.writeBits(1, 1);
        _writeCompactUint(writer, token.distance - 1);
        _writeCompactUint(writer, token.length - _minLzMatchLength);
      } else {
        writer.writeBits(0, 1);
        _writeCompactUint(writer, token.literals.length - 1);
        for (final color in token.literals) {
          writer.writeBits(color, localBits);
        }
      }
    }
    return _V2BlockPayload(
      writer.toBytes(),
      bitsPerLocalPixel: localBits,
    );
  }

  _V2BlockPayload? _tryBuildV2SharedQuadtreeBlockBody(
    List<int> localPixels,
    int localBits, {
    required int width,
    required int height,
  }) {
    if (localPixels.isEmpty || width <= 0 || height <= 0) return null;
    final writer = _BitWriter()
      ..writeBits(ExtendedImageMode.quadtree.index, _extendedSubmodeBits);
    _writeQuadtreeNode(
      writer,
      localPixels,
      width,
      0,
      0,
      width,
      height,
      localBits,
    );
    return _V2BlockPayload(
      writer.toBytes(),
      bitsPerLocalPixel: localBits,
    );
  }

  _V2BlockPayload? _tryBuildV2SharedCompactRowDeltaBlockBody(
    List<int> localPixels,
    int localBits,
    int rowLength,
  ) {
    if (localPixels.isEmpty || rowLength <= 0) return null;
    final writer = _BitWriter()
      ..writeBits(
        ExtendedImageMode.compactRowDelta.index,
        _extendedSubmodeBits,
      )
      ..writeBits(0, 1);
    _writeCompactRowDeltaBody(
      writer,
      localPixels,
      rowLength,
      localBits,
      directGrayscale: false,
    );
    return _V2BlockPayload(
      writer.toBytes(),
      bitsPerLocalPixel: localBits,
    );
  }

  void _writeV2Header(
    _BitWriter writer, {
    required PaletteProfile profile,
    required int container,
    required ImageMode mode,
    required ScanMode scan,
    required bool boundsPresent,
    required DynamicPaletteReferenceEncoding? referenceEncoding,
    required bool implicitWhiteBackground,
    required int width,
    required int height,
    required bool hasTransparentColor,
    bool sharedFixedRegionsPalette = false,
    bool unalignedExtendedBody = false,
    bool solidBackground = false,
  }) {
    if (container == _containerRegions) {
      if (boundsPresent ||
          (mode != ImageMode.rawGlobal && mode != ImageMode.extended) ||
          scan != ScanMode.h) {
        throw const MCOImageInvalidInputException('Invalid v2 regions header');
      }
    }
    if (solidBackground &&
        (container != _containerBlock ||
            mode != ImageMode.rawGlobal ||
            boundsPresent ||
            (scan != ScanMode.h && scan != ScanMode.v))) {
      throw const MCOImageInvalidInputException('Invalid v2 solid mode');
    }
    if (profile.isFixed && referenceEncoding != null) {
      throw const MCOImageInvalidInputException(
        'Fixed palette cannot use dynamic reference encoding',
      );
    }
    if (sharedFixedRegionsPalette &&
        (!profile.isFixed || container != _containerRegions)) {
      throw const MCOImageInvalidInputException(
        'Shared fixed palette requires fixed regions',
      );
    }
    if (unalignedExtendedBody &&
        (!profile.isFixed ||
            container != _containerBlock ||
            mode != ImageMode.extended)) {
      throw const MCOImageInvalidInputException(
        'Unaligned body requires a fixed extended block',
      );
    }
    if (referenceEncoding == DynamicPaletteReferenceEncoding.banked8x64 &&
        profile != PaletteProfile.dynamicGlobal512) {
      throw const MCOImageInvalidInputException(
        'Banked palette references require dynamicGlobal512',
      );
    }
    final fixedSolidImplicitWhite =
        profile.isFixed &&
        solidBackground;
    final fixedBlockExtension =
        profile.isFixed &&
        container == _containerBlock &&
        !solidBackground &&
        (implicitWhiteBackground || unalignedExtendedBody);
    writer
      ..writeAlignedByte(
        (_v2EncodeVersion << 6) |
            (_modeBits(mode) << 3) |
            (_scanBits(scan) << 1) |
            (boundsPresent ? 0x01 : 0),
      )
      ..writeAlignedByte(
        ((profile.isDynamic ? _paletteKindDynamic : _paletteKindFixed) << 7) |
            ((container == _containerRegions ? 1 : 0) << 6) |
            (((sharedFixedRegionsPalette ||
                            fixedBlockExtension ||
                            fixedSolidImplicitWhite ||
                            referenceEncoding ==
                                DynamicPaletteReferenceEncoding.banked8x64)
                    ? 1
                    : 0) <<
                5) |
            (hasTransparentColor ? _v2TransparentProfileFlag : 0) |
            (profile.isDynamic
                ? (_dynamicProfileId(profile) |
                      (implicitWhiteBackground ? 0x08 : 0))
                : _fixedProfileId(profile)),
      )
      ..writeAlignedByte(width - 1)
      ..writeAlignedByte(height - 1);
    if (fixedBlockExtension) {
      writer.writeBits(
        (implicitWhiteBackground
                ? _v2FixedBlockExtensionImplicitWhite
                : 0) |
            (unalignedExtendedBody
                ? _v2FixedBlockExtensionUnaligned
                : 0),
        2,
      );
    }
  }

  void _writeV2ColorRef(_BitWriter writer, PaletteProfile profile, int color) {
    if (profile.isDynamic) {
      final profileColorId = _profileColorIdForGlobalIndex(profile, color);
      if (profileColorId == null) {
        throw MCOImageInvalidInputException(
          'Color $color is not available in ${profile.name}',
        );
      }
      writer.writeBits(profileColorId, _dynamicProfileColorBits(profile));
      return;
    }
    _validateColor(color, profile, 'color');
    writer.writeBits(color, _globalBits(profile));
  }

  void _writeV2BackgroundRef(
    _BitWriter writer,
    PaletteProfile profile,
    int color,
  ) {
    if (_isImplicitWhiteBackground(profile, color)) return;
    _writeV2ColorRef(writer, profile, color);
  }

  int _readV2BackgroundRef(
    _BitReader reader,
    PaletteProfile profile, {
    required bool implicitWhiteBackground,
  }) {
    if (implicitWhiteBackground) {
      return profile.isDynamic
          ? MCOImageDynamicPalette.whiteGlobalIndexFor(profile)
          : 0;
    }
    return _readV2ColorRef(reader, profile);
  }

  static bool _isImplicitWhiteBackground(
    PaletteProfile profile,
    int color,
  ) =>
      profile.isDynamic
      ? color == MCOImageDynamicPalette.whiteGlobalIndexFor(profile)
      : color == 0;

  int _readV2ColorRef(_BitReader reader, PaletteProfile profile) {
    if (profile.isDynamic) {
      final profileColorId = reader.readBits(_dynamicProfileColorBits(profile));
      if (profileColorId >= _dynamicProfileSize(profile)) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic color id is outside selected profile',
        );
      }
      return _globalIndexForProfileColorId(profile, profileColorId);
    }
    final color = reader.readBits(_globalBits(profile));
    _validateColor(color, profile, 'color', payload: true);
    return color;
  }

  void _writeV2Bounds(_BitWriter writer, _ImageBounds bounds) {
    writer
      ..writeBitVarUint(bounds.x)
      ..writeBitVarUint(bounds.y)
      ..writeBitVarUint(bounds.width)
      ..writeBitVarUint(bounds.height);
  }

  void _writeV2CompactBounds(
    _BitWriter writer,
    _ImageBounds bounds,
    int fullWidth,
    int fullHeight,
  ) {
    if (bounds.area <= 0 ||
        bounds.x < 0 ||
        bounds.y < 0 ||
        bounds.x + bounds.width > fullWidth ||
        bounds.y + bounds.height > fullHeight) {
      throw const MCOImageInvalidInputException('Invalid compact bounds');
    }
    writer
      ..writeBits(bounds.x, _bitsForChoiceCount(fullWidth))
      ..writeBits(bounds.y, _bitsForChoiceCount(fullHeight))
      ..writeBits(
        bounds.width - 1,
        _bitsForChoiceCount(fullWidth - bounds.x),
      )
      ..writeBits(
        bounds.height - 1,
        _bitsForChoiceCount(fullHeight - bounds.y),
      );
  }

  _ImageBounds _readV2CompactBounds(
    _BitReader reader,
    int fullWidth,
    int fullHeight,
  ) {
    final x = reader.readBits(_bitsForChoiceCount(fullWidth));
    final y = reader.readBits(_bitsForChoiceCount(fullHeight));
    if (x >= fullWidth || y >= fullHeight) {
      throw const MCOImageInvalidPayloadException('Invalid compact bounds');
    }
    final width =
        reader.readBits(_bitsForChoiceCount(fullWidth - x)) + 1;
    final height =
        reader.readBits(_bitsForChoiceCount(fullHeight - y)) + 1;
    if (x + width > fullWidth || y + height > fullHeight) {
      throw const MCOImageInvalidPayloadException('Invalid compact bounds');
    }
    return _ImageBounds(x: x, y: y, width: width, height: height);
  }

  _RegionPayload? _tryBuildRegionsPayload(
    MCOImage image,
    int backgroundColor,
    int maxRegions,
  ) {
    if (maxRegions == 0) return null;
    final regions = _findRegions(
      image.pixels,
      image.width,
      image.height,
      backgroundColor,
    );
    if (regions.isEmpty || regions.length > maxRegions) return null;

    final writer = _BitWriter();
    writer.writeAlignedByte(
      (_encodeVersion << 6) |
          (_modeBits(ImageMode.rawGlobal) << 4) |
          (_scanBits(ScanMode.h) << 2) |
          0x02,
    );
    writer.writeAlignedByte(
      (_profileBits(image.paletteProfile) << 4) | _containerRegions,
    );
    writer.writeAlignedByte(image.width - 1);
    writer.writeAlignedByte(image.height - 1);
    writer.writeBits(backgroundColor, _globalBits(image.paletteProfile));
    writer.writeVarUint(regions.length);

    for (final region in regions) {
      final regionPixels = _cropPixels(image.pixels, image.width, region);
      final block = _bestBlockPayload(
        regionPixels,
        region.width,
        region.height,
        image.paletteProfile,
        backgroundColor,
      );
      writer
        ..writeVarUint(region.x)
        ..writeVarUint(region.y)
        ..writeVarUint(region.width)
        ..writeVarUint(region.height)
        ..writeAlignedByte(_modeBits(block.mode))
        ..writeAlignedByte(_scanBits(block.scan))
        ..writeVarUint(block.payload.length)
        ..writeAlignedBytes(block.payload);
    }

    return _RegionPayload(writer.toBytes(), regions.length);
  }

  _BlockPayload _bestBlockPayload(
    List<int> pixels,
    int width,
    int height,
    PaletteProfile profile,
    int backgroundColor,
  ) {
    _BlockPayload? best;
    for (final scan in ScanMode.values) {
      final linear = _toScanOrder(pixels, width, height, scan);
      for (final mode in _blockModes) {
        final writer = _BitWriter();
        _writeBlock(
          writer,
          linear,
          mode,
          profile,
          backgroundColor: backgroundColor,
          writeSparseBackground: false,
        );
        final candidate = _BlockPayload(writer.toBytes(), mode, scan);
        if (best == null ||
            candidate.payload.length < best.payload.length ||
            (candidate.payload.length == best.payload.length &&
                _modeTieOrder.indexOf(candidate.mode) <
                    _modeTieOrder.indexOf(best.mode))) {
          best = candidate;
        }
      }
    }
    return best!;
  }

  static int? decodeHeaderVersion(String text) {
    if (!text.startsWith(prefix)) return null;
    try {
      final bytes = _Base91.decode(text.substring(prefix.length));
      if (bytes.isEmpty) return null;
      return (bytes[0] >> 6) & 0x03;
    } catch (_) {
      return null;
    }
  }

  static MCOImagePayloadInfo? inspectPayload(String text) {
    if (!text.startsWith(prefix)) return null;
    try {
      final bytes = _Base91.decode(text.substring(prefix.length));
      return MCOImageCodec()._inspectPayloadBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  MCOImagePayloadInfo _inspectPayloadBytes(Uint8List bytes) {
    if (bytes.length < 4) {
      throw const MCOImageInvalidPayloadException('Payload too short');
    }
    final header = bytes[0];
    final version = (header >> 6) & 0x03;
    if (version < _minSupportedVersion || version > _maxSupportedVersion) {
      throw MCOImageInvalidPayloadException('Unsupported version $version');
    }

    if (version != _v2EncodeVersion) {
      final mode = _modeFromBits((header >> 4) & 0x03);
      final container = bytes[1] & 0x0f;
      return MCOImagePayloadInfo(
        version: version,
        algorithm: container == _containerRegions
            ? 'Regions'
            : _imageModeLabel(mode),
        binaryLength: bytes.length,
      );
    }

    final mode = _modeFromBits((header >> 3) & 0x07);
    final scan = _scanFromBits((header >> 1) & 0x03);
    final boundsPresent = (header & 0x01) != 0;
    final paletteHeader = bytes[1];
    final container = ((paletteHeader >> 6) & 0x01) == 0
        ? _containerBlock
        : _containerRegions;
    if (container == _containerRegions) {
      return MCOImagePayloadInfo(
        version: version,
        algorithm: 'Regions',
        binaryLength: bytes.length,
      );
    }
    final solidBackground =
        container == _containerBlock &&
        mode == ImageMode.rawGlobal &&
        (((paletteHeader >> 7) & 0x01) == _paletteKindDynamic ||
            ((paletteHeader >> 5) & 0x01) != 0);
    if (solidBackground) {
      return MCOImagePayloadInfo(
        version: version,
        algorithm: 'Solid background',
        binaryLength: bytes.length,
      );
    }
    if (mode != ImageMode.extended) {
      return MCOImagePayloadInfo(
        version: version,
        algorithm: _imageModeLabel(mode),
        binaryLength: bytes.length,
      );
    }

    final paletteKind = (paletteHeader >> 7) & 0x01;
    final referenceEncodingValue = (paletteHeader >> 5) & 0x01;
    final hasTransparentColor =
        (paletteHeader & _v2TransparentProfileFlag) != 0;
    final encodedProfileId = paletteHeader & _v2ProfileIdMask;
    final headerImplicitWhiteBackground =
        (paletteKind == _paletteKindDynamic &&
            (encodedProfileId & 0x08) != 0) ||
        (paletteKind == _paletteKindFixed &&
            container == _containerBlock &&
            mode == ImageMode.rawGlobal &&
            scan == ScanMode.v &&
            referenceEncodingValue != 0);
    final fixedBlockExtension =
        paletteKind == _paletteKindFixed &&
        container == _containerBlock &&
        mode != ImageMode.rawGlobal &&
        referenceEncodingValue != 0;
    final profileId = paletteKind == _paletteKindDynamic
        ? encodedProfileId & 0x07
        : encodedProfileId;
    final profile = paletteKind == _paletteKindDynamic
        ? _dynamicProfileFromId(profileId)
        : _fixedProfileFromId(profileId);
    final width = bytes[2] + 1;
    final height = bytes[3] + 1;
    final reader = _BitReader(bytes, byteIndex: 4);
    var implicitWhiteBackground = headerImplicitWhiteBackground;
    var unalignedExtendedBody = false;
    if (fixedBlockExtension) {
      final extensionFlags = reader.readBits(2);
      implicitWhiteBackground =
          (extensionFlags & _v2FixedBlockExtensionImplicitWhite) != 0;
      unalignedExtendedBody =
          (extensionFlags & _v2FixedBlockExtensionUnaligned) != 0;
    }
    if (hasTransparentColor) _readV2ColorRef(reader, profile);
    if (boundsPresent) {
      _readV2BackgroundRef(
        reader,
        profile,
        implicitWhiteBackground: implicitWhiteBackground,
      );
      _readV2CompactBounds(reader, width, height);
    }
    if (!unalignedExtendedBody) reader.alignToByte();
    final submode = reader.readBits(_extendedSubmodeBits);
    final algorithm = submode == ExtendedImageMode.wrappedBlock.index
        ? _imageModeLabel(_modeFromBits(reader.readBits(3)))
        : _extendedImageModeLabel(submode);
    return MCOImagePayloadInfo(
      version: version,
      algorithm: algorithm,
      binaryLength: bytes.length,
    );
  }

  static String _imageModeLabel(ImageMode mode) {
    return switch (mode) {
      ImageMode.rawGlobal => 'Raw global',
      ImageMode.rawLocal => 'Raw local',
      ImageMode.rleLocal => 'RLE local',
      ImageMode.sparseBg => 'Sparse background',
      ImageMode.regionsBg => 'Regions',
      ImageMode.biColorMask => 'Bi-color mask',
      ImageMode.rowDelta => 'Row delta',
      ImageMode.rowRepeat => 'Row repeat',
      ImageMode.extended => 'Extended',
    };
  }

  static String _extendedImageModeLabel(int submode) {
    if (submode < 0 || submode >= ExtendedImageMode.values.length) {
      return 'Extended';
    }
    return switch (ExtendedImageMode.values[submode]) {
      ExtendedImageMode.wrappedBlock => 'Wrapped block',
      ExtendedImageMode.solidRects => 'Solid rectangles',
      ExtendedImageMode.compactRle => 'Compact RLE',
      ExtendedImageMode.compactSparse => 'Compact sparse',
      ExtendedImageMode.lzPixels => 'LZ pixels',
      ExtendedImageMode.quadtree => 'Quadtree',
      ExtendedImageMode.bitplanes => 'Bitplanes',
      ExtendedImageMode.compactRowDelta => 'Compact row delta',
    };
  }

  static Uint8List binaryPayloadFromText(String text) {
    if (!text.startsWith(prefix)) {
      throw const MCOImageInvalidPayloadException('Missing im: prefix');
    }
    return _Base91.decode(text.substring(prefix.length));
  }

  static String textFromBinaryPayload(Uint8List payload) {
    return '$prefix${_Base91.encode(payload)}';
  }

  MCOImage decode(String text) {
    if (!text.startsWith(prefix)) {
      throw const MCOImageInvalidPayloadException('Missing im: prefix');
    }

    final bytes = _Base91.decode(text.substring(prefix.length));
    if (bytes.length < 4) {
      throw const MCOImageInvalidPayloadException('Payload too short');
    }

    final header = bytes[0];
    final version = (header >> 6) & 0x03;
    if (version < _minSupportedVersion || version > _maxSupportedVersion) {
      throw MCOImageInvalidPayloadException('Unsupported version $version');
    }
    if (version == _v2EncodeVersion) {
      return _decodeVersion2(bytes, header);
    }

    final mode = _modeFromBits((header >> 4) & 0x03);
    final scan = _scanFromBits((header >> 2) & 0x03);
    final bgPresent = ((header >> 1) & 0x01) != 0;
    final boundsPresent = version >= 1 && (header & 0x01) != 0;
    if (version == 0 && (header & 0x01) != 0) {
      throw const MCOImageInvalidPayloadException('Reserved header bit is set');
    }
    final profileHeader = bytes[1];
    final profile = _profileFromBits((profileHeader >> 4) & 0x0f);
    final container = version >= 1 ? profileHeader & 0x0f : _containerBlock;
    if (version == 0 && (profileHeader & 0x0f) != 0) {
      throw const MCOImageInvalidPayloadException(
        'Reserved palette bits are set',
      );
    }
    if (container != _containerBlock && container != _containerRegions) {
      throw const MCOImageInvalidPayloadException('Unknown image container');
    }
    if (container == _containerBlock &&
        bgPresent != (mode == ImageMode.sparseBg)) {
      throw const MCOImageInvalidPayloadException(
        'Background flag does not match mode',
      );
    }

    final width = bytes[2] + 1;
    final height = bytes[3] + 1;
    _validateDimensions(width, height, payload: true);

    final reader = _BitReader(bytes, byteIndex: 4);
    if (container == _containerRegions) {
      if (!bgPresent || boundsPresent) {
        throw const MCOImageInvalidPayloadException('Invalid regions header');
      }
      final pixels = _decodeRegions(reader, width, height, profile);
      reader.finish();
      return MCOImage(
        width: width,
        height: height,
        paletteProfile: profile,
        pixels: pixels,
        encodingVersion: MCOImageEncodingVersion.v1Legacy,
      );
    }

    if (boundsPresent) {
      final background = reader.readBits(_globalBits(profile));
      _validateColor(background, profile, 'backgroundColor', payload: true);
      final bounds = _readBounds(reader, width, height);
      if (bounds.area == 0) {
        reader.finish();
        return MCOImage(
          width: width,
          height: height,
          paletteProfile: profile,
          pixels: List<int>.filled(width * height, background),
          encodingVersion: MCOImageEncodingVersion.v1Legacy,
        );
      }

      final croppedLinear = _decodeBody(
        reader,
        bounds.width,
        bounds.height,
        profile,
        mode,
        sparseBackgroundColor: background,
      );
      reader.finish();
      final cropped = _fromScanOrder(
        croppedLinear,
        bounds.width,
        bounds.height,
        scan,
      );
      return MCOImage(
        width: width,
        height: height,
        paletteProfile: profile,
        pixels: _insertBounds(width, height, background, cropped, bounds),
        encodingVersion: MCOImageEncodingVersion.v1Legacy,
      );
    }

    final linear = _decodeBody(reader, width, height, profile, mode);
    reader.finish();

    return MCOImage(
      width: width,
      height: height,
      paletteProfile: profile,
      pixels: _fromScanOrder(linear, width, height, scan),
      encodingVersion: MCOImageEncodingVersion.v1Legacy,
    );
  }

  MCOImage _decodeVersion2(Uint8List bytes, int header) {
    if (bytes.length < 4) {
      throw const MCOImageInvalidPayloadException('Payload too short');
    }

    final modeBits = (header >> 3) & 0x07;
    final mode = _modeFromBits(modeBits);
    final scan = _scanFromBits((header >> 1) & 0x03);
    final boundsPresent = (header & 0x01) != 0;
    final paletteHeader = bytes[1];
    final paletteKind = (paletteHeader >> 7) & 0x01;
    final container = ((paletteHeader >> 6) & 0x01) == 0
        ? _containerBlock
        : _containerRegions;
    final referenceEncodingValue = (paletteHeader >> 5) & 0x01;
    final hasTransparentColor =
        (paletteHeader & _v2TransparentProfileFlag) != 0;
    final encodedProfileId = paletteHeader & _v2ProfileIdMask;
    final headerImplicitWhiteBackground =
        (paletteKind == _paletteKindDynamic &&
            (encodedProfileId & 0x08) != 0) ||
        (paletteKind == _paletteKindFixed &&
            container == _containerBlock &&
            mode == ImageMode.rawGlobal &&
            scan == ScanMode.v &&
            referenceEncodingValue != 0);
    final fixedBlockExtension =
        paletteKind == _paletteKindFixed &&
        container == _containerBlock &&
        mode != ImageMode.rawGlobal &&
        referenceEncodingValue != 0;
    final profileId = paletteKind == _paletteKindDynamic
        ? encodedProfileId & 0x07
        : encodedProfileId;
    if (paletteKind != _paletteKindFixed &&
        paletteKind != _paletteKindDynamic) {
      throw const MCOImageInvalidPayloadException(
        'Unsupported v2 palette kind',
      );
    }
    final profile = paletteKind == _paletteKindDynamic
        ? _dynamicProfileFromId(profileId)
        : _fixedProfileFromId(profileId);
    final referenceEncoding = paletteKind == _paletteKindDynamic
        ? _dynamicReferenceEncodingFromBits(referenceEncodingValue)
        : null;
    final sharedFixedRegionsPalette =
        paletteKind == _paletteKindFixed &&
        container == _containerRegions &&
        referenceEncodingValue != 0;
    if (paletteKind == _paletteKindFixed &&
        referenceEncodingValue != 0 &&
        container != _containerBlock &&
        !sharedFixedRegionsPalette) {
      throw const MCOImageInvalidPayloadException(
        'Fixed palette cannot use dynamic reference encoding',
      );
    }
    if (referenceEncoding == DynamicPaletteReferenceEncoding.banked8x64 &&
        profile != PaletteProfile.dynamicGlobal512) {
      throw const MCOImageInvalidPayloadException(
        'Banked palette references require dynamicGlobal512',
      );
    }
    final solidBackground =
        container == _containerBlock &&
        mode == ImageMode.rawGlobal &&
        (profile.isDynamic || referenceEncodingValue != 0);
    if (container == _containerRegions) {
      final compactGeometry = mode == ImageMode.extended;
      if (boundsPresent ||
          (mode != ImageMode.rawGlobal && !compactGeometry) ||
          scan != ScanMode.h) {
        throw const MCOImageInvalidPayloadException(
          'Invalid v2 regions header',
        );
      }
      final width = bytes[2] + 1;
      final height = bytes[3] + 1;
      _validateDimensions(width, height, payload: true);
      final reader = _BitReader(bytes, byteIndex: 4);
      final transparentColor = hasTransparentColor
          ? _readV2ColorRef(reader, profile)
          : null;
      final pixels = _decodeV2Regions(
        reader,
        width,
        height,
        profile,
        referenceEncoding,
        compactGeometry: compactGeometry,
        implicitWhiteBackground: headerImplicitWhiteBackground,
        sharedFixedPalette: sharedFixedRegionsPalette,
      );
      reader.finish();
      return MCOImage(
        width: width,
        height: height,
        paletteProfile: profile,
        pixels: pixels,
        transparentColor: transparentColor,
        encodingVersion: MCOImageEncodingVersion.v2,
      );
    }

    final width = bytes[2] + 1;
    final height = bytes[3] + 1;
    _validateDimensions(width, height, payload: true);
    final reader = _BitReader(bytes, byteIndex: 4);
    var implicitWhiteBackground = headerImplicitWhiteBackground;
    var unalignedExtendedBody = false;
    if (fixedBlockExtension) {
      final extensionFlags = reader.readBits(2);
      implicitWhiteBackground =
          (extensionFlags & _v2FixedBlockExtensionImplicitWhite) != 0;
      unalignedExtendedBody =
          (extensionFlags & _v2FixedBlockExtensionUnaligned) != 0;
      if (unalignedExtendedBody && mode != ImageMode.extended) {
        throw const MCOImageInvalidPayloadException(
          'Unaligned flag requires an extended block',
        );
      }
    }
    final transparentColor = hasTransparentColor
        ? _readV2ColorRef(reader, profile)
        : null;

    if (solidBackground) {
      final background = _readV2BackgroundRef(
        reader,
        profile,
        implicitWhiteBackground: implicitWhiteBackground,
      );
      reader.finish();
      return MCOImage(
        width: width,
        height: height,
        paletteProfile: profile,
        pixels: List<int>.filled(width * height, background),
        transparentColor: transparentColor,
        encodingVersion: MCOImageEncodingVersion.v2,
      );
    }

    if (boundsPresent) {
      final background = _readV2BackgroundRef(
        reader,
        profile,
        implicitWhiteBackground: implicitWhiteBackground,
      );
      final bounds = mode == ImageMode.extended
          ? _readV2CompactBounds(reader, width, height)
          : _readV2Bounds(reader, width, height);
      if (bounds.area == 0) {
        reader.finish();
        return MCOImage(
          width: width,
          height: height,
          paletteProfile: profile,
          pixels: List<int>.filled(width * height, background),
          transparentColor: transparentColor,
          encodingVersion: MCOImageEncodingVersion.v2,
        );
      }
      if (!unalignedExtendedBody) reader.alignToByte();
      final croppedLinear = _decodeV2Body(
        reader,
        bounds.width,
        bounds.height,
        profile,
        mode,
        referenceEncoding,
        rowLength: _rowLengthForScan(scan, bounds.width, bounds.height),
        sparseBackgroundColor: background,
        unalignedExtendedBody: unalignedExtendedBody,
      );
      reader.finish();
      final cropped = _fromScanOrder(
        croppedLinear,
        bounds.width,
        bounds.height,
        scan,
      );
      return MCOImage(
        width: width,
        height: height,
        paletteProfile: profile,
        pixels: _insertBounds(width, height, background, cropped, bounds),
        transparentColor: transparentColor,
        encodingVersion: MCOImageEncodingVersion.v2,
      );
    }

    final implicitBackground = implicitWhiteBackground
        ? (profile.isDynamic
              ? MCOImageDynamicPalette.whiteGlobalIndexFor(profile)
              : 0)
        : null;
    if (!unalignedExtendedBody) reader.alignToByte();
    final linear = _decodeV2Body(
      reader,
      width,
      height,
      profile,
      mode,
      referenceEncoding,
      rowLength: _rowLengthForScan(scan, width, height),
      sparseBackgroundColor: implicitBackground,
      unalignedExtendedBody: unalignedExtendedBody,
    );
    reader.finish();
    return MCOImage(
      width: width,
      height: height,
      paletteProfile: profile,
      pixels: _fromScanOrder(linear, width, height, scan),
      transparentColor: transparentColor,
      encodingVersion: MCOImageEncodingVersion.v2,
    );
  }

  List<int> _decodeBody(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
    ImageMode mode, {
    int? sparseBackgroundColor,
  }) {
    return switch (mode) {
      ImageMode.rawGlobal => _decodeRawGlobal(reader, width, height, profile),
      ImageMode.rawLocal => _decodeRawLocal(reader, width, height, profile),
      ImageMode.rleLocal => _decodeRleLocal(reader, width, height, profile),
      ImageMode.sparseBg => _decodeSparseBg(
        reader,
        width,
        height,
        profile,
        backgroundColor: sparseBackgroundColor,
      ),
      ImageMode.biColorMask => throw const MCOImageInvalidPayloadException(
        'BI_COLOR_MASK is not supported by legacy block bodies',
      ),
      ImageMode.rowDelta => throw const MCOImageInvalidPayloadException(
        'ROW_DELTA is not supported by legacy block bodies',
      ),
      ImageMode.rowRepeat => throw const MCOImageInvalidPayloadException(
        'ROW_REPEAT is not supported by legacy block bodies',
      ),
      ImageMode.extended => throw const MCOImageInvalidPayloadException(
        'EXTENDED is not supported by legacy block bodies',
      ),
      ImageMode.regionsBg => throw const MCOImageInvalidPayloadException(
        'REGIONS_BG is not a block body mode',
      ),
    };
  }

  List<int> _decodeV2Body(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
    ImageMode mode,
    DynamicPaletteReferenceEncoding? referenceEncoding, {
    required int rowLength,
    int? sparseBackgroundColor,
    bool unalignedExtendedBody = false,
  }) {
    if (mode == ImageMode.extended) {
      final submode = reader.readBits(_extendedSubmodeBits);
      if (submode == ExtendedImageMode.solidRects.index) {
        return _decodeV2SolidRects(
          reader,
          width,
          height,
          profile,
          referenceEncoding,
          backgroundColor: sparseBackgroundColor,
        );
      }
      if (submode == ExtendedImageMode.compactRle.index) {
        return _decodeV2CompactRle(
          reader,
          width,
          height,
          profile,
          referenceEncoding,
        );
      }
      if (submode == ExtendedImageMode.compactSparse.index) {
        return _decodeV2CompactSparse(
          reader,
          width,
          height,
          profile,
          referenceEncoding,
          backgroundColor: sparseBackgroundColor,
        );
      }
      if (submode == ExtendedImageMode.lzPixels.index) {
        return _decodeV2LzPixels(
          reader,
          width,
          height,
          profile,
          referenceEncoding,
        );
      }
      if (submode == ExtendedImageMode.quadtree.index) {
        return _decodeV2Quadtree(
          reader,
          width,
          height,
          profile,
          referenceEncoding,
        );
      }
      if (submode == ExtendedImageMode.bitplanes.index) {
        return _decodeV2Bitplanes(
          reader,
          width,
          height,
          profile,
          referenceEncoding,
        );
      }
      if (submode == ExtendedImageMode.compactRowDelta.index) {
        return _decodeV2CompactRowDelta(
          reader,
          width,
          height,
          profile,
          referenceEncoding,
          rowLength,
        );
      }
      if (submode != ExtendedImageMode.wrappedBlock.index) {
        throw MCOImageInvalidPayloadException(
          'Unsupported extended image submode $submode',
        );
      }
      final innerMode = _modeFromBits(reader.readBits(3));
      if (innerMode == ImageMode.extended ||
          innerMode == ImageMode.regionsBg) {
        throw const MCOImageInvalidPayloadException(
          'Invalid wrapped image mode',
        );
      }
      if (!unalignedExtendedBody) reader.alignToByte();
      return _decodeV2Body(
        reader,
        width,
        height,
        profile,
        innerMode,
        referenceEncoding,
        rowLength: rowLength,
        sparseBackgroundColor: sparseBackgroundColor,
        unalignedExtendedBody: unalignedExtendedBody,
      );
    }
    if (profile.isDynamic) {
      if (referenceEncoding == null) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic v2 block is missing reference encoding',
        );
      }
      return _decodeV2DynamicBody(
        reader,
        width,
        height,
        profile,
        mode,
        referenceEncoding,
        rowLength: rowLength,
        sparseBackgroundColor: sparseBackgroundColor,
      );
    }

    final count = width * height;
    switch (mode) {
      case ImageMode.rawGlobal:
        return _decodeRawGlobal(reader, width, height, profile);
      case ImageMode.rawLocal:
        final palette = _readV2LocalPalette(reader, profile);
        final localBits = _localBits(palette.length);
        return List<int>.generate(count, (_) {
          final index = reader.readBits(localBits);
          if (index >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'Local color index out of range',
            );
          }
          return palette[index];
        });
      case ImageMode.rleLocal:
        final palette = _readV2LocalPalette(reader, profile);
        final localBits = _localBits(palette.length);
        final runCount = reader.readBitVarUint();
        final result = <int>[];
        for (var i = 0; i < runCount; i++) {
          final index = reader.readBits(localBits);
          if (index >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'RLE local color index out of range',
            );
          }
          final length = reader.readBitVarUint();
          if (length <= 0 || result.length + length > count) {
            throw const MCOImageInvalidPayloadException('Invalid RLE length');
          }
          result.addAll(List<int>.filled(length, palette[index]));
        }
        if (result.length != count) {
          throw const MCOImageInvalidPayloadException(
            'RLE data does not fill canvas',
          );
        }
        return result;
      case ImageMode.sparseBg:
        final bg = sparseBackgroundColor ?? _readV2ColorRef(reader, profile);
        final palette = _readV2LocalPalette(reader, profile, excludedColor: bg);
        final localBits = _localBits(palette.length);
        final segmentCount = reader.readBitVarUint();
        final result = List<int>.filled(count, bg);
        var pos = 0;
        for (var i = 0; i < segmentCount; i++) {
          final skip = reader.readBitVarUint();
          pos += skip;
          final index = reader.readBits(localBits);
          if (index >= palette.length) {
            throw const MCOImageInvalidPayloadException(
              'Sparse local color index out of range',
            );
          }
          final length = reader.readBitVarUint();
          if (length <= 0 || pos + length > count) {
            throw const MCOImageInvalidPayloadException(
              'Invalid sparse segment',
            );
          }
          for (var j = 0; j < length; j++) {
            result[pos + j] = palette[index];
          }
          pos += length;
        }
        return result;
      case ImageMode.rowRepeat:
        final palette = _readV2LocalPalette(reader, profile);
        final localBits = _localBits(palette.length);
        final localPixels = _readRowRepeatBody(
          reader,
          count,
          rowLength,
          localBits,
        );
        return localPixels
            .map((index) {
              if (index >= palette.length) {
                throw const MCOImageInvalidPayloadException(
                  'Row-repeat local color index out of range',
                );
              }
              return palette[index];
            })
            .toList(growable: false);
      case ImageMode.rowDelta:
        final palette = _readV2LocalPalette(reader, profile);
        final localBits = _localBits(palette.length);
        final localPixels = _readRowDeltaBody(
          reader,
          count,
          rowLength,
          localBits,
        );
        return localPixels
            .map((index) {
              if (index >= palette.length) {
                throw const MCOImageInvalidPayloadException(
                  'Row-delta local color index out of range',
                );
              }
              return palette[index];
            })
            .toList(growable: false);
      case ImageMode.biColorMask:
        final background =
            sparseBackgroundColor ?? _readV2ColorRef(reader, profile);
        final foreground = _readV2ColorRef(reader, profile);
        if (foreground == background) {
          throw const MCOImageInvalidPayloadException(
            'Bi-color foreground equals background',
          );
        }
        return _readBiColorMask(reader, count, background, foreground);
      case ImageMode.extended:
      case ImageMode.regionsBg:
        throw const MCOImageInvalidPayloadException(
          'REGIONS_BG is not a block body mode',
        );
    }
  }

  List<int> _decodeV2SolidRects(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
    DynamicPaletteReferenceEncoding? referenceEncoding, {
    int? backgroundColor,
  }) {
    final background = backgroundColor ?? _readV2ColorRef(reader, profile);
    final List<int> palette;
    if (profile.isDynamic) {
      if (referenceEncoding == null) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic solid rectangles are missing reference encoding',
        );
      }
      palette = _readDynamicLocalPalette(
        reader,
        profile,
        referenceEncoding,
      ).globalColors;
      if (palette.contains(background)) {
        throw const MCOImageInvalidPayloadException(
          'Solid rectangle palette contains background',
        );
      }
    } else {
      palette = _readV2LocalPalette(
        reader,
        profile,
        excludedColor: background,
      );
    }
    final localBits = _localBits(palette.length);
    final rectCount = reader.readBitVarUint();
    if (rectCount <= 0 || rectCount > 64) {
      throw const MCOImageInvalidPayloadException(
        'Invalid solid rectangle count',
      );
    }
    final result = List<int>.filled(width * height, background);
    final occupied = List<bool>.filled(width * height, false);
    for (var i = 0; i < rectCount; i++) {
      final bounds = _readV2CompactBounds(reader, width, height);
      final colorIndex = reader.readBits(localBits);
      if (colorIndex >= palette.length) {
        throw const MCOImageInvalidPayloadException(
          'Solid rectangle color index out of range',
        );
      }
      for (var y = bounds.y; y < bounds.y + bounds.height; y++) {
        for (var x = bounds.x; x < bounds.x + bounds.width; x++) {
          final pixelIndex = y * width + x;
          if (occupied[pixelIndex]) {
            throw const MCOImageInvalidPayloadException(
              'Overlapping solid rectangles',
            );
          }
          occupied[pixelIndex] = true;
          result[pixelIndex] = palette[colorIndex];
        }
      }
    }
    return result;
  }

  List<int> _decodeV2CompactRle(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
    DynamicPaletteReferenceEncoding? referenceEncoding,
  ) {
    final List<int> palette;
    if (profile.isDynamic) {
      if (referenceEncoding == null) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic compact RLE is missing reference encoding',
        );
      }
      palette = _readDynamicLocalPalette(
        reader,
        profile,
        referenceEncoding,
      ).globalColors;
    } else {
      palette = _readV2LocalPalette(reader, profile);
    }
    final localBits = _localBits(palette.length);
    final pixelCount = width * height;
    final result = <int>[];
    while (result.length < pixelCount) {
      final colorIndex = reader.readBits(localBits);
      if (colorIndex >= palette.length) {
        throw const MCOImageInvalidPayloadException(
          'Compact RLE color index out of range',
        );
      }
      final length = _readCompactUint(reader) + 1;
      if (result.length + length > pixelCount) {
        throw const MCOImageInvalidPayloadException(
          'Compact RLE exceeds pixel count',
        );
      }
      result.addAll(List<int>.filled(length, palette[colorIndex]));
    }
    return result;
  }

  List<int> _decodeV2CompactSparse(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
    DynamicPaletteReferenceEncoding? referenceEncoding, {
    int? backgroundColor,
  }) {
    final background =
        backgroundColor ?? _readV2ColorRef(reader, profile);
    final List<int> palette;
    if (profile.isDynamic) {
      if (referenceEncoding == null) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic compact sparse is missing reference encoding',
        );
      }
      palette = _readDynamicLocalPalette(
        reader,
        profile,
        referenceEncoding,
      ).globalColors;
      if (palette.contains(background)) {
        throw const MCOImageInvalidPayloadException(
          'Compact sparse palette contains background',
        );
      }
    } else {
      palette = _readV2LocalPalette(
        reader,
        profile,
        excludedColor: background,
      );
    }

    final pixelCount = width * height;
    final segmentCount = _readCompactUint(reader) + 1;
    if (segmentCount <= 0 || segmentCount > pixelCount) {
      throw const MCOImageInvalidPayloadException(
        'Invalid compact sparse segment count',
      );
    }
    final localBits = _localBits(palette.length);
    final result = List<int>.filled(pixelCount, background);
    var pos = 0;
    for (var i = 0; i < segmentCount; i++) {
      final skip = _readCompactUint(reader);
      pos += skip;
      final colorIndex = reader.readBits(localBits);
      if (colorIndex >= palette.length) {
        throw const MCOImageInvalidPayloadException(
          'Compact sparse color index out of range',
        );
      }
      final length = _readCompactUint(reader) + 1;
      if (pos >= pixelCount || pos + length > pixelCount) {
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
  }

  List<int> _decodeV2LzPixels(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
    DynamicPaletteReferenceEncoding? referenceEncoding,
  ) {
    final List<int> palette;
    if (profile.isDynamic) {
      if (referenceEncoding == null) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic LZ pixels are missing reference encoding',
        );
      }
      palette = _readDynamicLocalPalette(
        reader,
        profile,
        referenceEncoding,
      ).globalColors;
    } else {
      palette = _readV2LocalPalette(reader, profile);
    }

    final pixelCount = width * height;
    final localBits = _localBits(palette.length);
    final result = <int>[];
    while (result.length < pixelCount) {
      final isMatch = reader.readBits(1) != 0;
      if (isMatch) {
        final distance = _readCompactUint(reader) + 1;
        final length =
            _readCompactUint(reader) + _minLzMatchLength;
        if (distance <= 0 ||
            distance > result.length ||
            result.length + length > pixelCount) {
          throw const MCOImageInvalidPayloadException(
            'Invalid LZ pixel match',
          );
        }
        for (var i = 0; i < length; i++) {
          result.add(result[result.length - distance]);
        }
      } else {
        final length = _readCompactUint(reader) + 1;
        if (result.length + length > pixelCount) {
          throw const MCOImageInvalidPayloadException(
            'Invalid LZ pixel literal length',
          );
        }
        for (var i = 0; i < length; i++) {
          final colorIndex = reader.readBits(localBits);
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
  }

  List<int> _decodeV2Quadtree(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
    DynamicPaletteReferenceEncoding? referenceEncoding,
  ) {
    final List<int> palette;
    if (profile.isDynamic) {
      if (referenceEncoding == null) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic quadtree is missing reference encoding',
        );
      }
      palette = _readDynamicLocalPalette(
        reader,
        profile,
        referenceEncoding,
      ).globalColors;
    } else {
      palette = _readV2LocalPalette(reader, profile);
    }

    final result = List<int>.filled(width * height, palette.first);
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
  }

  void _readQuadtreeNode(
    _BitReader reader,
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
    for (final child in <_ImageBounds>[
      _ImageBounds(x: x, y: y, width: leftWidth, height: topHeight),
      _ImageBounds(
        x: x + leftWidth,
        y: y,
        width: width - leftWidth,
        height: topHeight,
      ),
      _ImageBounds(
        x: x,
        y: y + topHeight,
        width: leftWidth,
        height: height - topHeight,
      ),
      _ImageBounds(
        x: x + leftWidth,
        y: y + topHeight,
        width: width - leftWidth,
        height: height - topHeight,
      ),
    ]) {
      _readQuadtreeNode(
        reader,
        pixels,
        stride,
        child.x,
        child.y,
        child.width,
        child.height,
        palette,
        localBits,
      );
    }
  }

  List<int> _decodeV2Bitplanes(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
    DynamicPaletteReferenceEncoding? referenceEncoding,
  ) {
    final paletteMarker = reader.readBits(8);
    if (paletteMarker == 0 && profile.isFixed) {
      final palette = _readV2FixedPaletteDescriptor(reader, profile);
      return _decodeLegacyBitplanesBody(reader, width, height, palette);
    }
    if (paletteMarker == 0 && profile.isDynamic) {
      final palette = _readExtendedDynamicLocalPalette(
        reader,
        profile,
      ).globalColors;
      return _decodeLegacyBitplanesBody(reader, width, height, palette);
    }
    if (paletteMarker >= 1 && paletteMarker <= 64) {
      final palette = _readBitplanesPaletteBody(
        reader,
        profile,
        referenceEncoding,
        paletteMarker,
      );
      return _decodeLegacyBitplanesBody(reader, width, height, palette);
    }
    if ((paletteMarker & 0xc0) == 0x80) {
      final palette = _readBitplanesPaletteBody(
        reader,
        profile,
        referenceEncoding,
        (paletteMarker & 0x3f) + 1,
      );
      return _decodeAdaptiveBitplanesBody(reader, width, height, palette);
    }
    if (paletteMarker == 0xc0) {
      if (_isGrayscaleProfile(profile)) {
        return _decodeAdaptiveBitplanesBody(
          reader,
          width,
          height,
          List<int>.generate(_paletteSize(profile), (index) => index),
        );
      }
      if (profile.isDynamic) {
        return _decodeAdaptiveBitplanesBody(
          reader,
          width,
          height,
          MCOImageDynamicPalette.indicesFor(profile),
        );
      }
    }
    throw const MCOImageInvalidPayloadException(
      'Invalid Bitplanes palette marker',
    );
  }

  List<int> _readBitplanesPaletteBody(
    _BitReader reader,
    PaletteProfile profile,
    DynamicPaletteReferenceEncoding? referenceEncoding,
    int length,
  ) {
    if (profile.isDynamic) {
      if (referenceEncoding == null) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic bitplanes are missing reference encoding',
        );
      }
      return _readDynamicLocalPaletteBody(
        reader,
        profile,
        referenceEncoding,
        length,
      ).globalColors;
    }
    return _readV2LocalPaletteBody(reader, profile, length);
  }

  List<int> _decodeLegacyBitplanesBody(
    _BitReader reader,
    int width,
    int height,
    List<int> palette,
  ) {
    final pixelCount = width * height;
    final localBits = _localBits(palette.length);
    final localPixels = List<int>.filled(pixelCount, 0);
    for (var bit = 0; bit < localBits; bit++) {
      final isRle = reader.readBits(1) != 0;
      if (!isRle) {
        for (var i = 0; i < pixelCount; i++) {
          localPixels[i] |= reader.readBits(1) << bit;
        }
        continue;
      }

      var value = reader.readBits(1);
      var position = 0;
      while (position < pixelCount) {
        final length = _readCompactUint(reader) + 1;
        if (position + length > pixelCount) {
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
  }

  List<int> _decodeAdaptiveBitplanesBody(
    _BitReader reader,
    int width,
    int height,
    List<int> palette,
  ) {
    final pixelCount = width * height;
    final localBits = _localBits(palette.length);
    final localPixels = List<int>.filled(pixelCount, 0);
    for (var bit = 0; bit < localBits; bit++) {
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

  void _readAdaptiveBitplaneRuns(
    _BitReader reader,
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
          : _readCompactUint(reader) + 1;
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

  void _readSparseBitplane(
    _BitReader reader,
    List<int> pixels,
    int bit,
    int pixelCount, {
    required int minorityBit,
  }) {
    final count = _readCompactUint(reader) + 1;
    if (count > pixelCount) {
      throw const MCOImageInvalidPayloadException(
        'Sparse bitplane count exceeds pixel count',
      );
    }
    var previous = -1;
    for (var i = 0; i < count; i++) {
      final gap = _readCompactUint(reader);
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

  List<int> _decodeV2CompactRowDelta(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
    DynamicPaletteReferenceEncoding? referenceEncoding,
    int rowLength,
  ) {
    final directGrayscale = reader.readBits(1) != 0;
    if (directGrayscale && !_isGrayscaleProfile(profile)) {
      throw const MCOImageInvalidPayloadException(
        'Direct row-delta levels require a grayscale palette',
      );
    }

    List<int>? palette;
    final int valueBits;
    if (directGrayscale) {
      valueBits = _globalBits(profile);
    } else if (profile.isDynamic) {
      if (referenceEncoding == null) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic compact row-delta is missing reference encoding',
        );
      }
      palette = _readDynamicLocalPalette(
        reader,
        profile,
        referenceEncoding,
      ).globalColors;
      valueBits = _localBits(palette.length);
    } else {
      palette = _readV2LocalPalette(reader, profile);
      valueBits = _localBits(palette.length);
    }

    final maxValue = directGrayscale
        ? _paletteSize(profile) - 1
        : palette!.length - 1;
    final localValues = _readCompactRowDeltaBody(
      reader,
      width * height,
      rowLength,
      valueBits,
      directGrayscale: directGrayscale,
      maxValue: maxValue,
    );
    if (directGrayscale) return localValues;
    return localValues.map((value) => palette![value]).toList(growable: false);
  }

  List<int> _readCompactRowDeltaBody(
    _BitReader reader,
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
    final rowCount = count ~/ rowLength;
    var row = useVirtualBaseRow ? 0 : 1;
    if (!useVirtualBaseRow) {
      for (var x = 0; x < rowLength; x++) {
        final value = reader.readBits(valueBits);
        if (value > maxValue) {
          throw const MCOImageInvalidPayloadException(
            'Compact row-delta value out of range',
          );
        }
        result[x] = value;
      }
    }

    while (row < rowCount) {
      final op = reader.readBits(_compactRowDeltaOpBits);
      if (op == _compactRowDeltaOpRepeat ||
          op == _compactRowDeltaOpRepeatRun) {
        final repeatCount = op == _compactRowDeltaOpRepeat
            ? 1
            : _readCompactUint(reader) + 2;
        if (row + repeatCount > rowCount) {
          throw const MCOImageInvalidPayloadException(
            'Compact row-delta repeat exceeds row count',
          );
        }
        for (var i = 0; i < repeatCount; i++) {
          _copyRowDeltaPredictedRow(
            result,
            row * rowLength,
            row * rowLength - rowLength,
            row,
            rowLength,
            useVirtualBaseRow: useVirtualBaseRow,
            predictor: _rowDeltaPredictorSame,
          );
          row++;
        }
        continue;
      }
      if (op == _compactRowDeltaOpRaw) {
        final rowStart = row * rowLength;
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
      final rowStart = row * rowLength;
      _copyRowDeltaPredictedRow(
        result,
        rowStart,
        rowStart - rowLength,
        row,
        rowLength,
        useVirtualBaseRow: useVirtualBaseRow,
        predictor: predictor,
      );
      if (op == _compactRowDeltaOpPredicted) {
        row++;
        continue;
      }
      final useResidual = directGrayscale && reader.readBits(1) != 0;
      final positions = <int>[];
      if (op == _compactRowDeltaOpIndexed ||
          op == _compactRowDeltaOpSameScalar) {
        final changeCount = _readCompactUint(reader) + 1;
        if (changeCount > rowLength) {
          throw const MCOImageInvalidPayloadException(
            'Compact row-delta change count exceeds row length',
          );
        }
        _readCompactChangePositions(reader, positions, changeCount, rowLength);
      } else if (op == _compactRowDeltaOpSegments) {
        final segmentCount = _readCompactUint(reader) + 1;
        if (segmentCount > rowLength) {
          throw const MCOImageInvalidPayloadException(
            'Compact row-delta segment count exceeds row length',
          );
        }
        var previousEnd = 0;
        for (var i = 0; i < segmentCount; i++) {
          final gap = _readCompactUint(reader);
          final start = (i == 0 ? 0 : previousEnd) + gap;
          final length = _readCompactUint(reader) + 1;
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
      } else if (op == _compactRowDeltaOpTrimmedMask) {
        final start = _readCompactUint(reader);
        final span = _readCompactUint(reader) + 1;
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
      } else {
        throw const MCOImageInvalidPayloadException(
          'Unknown compact row-delta op',
        );
      }

      if (op == _compactRowDeltaOpSameScalar) {
        final encoded = useResidual
            ? _readCompactUint(reader) + 1
            : reader.readBits(valueBits);
        for (final x in positions) {
          result[rowStart + x] = _decodeCompactRowDeltaValue(
            encoded,
            result[rowStart + x],
            useResidual: useResidual,
            maxValue: maxValue,
          );
        }
      } else {
        for (final x in positions) {
          final encoded = useResidual
              ? _readCompactUint(reader) + 1
              : reader.readBits(valueBits);
          result[rowStart + x] = _decodeCompactRowDeltaValue(
            encoded,
            result[rowStart + x],
            useResidual: useResidual,
            maxValue: maxValue,
          );
        }
      }
      row++;
    }
    return result;
  }

  int _readCompactRowDeltaPredictor(_BitReader reader) {
    if (reader.readBits(1) == 0) return _rowDeltaPredictorSame;
    return reader.readBits(1) == 0
        ? _rowDeltaPredictorLeft
        : _rowDeltaPredictorRight;
  }

  void _readCompactChangePositions(
    _BitReader reader,
    List<int> positions,
    int count,
    int rowLength,
  ) {
    var previousX = -1;
    for (var i = 0; i < count; i++) {
      final x = previousX + 1 + _readCompactUint(reader);
      if (x >= rowLength) {
        throw const MCOImageInvalidPayloadException(
          'Compact row-delta position out of range',
        );
      }
      positions.add(x);
      previousX = x;
    }
  }

  int _decodeCompactRowDeltaValue(
    int encoded,
    int predicted, {
    required bool useResidual,
    required int maxValue,
  }) {
    final value = useResidual
        ? predicted + (encoded.isOdd ? (encoded + 1) ~/ 2 : -(encoded ~/ 2))
        : encoded;
    if (value < 0 || value > maxValue) {
      throw const MCOImageInvalidPayloadException(
        'Compact row-delta reconstructed value out of range',
      );
    }
    return value;
  }

  List<int> _decodeV2DynamicBody(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
    ImageMode mode,
    DynamicPaletteReferenceEncoding referenceEncoding, {
    required int rowLength,
    int? sparseBackgroundColor,
  }) {
    final count = width * height;
    switch (mode) {
      case ImageMode.rawLocal:
        final palette = _readDynamicLocalPalette(
          reader,
          profile,
          referenceEncoding,
        );
        final localBits = _localBits(palette.globalColors.length);
        return List<int>.generate(count, (_) {
          final index = reader.readBits(localBits);
          if (index >= palette.globalColors.length) {
            throw const MCOImageInvalidPayloadException(
              'Dynamic local color index out of range',
            );
          }
          return palette.globalColors[index];
        });
      case ImageMode.rleLocal:
        final palette = _readDynamicLocalPalette(
          reader,
          profile,
          referenceEncoding,
        );
        final localBits = _localBits(palette.globalColors.length);
        final runCount = reader.readBitVarUint();
        final result = <int>[];
        for (var i = 0; i < runCount; i++) {
          final index = reader.readBits(localBits);
          if (index >= palette.globalColors.length) {
            throw const MCOImageInvalidPayloadException(
              'Dynamic RLE color index out of range',
            );
          }
          final length = reader.readBitVarUint();
          if (length <= 0 || result.length + length > count) {
            throw const MCOImageInvalidPayloadException(
              'Invalid dynamic RLE length',
            );
          }
          result.addAll(List<int>.filled(length, palette.globalColors[index]));
        }
        if (result.length != count) {
          throw const MCOImageInvalidPayloadException(
            'Dynamic RLE data does not fill canvas',
          );
        }
        return result;
      case ImageMode.sparseBg:
        final background =
            sparseBackgroundColor ?? _readV2ColorRef(reader, profile);
        final palette = _readDynamicLocalPalette(
          reader,
          profile,
          referenceEncoding,
        );
        if (palette.globalColors.contains(background)) {
          throw const MCOImageInvalidPayloadException(
            'Invalid dynamic sparse local palette',
          );
        }
        final localBits = _localBits(palette.globalColors.length);
        final segmentCount = reader.readBitVarUint();
        final result = List<int>.filled(count, background);
        var pos = 0;
        for (var i = 0; i < segmentCount; i++) {
          final skip = reader.readBitVarUint();
          pos += skip;
          final index = reader.readBits(localBits);
          if (index >= palette.globalColors.length) {
            throw const MCOImageInvalidPayloadException(
              'Dynamic sparse color index out of range',
            );
          }
          final length = reader.readBitVarUint();
          if (length <= 0 || pos + length > count) {
            throw const MCOImageInvalidPayloadException(
              'Invalid dynamic sparse segment',
            );
          }
          for (var j = 0; j < length; j++) {
            result[pos + j] = palette.globalColors[index];
          }
          pos += length;
        }
        return result;
      case ImageMode.rowRepeat:
        final palette = _readDynamicLocalPalette(
          reader,
          profile,
          referenceEncoding,
        );
        final localBits = _localBits(palette.globalColors.length);
        final localPixels = _readRowRepeatBody(
          reader,
          count,
          rowLength,
          localBits,
        );
        return localPixels
            .map((index) {
              if (index >= palette.globalColors.length) {
                throw const MCOImageInvalidPayloadException(
                  'Dynamic row-repeat color index out of range',
                );
              }
              return palette.globalColors[index];
            })
            .toList(growable: false);
      case ImageMode.rowDelta:
        final palette = _readDynamicLocalPalette(
          reader,
          profile,
          referenceEncoding,
        );
        final localBits = _localBits(palette.globalColors.length);
        final localPixels = _readRowDeltaBody(
          reader,
          count,
          rowLength,
          localBits,
        );
        return localPixels
            .map((index) {
              if (index >= palette.globalColors.length) {
                throw const MCOImageInvalidPayloadException(
                  'Dynamic row-delta color index out of range',
                );
              }
              return palette.globalColors[index];
            })
            .toList(growable: false);
      case ImageMode.biColorMask:
        final background =
            sparseBackgroundColor ?? _readV2ColorRef(reader, profile);
        final foreground = _readV2ColorRef(reader, profile);
        if (foreground == background) {
          throw const MCOImageInvalidPayloadException(
            'Dynamic bi-color foreground equals background',
          );
        }
        return _readBiColorMask(reader, count, background, foreground);
      case ImageMode.rawGlobal:
      case ImageMode.extended:
      case ImageMode.regionsBg:
        throw const MCOImageInvalidPayloadException(
          'Unsupported dynamic block mode',
        );
    }
  }

  List<int> _decodeDynamicBodyWithPalette(
    _BitReader reader,
    int width,
    int height,
    _DynamicLocalPalette palette,
    ImageMode mode,
    int background, {
    required int rowLength,
  }) {
    final count = width * height;
    final localBits = _localBits(palette.globalColors.length);
    switch (mode) {
      case ImageMode.rawLocal:
        return List<int>.generate(count, (_) {
          final index = reader.readBits(localBits);
          if (index >= palette.globalColors.length) {
            throw const MCOImageInvalidPayloadException(
              'Dynamic region local color index out of range',
            );
          }
          return palette.globalColors[index];
        });
      case ImageMode.rleLocal:
        final runCount = reader.readBitVarUint();
        final result = <int>[];
        for (var i = 0; i < runCount; i++) {
          final index = reader.readBits(localBits);
          if (index >= palette.globalColors.length) {
            throw const MCOImageInvalidPayloadException(
              'Dynamic region RLE color index out of range',
            );
          }
          final length = reader.readBitVarUint();
          if (length <= 0 || result.length + length > count) {
            throw const MCOImageInvalidPayloadException(
              'Invalid dynamic region RLE length',
            );
          }
          result.addAll(List<int>.filled(length, palette.globalColors[index]));
        }
        if (result.length != count) {
          throw const MCOImageInvalidPayloadException(
            'Dynamic region RLE data does not fill region',
          );
        }
        return result;
      case ImageMode.sparseBg:
        final segmentCount = reader.readBitVarUint();
        final result = List<int>.filled(count, background);
        var pos = 0;
        for (var i = 0; i < segmentCount; i++) {
          final skip = reader.readBitVarUint();
          pos += skip;
          final index = reader.readBits(localBits);
          if (index >= palette.globalColors.length) {
            throw const MCOImageInvalidPayloadException(
              'Dynamic region sparse color index out of range',
            );
          }
          final length = reader.readBitVarUint();
          if (length <= 0 || pos + length > count) {
            throw const MCOImageInvalidPayloadException(
              'Invalid dynamic region sparse segment',
            );
          }
          for (var j = 0; j < length; j++) {
            result[pos + j] = palette.globalColors[index];
          }
          pos += length;
        }
        return result;
      case ImageMode.rowRepeat:
        final localPixels = _readRowRepeatBody(
          reader,
          count,
          rowLength,
          localBits,
        );
        return localPixels
            .map((index) {
              if (index >= palette.globalColors.length) {
                throw const MCOImageInvalidPayloadException(
                  'Dynamic region row-repeat index out of range',
                );
              }
              return palette.globalColors[index];
            })
            .toList(growable: false);
      case ImageMode.rowDelta:
        final localPixels = _readRowDeltaBody(
          reader,
          count,
          rowLength,
          localBits,
        );
        return localPixels
            .map((index) {
              if (index >= palette.globalColors.length) {
                throw const MCOImageInvalidPayloadException(
                  'Dynamic region row-delta index out of range',
                );
              }
              return palette.globalColors[index];
            })
            .toList(growable: false);
      case ImageMode.biColorMask:
        final index = reader.readBits(localBits);
        if (index >= palette.globalColors.length) {
          throw const MCOImageInvalidPayloadException(
            'Dynamic region bi-color index out of range',
          );
        }
        final foreground = palette.globalColors[index];
        if (foreground == background) {
          throw const MCOImageInvalidPayloadException(
            'Dynamic region bi-color foreground equals background',
          );
        }
        return _readBiColorMask(reader, count, background, foreground);
      case ImageMode.extended:
        return _decodeDynamicExtendedBodyWithPalette(
          reader,
          width,
          height,
          palette,
          background,
          rowLength: rowLength,
        );
      case ImageMode.rawGlobal:
      case ImageMode.regionsBg:
        throw const MCOImageInvalidPayloadException(
          'Unsupported dynamic region block mode',
        );
    }
  }

  List<int> _decodeDynamicExtendedBodyWithPalette(
    _BitReader reader,
    int width,
    int height,
    _DynamicLocalPalette palette,
    int background, {
    required int rowLength,
  }) {
    final submode = reader.readBits(_extendedSubmodeBits);
    if (submode == ExtendedImageMode.compactRle.index) {
      return _decodeSharedPaletteCompactRle(reader, width, height, palette);
    }
    if (submode == ExtendedImageMode.compactSparse.index) {
      return _decodeSharedPaletteCompactSparse(
        reader,
        width,
        height,
        palette,
        background,
      );
    }
    if (submode == ExtendedImageMode.lzPixels.index) {
      return _decodeSharedPaletteLzPixels(reader, width, height, palette);
    }
    if (submode == ExtendedImageMode.quadtree.index) {
      return _decodeSharedPaletteQuadtree(reader, width, height, palette);
    }
    if (submode == ExtendedImageMode.bitplanes.index) {
      return _decodeAdaptiveBitplanesBody(
        reader,
        width,
        height,
        palette.globalColors,
      );
    }
    if (submode == ExtendedImageMode.compactRowDelta.index) {
      final directGrayscale = reader.readBits(1) != 0;
      if (directGrayscale) {
        throw const MCOImageInvalidPayloadException(
          'Shared palette row-delta cannot use direct grayscale',
        );
      }
      final localPixels = _readCompactRowDeltaBody(
        reader,
        width * height,
        rowLength,
        _localBits(palette.globalColors.length),
        directGrayscale: false,
        maxValue: palette.globalColors.length - 1,
      );
      return localPixels
          .map((index) {
            if (index >= palette.globalColors.length) {
              throw const MCOImageInvalidPayloadException(
                'Shared palette row-delta index out of range',
              );
            }
            return palette.globalColors[index];
          })
          .toList(growable: false);
    }
    throw const MCOImageInvalidPayloadException(
      'Unsupported shared palette extended region mode',
    );
  }

  List<int> _decodeSharedPaletteCompactRle(
    _BitReader reader,
    int width,
    int height,
    _DynamicLocalPalette palette,
  ) {
    final pixelCount = width * height;
    final localBits = _localBits(palette.globalColors.length);
    final result = <int>[];
    while (result.length < pixelCount) {
      final index = reader.readBits(localBits);
      if (index >= palette.globalColors.length) {
        throw const MCOImageInvalidPayloadException(
          'Shared palette compact RLE index out of range',
        );
      }
      final length = _readCompactUint(reader) + 1;
      if (result.length + length > pixelCount) {
        throw const MCOImageInvalidPayloadException(
          'Shared palette compact RLE exceeds pixel count',
        );
      }
      result.addAll(List<int>.filled(length, palette.globalColors[index]));
    }
    return result;
  }

  List<int> _decodeSharedPaletteCompactSparse(
    _BitReader reader,
    int width,
    int height,
    _DynamicLocalPalette palette,
    int background,
  ) {
    final pixelCount = width * height;
    final segmentCount = _readCompactUint(reader) + 1;
    if (segmentCount <= 0 || segmentCount > pixelCount) {
      throw const MCOImageInvalidPayloadException(
        'Invalid shared palette compact sparse segment count',
      );
    }
    final localBits = _localBits(palette.globalColors.length);
    final result = List<int>.filled(pixelCount, background);
    var pos = 0;
    for (var i = 0; i < segmentCount; i++) {
      final skip = _readCompactUint(reader);
      pos += skip;
      final index = reader.readBits(localBits);
      if (index >= palette.globalColors.length) {
        throw const MCOImageInvalidPayloadException(
          'Shared palette compact sparse index out of range',
        );
      }
      final length = _readCompactUint(reader) + 1;
      if (pos >= pixelCount || pos + length > pixelCount) {
        throw const MCOImageInvalidPayloadException(
          'Invalid shared palette compact sparse segment',
        );
      }
      for (var j = 0; j < length; j++) {
        result[pos + j] = palette.globalColors[index];
      }
      pos += length;
    }
    return result;
  }

  List<int> _decodeSharedPaletteLzPixels(
    _BitReader reader,
    int width,
    int height,
    _DynamicLocalPalette palette,
  ) {
    final pixelCount = width * height;
    final localBits = _localBits(palette.globalColors.length);
    final result = <int>[];
    while (result.length < pixelCount) {
      final isMatch = reader.readBits(1) != 0;
      if (isMatch) {
        final distance = _readCompactUint(reader) + 1;
        final length =
            _readCompactUint(reader) + _minLzMatchLength;
        if (distance <= 0 ||
            distance > result.length ||
            result.length + length > pixelCount) {
          throw const MCOImageInvalidPayloadException(
            'Invalid shared palette LZ match',
          );
        }
        for (var i = 0; i < length; i++) {
          result.add(result[result.length - distance]);
        }
      } else {
        final length = _readCompactUint(reader) + 1;
        if (result.length + length > pixelCount) {
          throw const MCOImageInvalidPayloadException(
            'Invalid shared palette LZ literal length',
          );
        }
        for (var i = 0; i < length; i++) {
          final index = reader.readBits(localBits);
          if (index >= palette.globalColors.length) {
            throw const MCOImageInvalidPayloadException(
              'Shared palette LZ index out of range',
            );
          }
          result.add(palette.globalColors[index]);
        }
      }
    }
    return result;
  }

  List<int> _decodeSharedPaletteQuadtree(
    _BitReader reader,
    int width,
    int height,
    _DynamicLocalPalette palette,
  ) {
    final result = List<int>.filled(width * height, palette.globalColors.first);
    _readQuadtreeNode(
      reader,
      result,
      width,
      0,
      0,
      width,
      height,
      palette.globalColors,
      _localBits(palette.globalColors.length),
    );
    return result;
  }

  List<int> _decodeRegions(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
  ) {
    final background = reader.readBits(_globalBits(profile));
    _validateColor(background, profile, 'backgroundColor', payload: true);
    final regionCount = reader.readVarUint();
    if (regionCount <= 0 || regionCount > _legacyMaxRegions) {
      throw const MCOImageInvalidPayloadException('Invalid region count');
    }

    final pixels = List<int>.filled(width * height, background);
    final occupied = List<bool>.filled(width * height, false);
    for (var i = 0; i < regionCount; i++) {
      final region = _ImageBounds(
        x: reader.readVarUint(),
        y: reader.readVarUint(),
        width: reader.readVarUint(),
        height: reader.readVarUint(),
      );
      if (region.width <= 0 ||
          region.height <= 0 ||
          region.x + region.width > width ||
          region.y + region.height > height) {
        throw const MCOImageInvalidPayloadException('Invalid image region');
      }

      final regionMode = _modeFromBits(reader.readAlignedByte());
      final regionScan = _scanFromBits(reader.readAlignedByte());
      final payloadLength = reader.readVarUint();
      final payload = reader.readAlignedBytes(payloadLength);
      final regionReader = _BitReader(payload);
      final linear = _decodeBody(
        regionReader,
        region.width,
        region.height,
        profile,
        regionMode,
        sparseBackgroundColor: background,
      );
      regionReader.finish();
      final regionPixels = _fromScanOrder(
        linear,
        region.width,
        region.height,
        regionScan,
      );
      for (var y = 0; y < region.height; y++) {
        for (var x = 0; x < region.width; x++) {
          final target = (region.y + y) * width + region.x + x;
          if (occupied[target]) {
            throw const MCOImageInvalidPayloadException(
              'Overlapping image regions',
            );
          }
          occupied[target] = true;
          pixels[target] = regionPixels[y * region.width + x];
        }
      }
    }
    return pixels;
  }

  List<int> _decodeV2Regions(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
    DynamicPaletteReferenceEncoding? referenceEncoding, {
    required bool compactGeometry,
    required bool implicitWhiteBackground,
    required bool sharedFixedPalette,
  }) {
    final effectiveImplicitWhiteBackground = sharedFixedPalette
        ? reader.readBits(1) != 0
        : implicitWhiteBackground;
    final background = _readV2BackgroundRef(
      reader,
      profile,
      implicitWhiteBackground: effectiveImplicitWhiteBackground,
    );
    _DynamicLocalPalette? sharedDynamicPalette;
    _DynamicLocalPalette? sharedFixedLocalPalette;
    if (profile.isDynamic) {
      if (referenceEncoding == null) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic v2 regions are missing reference encoding',
        );
      }
      sharedDynamicPalette = _readDynamicLocalPalette(
        reader,
        profile,
        referenceEncoding,
      );
    } else if (sharedFixedPalette) {
      sharedFixedLocalPalette = _DynamicLocalPalette(
        _readV2LocalPalette(reader, profile),
      );
    }

    final regionCount = compactGeometry
        ? reader.readBits(_bitsForChoiceCount(_maxV2Regions)) + 1
        : reader.readBitVarUint();
    if (regionCount <= 0 || regionCount > _maxV2Regions) {
      throw const MCOImageInvalidPayloadException('Invalid v2 region count');
    }

    final pixels = List<int>.filled(width * height, background);
    final occupied = List<bool>.filled(width * height, false);
    for (var i = 0; i < regionCount; i++) {
      final region = compactGeometry
          ? _readV2CompactBounds(reader, width, height)
          : _ImageBounds(
              x: reader.readBitVarUint(),
              y: reader.readBitVarUint(),
              width: reader.readBitVarUint(),
              height: reader.readBitVarUint(),
            );
      if (region.width <= 0 ||
          region.height <= 0 ||
          region.x + region.width > width ||
          region.y + region.height > height) {
        throw const MCOImageInvalidPayloadException('Invalid v2 image region');
      }

      final modeAndScan = reader.readAlignedByte();
      if ((modeAndScan & 0x07) != 0) {
        throw const MCOImageInvalidPayloadException(
          'Reserved region bits are set',
        );
      }
      final regionMode = _modeFromBits((modeAndScan >> 5) & 0x07);
      final regionScan = _scanFromBits((modeAndScan >> 3) & 0x03);
      if (profile.isDynamic && regionMode == ImageMode.rawGlobal) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic region rawGlobal is reserved',
        );
      }
      final payloadLength = reader.readBitVarUint();
      final payload = reader.readAlignedBytes(payloadLength);
      final regionReader = _BitReader(payload);
      final linear = profile.isDynamic
          ? _decodeDynamicBodyWithPalette(
              regionReader,
              region.width,
              region.height,
              sharedDynamicPalette!,
              regionMode,
              background,
              rowLength: _rowLengthForScan(
                regionScan,
                region.width,
                region.height,
              ),
            )
          : sharedFixedPalette
          ? _decodeDynamicBodyWithPalette(
              regionReader,
              region.width,
              region.height,
              sharedFixedLocalPalette!,
              regionMode,
              background,
              rowLength: _rowLengthForScan(
                regionScan,
                region.width,
                region.height,
              ),
            )
          : _decodeV2Body(
              regionReader,
              region.width,
              region.height,
              profile,
              regionMode,
              null,
              rowLength: _rowLengthForScan(
                regionScan,
                region.width,
                region.height,
              ),
              sparseBackgroundColor: background,
            );
      regionReader.finish();
      final regionPixels = _fromScanOrder(
        linear,
        region.width,
        region.height,
        regionScan,
      );
      for (var y = 0; y < region.height; y++) {
        for (var x = 0; x < region.width; x++) {
          final target = (region.y + y) * width + region.x + x;
          if (occupied[target]) {
            throw const MCOImageInvalidPayloadException(
              'Overlapping v2 image regions',
            );
          }
          occupied[target] = true;
          pixels[target] = regionPixels[y * region.width + x];
        }
      }
    }
    return pixels;
  }

  Uint8List _buildPayload(
    MCOImage image,
    List<int> linear,
    ImageMode mode,
    ScanMode scan, {
    required int dataWidth,
    required int dataHeight,
    required int backgroundColor,
    _ImageBounds? bounds,
  }) {
    final expectedDataLength = dataWidth * dataHeight;
    if (linear.length != expectedDataLength) {
      throw MCOImageInvalidInputException(
        'linear.length must be $expectedDataLength, got ${linear.length}',
      );
    }
    final writer = _BitWriter();
    final bgPresent = mode == ImageMode.sparseBg;
    final boundsPresent = bounds != null;
    writer.writeAlignedByte(
      (_encodeVersion << 6) |
          (_modeBits(mode) << 4) |
          (_scanBits(scan) << 2) |
          (bgPresent ? 0x02 : 0) |
          (boundsPresent ? 0x01 : 0),
    );
    writer.writeAlignedByte(_profileBits(image.paletteProfile) << 4);
    writer.writeAlignedByte(image.width - 1);
    writer.writeAlignedByte(image.height - 1);

    if (boundsPresent) {
      // Bounds keep the original canvas size in the header, but encode only the
      // non-background rectangle and fill everything outside it while decoding.
      writer.writeBits(backgroundColor, _globalBits(image.paletteProfile));
      writer.writeVarUint(bounds.x);
      writer.writeVarUint(bounds.y);
      writer.writeVarUint(bounds.width);
      writer.writeVarUint(bounds.height);
      if (bounds.area == 0) {
        return writer.toBytes();
      }
    }

    _writeBlock(
      writer,
      linear,
      mode,
      image.paletteProfile,
      backgroundColor: backgroundColor,
      writeSparseBackground: !boundsPresent,
    );
    return writer.toBytes();
  }

  void _writeBlock(
    _BitWriter writer,
    List<int> linear,
    ImageMode mode,
    PaletteProfile profile, {
    required int backgroundColor,
    required bool writeSparseBackground,
  }) {
    switch (mode) {
      case ImageMode.rawGlobal:
        _encodeRawGlobal(writer, linear, profile);
        break;
      case ImageMode.rawLocal:
        _encodeRawLocal(writer, linear, profile);
        break;
      case ImageMode.rleLocal:
        _encodeRleLocal(writer, linear, profile);
        break;
      case ImageMode.sparseBg:
        _encodeSparseBg(
          writer,
          linear,
          profile,
          backgroundColor: backgroundColor,
          writeBackground: writeSparseBackground,
        );
        break;
      case ImageMode.biColorMask:
        throw const MCOImageInvalidInputException(
          'BI_COLOR_MASK is not supported by legacy block mode',
        );
      case ImageMode.rowDelta:
        throw const MCOImageInvalidInputException(
          'ROW_DELTA is not supported by legacy block mode',
        );
      case ImageMode.rowRepeat:
        throw const MCOImageInvalidInputException(
          'ROW_REPEAT is not supported by legacy block mode',
        );
      case ImageMode.extended:
      case ImageMode.regionsBg:
        throw const MCOImageInvalidInputException(
          'REGIONS_BG is not a block mode',
        );
    }
  }

  void _writeV2DynamicBlockWithLocalPalette(
    _BitWriter writer,
    List<int> linear,
    ImageMode mode,
    PaletteProfile profile, {
    required int rowLength,
    required int backgroundColor,
    required Map<int, int> localIndexByProfileColorId,
  }) {
    switch (mode) {
      case ImageMode.rawLocal:
        final localBits = _localBits(localIndexByProfileColorId.length);
        for (final globalIndex in linear) {
          final profileColorId = _profileColorIdForGlobalIndex(
            profile,
            globalIndex,
          );
          final localIndex = localIndexByProfileColorId[profileColorId];
          if (localIndex == null) {
            throw MCOImageInvalidInputException(
              'Dynamic shared palette is missing globalIndex $globalIndex',
            );
          }
          writer.writeBits(localIndex, localBits);
        }
        break;
      case ImageMode.rleLocal:
        final localBits = _localBits(localIndexByProfileColorId.length);
        final localPixels = linear.map((globalIndex) {
          final profileColorId = _profileColorIdForGlobalIndex(
            profile,
            globalIndex,
          );
          final localIndex = localIndexByProfileColorId[profileColorId];
          if (localIndex == null) {
            throw MCOImageInvalidInputException(
              'Dynamic shared palette is missing globalIndex $globalIndex',
            );
          }
          return localIndex;
        }).toList();
        final runs = _buildRuns(localPixels);
        writer.writeBitVarUint(runs.length);
        for (final run in runs) {
          writer.writeBits(run.color, localBits);
          writer.writeBitVarUint(run.length);
        }
        break;
      case ImageMode.sparseBg:
        final localBits = _localBits(localIndexByProfileColorId.length);
        final segments = _buildDynamicSparseSegments(
          linear,
          profile,
          backgroundColor,
          localIndexByProfileColorId,
        );
        writer.writeBitVarUint(segments.length);
        var pos = 0;
        for (final segment in segments) {
          writer.writeBitVarUint(segment.start - pos);
          writer.writeBits(segment.color, localBits);
          writer.writeBitVarUint(segment.length);
          pos = segment.start + segment.length;
        }
        break;
      case ImageMode.rowRepeat:
        final localBits = _localBits(localIndexByProfileColorId.length);
        final localPixels = linear
            .map((globalIndex) {
              final profileColorId = _profileColorIdForGlobalIndex(
                profile,
                globalIndex,
              );
              final localIndex = localIndexByProfileColorId[profileColorId];
              if (localIndex == null) {
                throw MCOImageInvalidInputException(
                  'Dynamic shared palette is missing globalIndex $globalIndex',
                );
              }
              return localIndex;
            })
            .toList(growable: false);
        _writeRowRepeatBody(writer, localPixels, rowLength, localBits);
        break;
      case ImageMode.rowDelta:
        final localBits = _localBits(localIndexByProfileColorId.length);
        final localPixels = linear
            .map((globalIndex) {
              final profileColorId = _profileColorIdForGlobalIndex(
                profile,
                globalIndex,
              );
              final localIndex = localIndexByProfileColorId[profileColorId];
              if (localIndex == null) {
                throw MCOImageInvalidInputException(
                  'Dynamic shared palette is missing globalIndex $globalIndex',
                );
              }
              return localIndex;
            })
            .toList(growable: false);
        _writeRowDeltaBody(writer, localPixels, rowLength, localBits);
        break;
      case ImageMode.biColorMask:
        final foregroundColor = _biColorForeground(linear, backgroundColor);
        if (foregroundColor == null) {
          throw const MCOImageInvalidInputException(
            'BI_COLOR_MASK requires exactly one foreground color',
          );
        }
        final foregroundProfileColorId = _profileColorIdForGlobalIndex(
          profile,
          foregroundColor,
        );
        final foregroundIndex =
            localIndexByProfileColorId[foregroundProfileColorId];
        if (foregroundIndex == null) {
          throw const MCOImageInvalidInputException(
            'Dynamic shared palette is missing bi-color foreground',
          );
        }
        final localBits = _localBits(localIndexByProfileColorId.length);
        writer.writeBits(foregroundIndex, localBits);
        _writeBiColorMask(writer, linear, backgroundColor, foregroundColor);
        break;
      case ImageMode.rawGlobal:
      case ImageMode.extended:
      case ImageMode.regionsBg:
        throw const MCOImageInvalidInputException(
          'Unsupported dynamic shared block mode',
        );
    }
  }

  void _writeV2FixedBlockWithSharedPalette(
    _BitWriter writer,
    List<int> linear,
    ImageMode mode, {
    required int rowLength,
    required int backgroundColor,
    required Map<int, int> localIndexByColor,
  }) {
    final localBits = _localBits(localIndexByColor.length);
    int localIndex(int color) {
      final index = localIndexByColor[color];
      if (index == null) {
        throw MCOImageInvalidInputException(
          'Fixed shared palette is missing color $color',
        );
      }
      return index;
    }

    switch (mode) {
      case ImageMode.rawLocal:
        for (final color in linear) {
          writer.writeBits(localIndex(color), localBits);
        }
        break;
      case ImageMode.rleLocal:
        final runs = _buildRuns(linear);
        writer.writeBitVarUint(runs.length);
        for (final run in runs) {
          writer
            ..writeBits(localIndex(run.color), localBits)
            ..writeBitVarUint(run.length);
        }
        break;
      case ImageMode.sparseBg:
        final segments = _buildSparseSegments(linear, backgroundColor);
        writer.writeBitVarUint(segments.length);
        var pos = 0;
        for (final segment in segments) {
          writer
            ..writeBitVarUint(segment.start - pos)
            ..writeBits(localIndex(segment.color), localBits)
            ..writeBitVarUint(segment.length);
          pos = segment.start + segment.length;
        }
        break;
      case ImageMode.rowRepeat:
        _writeRowRepeatBody(
          writer,
          linear.map(localIndex).toList(growable: false),
          rowLength,
          localBits,
        );
        break;
      case ImageMode.rowDelta:
        _writeRowDeltaBody(
          writer,
          linear.map(localIndex).toList(growable: false),
          rowLength,
          localBits,
        );
        break;
      case ImageMode.biColorMask:
        final foreground = _biColorForeground(linear, backgroundColor);
        if (foreground == null) {
          throw const MCOImageInvalidInputException(
            'BI_COLOR_MASK requires exactly one foreground color',
          );
        }
        writer.writeBits(localIndex(foreground), localBits);
        _writeBiColorMask(
          writer,
          linear,
          backgroundColor,
          foreground,
        );
        break;
      case ImageMode.rawGlobal:
      case ImageMode.extended:
      case ImageMode.regionsBg:
        throw const MCOImageInvalidInputException(
          'Unsupported fixed shared block mode',
        );
    }
  }

  EncodedMCOImage _candidateFromPayload(
    Uint8List payload,
    ImageMode mode,
    ScanMode scan, {
    _ImageBounds? bounds,
    int? backgroundColor,
    int? transparentColor,
    int backgroundRank = 0,
    int regionCount = 0,
    int codecVersion = _encodeVersion,
    DynamicPaletteReferenceEncoding? dynamicReferenceEncoding,
    int? localPaletteSize,
    int? usedBankCount,
    int? bitsPerLocalPixel,
    String paletteKind = 'fixed',
    String container = 'block',
  }) {
    final text = '$prefix${_Base91.encode(payload)}';
    return EncodedMCOImage(
      text: text,
      mode: mode,
      scan: scan,
      byteLength: payload.length,
      charLength: text.length,
      boundsPresent: bounds != null,
      boundsX: bounds?.x,
      boundsY: bounds?.y,
      boundsWidth: bounds?.width,
      boundsHeight: bounds?.height,
      backgroundColor: backgroundColor,
      transparentColor: transparentColor,
      backgroundRank: backgroundRank,
      regionCount: regionCount,
      codecVersion: codecVersion,
      dynamicReferenceEncoding: dynamicReferenceEncoding,
      localPaletteSize: localPaletteSize,
      usedBankCount: usedBankCount,
      bitsPerLocalPixel: bitsPerLocalPixel,
      requestedEncodingVersion: codecVersion == _encodeVersion
          ? MCOImageEncodingVersion.v1Legacy
          : MCOImageEncodingVersion.v2,
      actualEncodingVersion: codecVersion == _encodeVersion
          ? MCOImageEncodingVersion.v1Legacy
          : MCOImageEncodingVersion.v2,
      paletteKind: paletteKind,
      container: container,
    );
  }

  _ImageBounds _readBounds(_BitReader reader, int fullWidth, int fullHeight) {
    final bounds = _ImageBounds(
      x: reader.readVarUint(),
      y: reader.readVarUint(),
      width: reader.readVarUint(),
      height: reader.readVarUint(),
    );
    if (bounds.width < 0 ||
        bounds.height < 0 ||
        bounds.x + bounds.width > fullWidth ||
        bounds.y + bounds.height > fullHeight ||
        (bounds.width == 0 && bounds.height != 0) ||
        (bounds.height == 0 && bounds.width != 0)) {
      throw const MCOImageInvalidPayloadException('Invalid image bounds');
    }
    return bounds;
  }

  _ImageBounds _readV2Bounds(_BitReader reader, int fullWidth, int fullHeight) {
    final bounds = _ImageBounds(
      x: reader.readBitVarUint(),
      y: reader.readBitVarUint(),
      width: reader.readBitVarUint(),
      height: reader.readBitVarUint(),
    );
    if (bounds.width < 0 ||
        bounds.height < 0 ||
        bounds.x + bounds.width > fullWidth ||
        bounds.y + bounds.height > fullHeight ||
        (bounds.width == 0 && bounds.height != 0) ||
        (bounds.height == 0 && bounds.width != 0)) {
      throw const MCOImageInvalidPayloadException('Invalid image bounds');
    }
    return bounds;
  }

  static _ImageBounds _findBounds(
    List<int> pixels,
    int width,
    int height,
    int backgroundColor,
  ) {
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (pixels[y * width + x] == backgroundColor) continue;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
    }
    if (maxX < 0) {
      return const _ImageBounds(x: 0, y: 0, width: 0, height: 0);
    }
    return _ImageBounds(
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
    );
  }

  List<List<_SolidRect>> _solidRectVariants(
    List<int> pixels,
    int width,
    int height,
    int background, {
    required int maxRects,
  }) {
    final horizontal = <_SolidRect>[];
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
          _SolidRect(
            _ImageBounds(x: start, y: y, width: x - start, height: 1),
            color,
          ),
        );
      }
    }

    final vertical = <_SolidRect>[];
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
          _SolidRect(
            _ImageBounds(x: x, y: start, width: 1, height: y - start),
            color,
          ),
        );
      }
    }

    final mergedHorizontal = _mergeSolidRuns(horizontal, vertical: false);
    final mergedVertical = _mergeSolidRuns(vertical, vertical: true);

    return <List<_SolidRect>>[
      if (mergedHorizontal.isNotEmpty && mergedHorizontal.length <= maxRects)
        mergedHorizontal,
      if (mergedVertical.isNotEmpty && mergedVertical.length <= maxRects)
        mergedVertical,
    ];
  }

  List<_SolidRect> _mergeSolidRuns(
    List<_SolidRect> runs, {
    required bool vertical,
  }) {
    final merged = <_SolidRect>[];
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
          merged[previousIndex] = _SolidRect(
            _ImageBounds(
              x: previous.bounds.x,
              y: previous.bounds.y,
              width: vertical
                  ? previous.bounds.width + bounds.width
                  : previous.bounds.width,
              height: vertical
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

  static List<_BackgroundCandidate> _backgroundCandidates(
    MCOImage image,
    int? explicitBackground, {
    bool exhaustiveSmallImage = false,
  }) {
    final result = <_BackgroundCandidate>[];
    final seen = <int>{};

    void add(int color, int rank) {
      if (color < 0 || color >= _paletteSize(image.paletteProfile)) return;
      if (!seen.add(color)) return;
      result.add(_BackgroundCandidate(color, rank));
    }

    if (explicitBackground != null) add(explicitBackground, 0);
    add(0, 1);

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

  List<_ImageBounds> _splitRegionsByEmptyLines(
    List<int> pixels,
    int fullWidth,
    int background,
    List<_ImageBounds> regions,
    int maxRegions,
  ) {
    return _splitRegionsBySparseLines(
      pixels,
      fullWidth,
      background,
      regions,
      maxRegions,
      maxLineNonBackground: 0,
    );
  }

  List<_ImageBounds> _splitRegionsBySparseLines(
    List<int> pixels,
    int fullWidth,
    int background,
    List<_ImageBounds> regions,
    int maxRegions, {
    required int maxLineNonBackground,
  }) {
    if (maxRegions == 0 || regions.isEmpty) return const <_ImageBounds>[];

    final result = <_ImageBounds>[];
    for (final region in regions) {
      _splitRegionByBestSparseLine(
        pixels,
        fullWidth,
        background,
        region,
        result,
        maxRegions,
        maxLineNonBackground: maxLineNonBackground,
      );
      if (result.length > maxRegions) {
        return const <_ImageBounds>[];
      }
    }

    result.sort((a, b) {
      final byY = a.y.compareTo(b.y);
      return byY != 0 ? byY : a.x.compareTo(b.x);
    });

    if (result.length == regions.length && _sameRegionList(result, regions)) {
      return const <_ImageBounds>[];
    }
    return result;
  }

  void _splitRegionByBestSparseLine(
    List<int> pixels,
    int fullWidth,
    int background,
    _ImageBounds region,
    List<_ImageBounds> output,
    int maxRegions, {
    required int maxLineNonBackground,
  }) {
    if (output.length > maxRegions) return;

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

  _RegionPartition? _bestSparseRowSplit(
    List<int> pixels,
    int fullWidth,
    int background,
    _ImageBounds region,
    int maxLineNonBackground,
  ) {
    _RegionPartition? best;
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

      final candidates = <_ImageBounds?>[
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _ImageBounds(
            x: region.x,
            y: region.y,
            width: region.width,
            height: startY - region.y,
          ),
        ),
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _ImageBounds(
            x: region.x,
            y: startY,
            width: region.width,
            height: endY - startY + 1,
          ),
        ),
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _ImageBounds(
            x: region.x,
            y: endY + 1,
            width: region.width,
            height: region.y + region.height - endY - 1,
          ),
        ),
      ];

      final parts = candidates.whereType<_ImageBounds>().toList();
      final partition = _partitionIfUseful(region, parts);
      if (partition != null &&
          (best == null || partition.savedArea > best.savedArea)) {
        best = partition;
      }
    }
    return best;
  }

  _RegionPartition? _bestSparseColumnSplit(
    List<int> pixels,
    int fullWidth,
    int background,
    _ImageBounds region,
    int maxLineNonBackground,
  ) {
    _RegionPartition? best;
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

      final candidates = <_ImageBounds?>[
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _ImageBounds(
            x: region.x,
            y: region.y,
            width: startX - region.x,
            height: region.height,
          ),
        ),
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _ImageBounds(
            x: startX,
            y: region.y,
            width: endX - startX + 1,
            height: region.height,
          ),
        ),
        _tightBoundsInRect(
          pixels,
          fullWidth,
          background,
          _ImageBounds(
            x: endX + 1,
            y: region.y,
            width: region.x + region.width - endX - 1,
            height: region.height,
          ),
        ),
      ];

      final parts = candidates.whereType<_ImageBounds>().toList();
      final partition = _partitionIfUseful(region, parts);
      if (partition != null &&
          (best == null || partition.savedArea > best.savedArea)) {
        best = partition;
      }
    }
    return best;
  }

  _RegionPartition? _partitionIfUseful(
    _ImageBounds original,
    List<_ImageBounds> parts,
  ) {
    if (parts.length < 2) return null;
    var area = 0;
    for (final part in parts) {
      area += part.area;
    }
    final savedArea = original.area - area;
    if (savedArea <= 0) return null;
    return _RegionPartition(List.unmodifiable(parts), savedArea);
  }

  _RegionPartition? _betterRegionPartition(
    _RegionPartition? a,
    _RegionPartition? b,
  ) {
    if (a == null) return b;
    if (b == null) return a;
    return a.savedArea >= b.savedArea ? a : b;
  }

  int _regionRowNonBackgroundCount(
    List<int> pixels,
    int fullWidth,
    int background,
    _ImageBounds region,
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
    _ImageBounds region,
    int x,
  ) {
    var count = 0;
    for (var y = region.y; y < region.y + region.height; y++) {
      if (pixels[y * fullWidth + x] != background) count++;
    }
    return count;
  }

  _ImageBounds? _tightBoundsInRect(
    List<int> pixels,
    int fullWidth,
    int background,
    _ImageBounds rect,
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
    return _ImageBounds(
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
    );
  }

  bool _sameRegionList(List<_ImageBounds> a, List<_ImageBounds> b) {
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

  List<List<_ImageBounds>> _findGreedyRectRegionVariants(
    List<int> pixels,
    int width,
    int height,
    int background,
    int maxRegions,
  ) {
    if (maxRegions == 0) return const <List<_ImageBounds>>[];

    const strategies = <_GreedyRectStrategy>[
      _GreedyRectStrategy(1, 1, _greedyTieLargestArea),
      _GreedyRectStrategy(1, 1, _greedyTieWidest),
      _GreedyRectStrategy(1, 1, _greedyTieTallest),
      _GreedyRectStrategy(-1, 1, _greedyTieLargestArea),
      _GreedyRectStrategy(1, -1, _greedyTieLargestArea),
      _GreedyRectStrategy(-1, -1, _greedyTieLargestArea),
    ];

    final variants = <List<_ImageBounds>>[];
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

  List<_ImageBounds> _findGreedyRectRegionsWithStrategy(
    List<int> pixels,
    int width,
    int height,
    int background,
    int maxRegions,
    _GreedyRectStrategy strategy,
  ) {
    final covered = List<bool>.filled(pixels.length, false);
    final regions = <_ImageBounds>[];

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
        return const <_ImageBounds>[];
      }

      for (var y = rect.y; y < rect.y + rect.height; y++) {
        for (var x = rect.x; x < rect.x + rect.width; x++) {
          covered[y * width + x] = true;
        }
      }
    }

    regions.sort((a, b) {
      final byY = a.y.compareTo(b.y);
      return byY != 0 ? byY : a.x.compareTo(b.x);
    });
    return regions;
  }

  int _findGreedyStartIndex(
    List<int> pixels,
    List<bool> covered,
    int width,
    int height,
    int background,
    _GreedyRectStrategy strategy,
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

  _ImageBounds _bestGreedyRectAt(
    List<int> pixels,
    List<bool> covered,
    int width,
    int height,
    int background,
    int startX,
    int startY,
    _GreedyRectStrategy strategy,
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
    return _ImageBounds(x: x, y: y, width: bestWidth, height: bestHeight);
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

  String _regionListKey(List<_ImageBounds> regions) {
    final parts = <String>[];
    for (final region in regions) {
      parts.add('${region.x},${region.y},${region.width},${region.height}');
    }
    return parts.join(';');
  }

  static List<_ImageBounds> _findRegions(
    List<int> pixels,
    int width,
    int height,
    int backgroundColor,
  ) {
    final visited = List<bool>.filled(width * height, false);
    final regions = <_ImageBounds>[];
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

    for (var start = 0; start < pixels.length; start++) {
      if (visited[start] || pixels[start] == backgroundColor) continue;
      var minX = start % width;
      var maxX = minX;
      var minY = start ~/ width;
      var maxY = minY;
      final queue = <int>[start];
      visited[start] = true;

      while (queue.isNotEmpty) {
        final index = queue.removeLast();
        final x = index % width;
        final y = index ~/ width;
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);

        for (final neighbor in neighbors) {
          final nx = x + neighbor[0];
          final ny = y + neighbor[1];
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          final next = ny * width + nx;
          if (visited[next] || pixels[next] == backgroundColor) continue;
          visited[next] = true;
          queue.add(next);
        }
      }

      regions.add(
        _ImageBounds(
          x: minX,
          y: minY,
          width: maxX - minX + 1,
          height: maxY - minY + 1,
        ),
      );
    }

    regions.sort((a, b) {
      final byY = a.y.compareTo(b.y);
      return byY != 0 ? byY : a.x.compareTo(b.x);
    });
    return regions;
  }

  static List<int> _cropPixels(
    List<int> pixels,
    int fullWidth,
    _ImageBounds bounds,
  ) {
    final cropped = <int>[];
    for (var y = 0; y < bounds.height; y++) {
      final start = (bounds.y + y) * fullWidth + bounds.x;
      cropped.addAll(pixels.getRange(start, start + bounds.width));
    }
    return cropped;
  }

  static List<int> _insertBounds(
    int fullWidth,
    int fullHeight,
    int backgroundColor,
    List<int> cropped,
    _ImageBounds bounds,
  ) {
    final pixels = List<int>.filled(fullWidth * fullHeight, backgroundColor);
    for (var y = 0; y < bounds.height; y++) {
      for (var x = 0; x < bounds.width; x++) {
        pixels[(bounds.y + y) * fullWidth + bounds.x + x] =
            cropped[y * bounds.width + x];
      }
    }
    return pixels;
  }

  void _encodeRawGlobal(
    _BitWriter writer,
    List<int> linear,
    PaletteProfile profile,
  ) {
    final bits = _globalBits(profile);
    for (final pixel in linear) {
      writer.writeBits(pixel, bits);
    }
  }

  List<int> _decodeRawGlobal(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
  ) {
    final bits = _globalBits(profile);
    final count = width * height;
    return List<int>.generate(count, (_) => reader.readBits(bits));
  }

  void _encodeRawLocal(
    _BitWriter writer,
    List<int> linear,
    PaletteProfile profile,
  ) {
    final local = _buildLocalPalette(linear);
    final map = _localIndexMap(local.colors);
    final localBits = _localBits(local.colors.length);
    writer.writeVarUint(local.colors.length);
    _writePalette(writer, local.colors, profile);
    for (final pixel in linear) {
      writer.writeBits(map[pixel]!, localBits);
    }
  }

  List<int> _decodeRawLocal(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
  ) {
    final count = width * height;
    final palette = _readLocalPalette(reader, profile);
    final localBits = _localBits(palette.length);
    return List<int>.generate(count, (_) {
      final index = reader.readBits(localBits);
      if (index >= palette.length) {
        throw const MCOImageInvalidPayloadException(
          'Local color index out of range',
        );
      }
      return palette[index];
    });
  }

  void _encodeRleLocal(
    _BitWriter writer,
    List<int> linear,
    PaletteProfile profile,
  ) {
    final local = _buildLocalPalette(linear);
    final map = _localIndexMap(local.colors);
    final localBits = _localBits(local.colors.length);
    final runs = _buildRuns(linear);
    writer.writeVarUint(local.colors.length);
    _writePalette(writer, local.colors, profile);
    writer.writeVarUint(runs.length);
    for (final run in runs) {
      writer.writeBits(map[run.color]!, localBits);
      writer.writeVarUint(run.length);
    }
  }

  List<int> _decodeRleLocal(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile,
  ) {
    final count = width * height;
    final palette = _readLocalPalette(reader, profile);
    final localBits = _localBits(palette.length);
    final runCount = reader.readVarUint();
    final result = <int>[];
    for (var i = 0; i < runCount; i++) {
      final index = reader.readBits(localBits);
      if (index >= palette.length) {
        throw const MCOImageInvalidPayloadException(
          'RLE local color index out of range',
        );
      }
      final length = reader.readVarUint();
      if (length <= 0 || result.length + length > count) {
        throw const MCOImageInvalidPayloadException('Invalid RLE length');
      }
      result.addAll(List<int>.filled(length, palette[index]));
    }
    if (result.length != count) {
      throw const MCOImageInvalidPayloadException(
        'RLE data does not fill canvas',
      );
    }
    return result;
  }

  void _encodeSparseBg(
    _BitWriter writer,
    List<int> linear,
    PaletteProfile profile, {
    required int backgroundColor,
    bool writeBackground = true,
  }) {
    final bg = backgroundColor;
    final globalBits = _globalBits(profile);
    if (writeBackground) {
      writer.writeBits(bg, globalBits);
    }

    final nonBgColors = linear.where((p) => p != bg).toList();
    final local = _buildLocalPalette(nonBgColors);
    final map = _localIndexMap(local.colors);
    final localBits = _localBits(local.colors.length);
    final segments = _buildSparseSegments(linear, bg);

    writer.writeVarUint(local.colors.length);
    _writePalette(writer, local.colors, profile);
    writer.writeVarUint(segments.length);
    var pos = 0;
    for (final segment in segments) {
      writer.writeVarUint(segment.start - pos);
      writer.writeBits(map[segment.color]!, localBits);
      writer.writeVarUint(segment.length);
      pos = segment.start + segment.length;
    }
  }

  List<int> _decodeSparseBg(
    _BitReader reader,
    int width,
    int height,
    PaletteProfile profile, {
    int? backgroundColor,
  }) {
    final count = width * height;
    final bg = backgroundColor ?? reader.readBits(_globalBits(profile));
    _validateColor(bg, profile, 'backgroundColor', payload: true);
    final palette = _readLocalPalette(
      reader,
      profile,
      excludedColor: bg,
      allowEmpty: true,
    );
    final localBits = _localBits(palette.length);
    final segmentCount = reader.readVarUint();
    final result = List<int>.filled(count, bg);
    var pos = 0;
    for (var i = 0; i < segmentCount; i++) {
      final skip = reader.readVarUint();
      pos += skip;
      final index = reader.readBits(localBits);
      if (index >= palette.length) {
        throw const MCOImageInvalidPayloadException(
          'Sparse local color index out of range',
        );
      }
      final length = reader.readVarUint();
      if (length <= 0 || pos + length > count) {
        throw const MCOImageInvalidPayloadException('Invalid sparse segment');
      }
      for (var j = 0; j < length; j++) {
        result[pos + j] = palette[index];
      }
      pos += length;
    }
    return result;
  }

  void _writePalette(
    _BitWriter writer,
    List<int> colors,
    PaletteProfile profile,
  ) {
    final bits = _globalBits(profile);
    for (final color in colors) {
      writer.writeBits(color, bits);
    }
  }

  List<int> _readLocalPalette(
    _BitReader reader,
    PaletteProfile profile, {
    int? excludedColor,
    bool allowEmpty = false,
  }) {
    final k = reader.readVarUint();
    final maxColors = _paletteSize(profile);
    if ((!allowEmpty && k == 0) || k > maxColors) {
      throw const MCOImageInvalidPayloadException('Invalid local palette size');
    }
    final bits = _globalBits(profile);
    final colors = <int>[];
    final seen = <int>{};
    for (var i = 0; i < k; i++) {
      final color = reader.readBits(bits);
      _validateColor(color, profile, 'localPalette', payload: true);
      if (color == excludedColor || !seen.add(color)) {
        throw const MCOImageInvalidPayloadException('Invalid local palette');
      }
      colors.add(color);
    }
    return colors;
  }

  List<int> _readV2LocalPalette(
    _BitReader reader,
    PaletteProfile profile, {
    int? excludedColor,
  }) {
    final k = reader.readBitVarUint();
    if (k == 0) {
      return _readV2FixedPaletteDescriptor(
        reader,
        profile,
        excludedColor: excludedColor,
      );
    }
    return _readV2LocalPaletteBody(
      reader,
      profile,
      k,
      excludedColor: excludedColor,
    );
  }

  List<int> _writeV2FixedLocalPalette(
    _BitWriter writer,
    List<int> colors,
    PaletteProfile profile,
  ) {
    if (!profile.isFixed || colors.isEmpty) {
      throw const MCOImageInvalidInputException(
        'Compact fixed palette requires fixed non-empty colors',
      );
    }
    final sorted = colors.toSet().toList()..sort();
    final globalBits = _globalBits(profile);
    final legacyBits = _bitVarUintBitLength(colors.length) +
        colors.length * globalBits;
    final bitmapBits = _bitVarUintBitLength(0) +
        _fixedPaletteDescriptorBits +
        _paletteSize(profile);

    var deltaBits = _bitVarUintBitLength(0) +
        _fixedPaletteDescriptorBits +
        _bitVarUintBitLength(sorted.length) +
        globalBits;
    for (var i = 1; i < sorted.length; i++) {
      deltaBits += _compactUintBitLength(sorted[i] - sorted[i - 1] - 1);
    }

    final runs = <_PaletteRange>[];
    for (final color in sorted) {
      if (runs.isNotEmpty && runs.last.end + 1 == color) {
        runs[runs.length - 1] = _PaletteRange(runs.last.start, color);
      } else {
        runs.add(_PaletteRange(color, color));
      }
    }
    var rangeBits = _bitVarUintBitLength(0) +
        _fixedPaletteDescriptorBits +
        _compactUintBitLength(runs.length - 1);
    for (final run in runs) {
      rangeBits += globalBits + _compactUintBitLength(run.length - 1);
    }

    final compactBits = math.min(bitmapBits, math.min(deltaBits, rangeBits));
    if (legacyBits <= compactBits) {
      writer.writeBitVarUint(colors.length);
      _writePalette(writer, colors, profile);
      return colors;
    }

    writer.writeBitVarUint(0);
    if (bitmapBits <= deltaBits && bitmapBits <= rangeBits) {
      writer.writeBits(
        _fixedPaletteDescriptorBitmap,
        _fixedPaletteDescriptorBits,
      );
      final selected = sorted.toSet();
      for (var color = 0; color < _paletteSize(profile); color++) {
        writer.writeBits(selected.contains(color) ? 1 : 0, 1);
      }
    } else if (deltaBits <= rangeBits) {
      writer.writeBits(
        _fixedPaletteDescriptorSortedDelta,
        _fixedPaletteDescriptorBits,
      );
      writer
        ..writeBitVarUint(sorted.length)
        ..writeBits(sorted.first, globalBits);
      for (var i = 1; i < sorted.length; i++) {
        _writeCompactUint(writer, sorted[i] - sorted[i - 1] - 1);
      }
    } else {
      writer.writeBits(
        _fixedPaletteDescriptorRangeRuns,
        _fixedPaletteDescriptorBits,
      );
      _writeCompactUint(writer, runs.length - 1);
      for (final run in runs) {
        writer.writeBits(run.start, globalBits);
        _writeCompactUint(writer, run.length - 1);
      }
    }
    return sorted;
  }

  List<int> _readV2FixedPaletteDescriptor(
    _BitReader reader,
    PaletteProfile profile, {
    int? excludedColor,
  }) {
    if (!profile.isFixed) {
      throw const MCOImageInvalidPayloadException(
        'Fixed palette descriptor used with a dynamic profile',
      );
    }
    final descriptor = reader.readBits(_fixedPaletteDescriptorBits);
    final colors = <int>[];
    switch (descriptor) {
      case _fixedPaletteDescriptorBitmap:
        for (var color = 0; color < _paletteSize(profile); color++) {
          if (reader.readBits(1) != 0) colors.add(color);
        }
        break;
      case _fixedPaletteDescriptorSortedDelta:
        final count = reader.readBitVarUint();
        if (count <= 0 || count > _paletteSize(profile)) {
          throw const MCOImageInvalidPayloadException(
            'Invalid fixed delta palette size',
          );
        }
        colors.add(reader.readBits(_globalBits(profile)));
        while (colors.length < count) {
          colors.add(colors.last + _readCompactUint(reader) + 1);
        }
        break;
      case _fixedPaletteDescriptorRangeRuns:
        final runCount = _readCompactUint(reader) + 1;
        if (runCount > _paletteSize(profile)) {
          throw const MCOImageInvalidPayloadException(
            'Invalid fixed palette range count',
          );
        }
        for (var i = 0; i < runCount; i++) {
          final start = reader.readBits(_globalBits(profile));
          final length = _readCompactUint(reader) + 1;
          if (start + length > _paletteSize(profile) ||
              colors.length + length > _paletteSize(profile)) {
            throw const MCOImageInvalidPayloadException(
              'Invalid fixed palette range',
            );
          }
          for (var offset = 0; offset < length; offset++) {
            colors.add(start + offset);
          }
        }
        break;
      default:
        throw const MCOImageInvalidPayloadException(
          'Unsupported fixed palette descriptor',
        );
    }
    if (colors.isEmpty || colors.length > _paletteSize(profile)) {
      throw const MCOImageInvalidPayloadException(
        'Invalid compact fixed palette size',
      );
    }
    final seen = <int>{};
    for (final color in colors) {
      _validateColor(color, profile, 'localPalette', payload: true);
      if (color == excludedColor || !seen.add(color)) {
        throw const MCOImageInvalidPayloadException('Invalid local palette');
      }
    }
    return colors;
  }

  List<int> _readV2LocalPaletteBody(
    _BitReader reader,
    PaletteProfile profile,
    int k, {
    int? excludedColor,
  }) {
    final maxColors = _paletteSize(profile);
    if (k == 0 || k > maxColors) {
      throw const MCOImageInvalidPayloadException('Invalid local palette size');
    }
    final bits = _globalBits(profile);
    final colors = <int>[];
    final seen = <int>{};
    for (var i = 0; i < k; i++) {
      final color = reader.readBits(bits);
      _validateColor(color, profile, 'localPalette', payload: true);
      if (color == excludedColor || !seen.add(color)) {
        throw const MCOImageInvalidPayloadException('Invalid local palette');
      }
      colors.add(color);
    }
    return colors;
  }

  List<int> _buildDynamicLocalPalette(
    PaletteProfile profile,
    List<int> profileColorIds,
    int backgroundProfileColorId,
    DynamicPaletteReferenceEncoding referenceEncoding,
  ) {
    final counts = <int, int>{};
    for (final profileColorId in profileColorIds) {
      counts[profileColorId] = (counts[profileColorId] ?? 0) + 1;
    }
    final colors = counts.keys.toList();
    if (_usesSortedDynamicPalette(referenceEncoding)) {
      colors.sort();
      return colors;
    }
    colors.sort((a, b) {
      if (a == backgroundProfileColorId && b != backgroundProfileColorId) {
        return -1;
      }
      if (b == backgroundProfileColorId && a != backgroundProfileColorId) {
        return 1;
      }
      final byFrequency = counts[b]!.compareTo(counts[a]!);
      if (byFrequency != 0) return byFrequency;
      final aGlobal = _globalIndexForProfileColorId(profile, a);
      final bGlobal = _globalIndexForProfileColorId(profile, b);
      return aGlobal.compareTo(bGlobal);
    });
    return colors;
  }

  void _writeDynamicLocalPalette(
    _BitWriter writer,
    PaletteProfile profile,
    List<int> profileColorIds,
    DynamicPaletteReferenceEncoding referenceEncoding,
  ) {
    if (profileColorIds.isEmpty ||
        profileColorIds.length > _maxDynamicLocalPalette) {
      throw const MCOImageInvalidInputException(
        'Invalid dynamic local palette size',
      );
    }
    if (_usesExtendedDynamicPaletteDescriptor(referenceEncoding)) {
      writer.writeBitVarUint(0);
      _writeExtendedDynamicLocalPalette(
        writer,
        profile,
        profileColorIds,
        referenceEncoding,
      );
      return;
    }
    writer.writeBitVarUint(profileColorIds.length);
    _writeDynamicLocalPaletteBody(
      writer,
      profile,
      profileColorIds,
      referenceEncoding,
    );
  }

  void _writeDynamicLocalPaletteBody(
    _BitWriter writer,
    PaletteProfile profile,
    List<int> profileColorIds,
    DynamicPaletteReferenceEncoding referenceEncoding,
  ) {
    switch (referenceEncoding) {
      case DynamicPaletteReferenceEncoding.flat:
        final bits = _dynamicProfileColorBits(profile);
        for (final profileColorId in profileColorIds) {
          writer.writeBits(profileColorId, bits);
        }
        break;
      case DynamicPaletteReferenceEncoding.banked8x64:
        if (profile != PaletteProfile.dynamicGlobal512) {
          throw const MCOImageInvalidInputException(
            'Banked palette references require dynamicGlobal512',
          );
        }
        final banks =
            profileColorIds
                .map((globalIndex) => globalIndex >> 6)
                .toSet()
                .toList()
              ..sort();
        writer.writeBitVarUint(banks.length);
        for (final bank in banks) {
          writer.writeBits(bank, 3);
        }
        final bankBits = _bitsForChoiceCount(banks.length);
        for (final globalIndex in profileColorIds) {
          final bank = globalIndex >> 6;
          final offset = globalIndex & 0x3f;
          writer.writeBits(banks.indexOf(bank), bankBits);
          writer.writeBits(offset, 6);
        }
        break;
      case DynamicPaletteReferenceEncoding.sortedDelta:
      case DynamicPaletteReferenceEncoding.rangeRuns:
      case DynamicPaletteReferenceEncoding.profileBitmap:
      case DynamicPaletteReferenceEncoding.bankBitmaps:
        throw const MCOImageInvalidInputException(
          'Extended dynamic palette descriptor requires a zero marker',
        );
    }
  }

  void _writeExtendedDynamicLocalPalette(
    _BitWriter writer,
    PaletteProfile profile,
    List<int> profileColorIds,
    DynamicPaletteReferenceEncoding referenceEncoding,
  ) {
    _validateSortedDynamicPalette(profile, profileColorIds);
    switch (referenceEncoding) {
      case DynamicPaletteReferenceEncoding.sortedDelta:
        writer
          ..writeBits(
            _dynamicPaletteDescriptorSortedDelta,
            _dynamicPaletteDescriptorBits,
          )
          ..writeBits(profileColorIds.length - 1, 6)
          ..writeBits(
            profileColorIds.first,
            _dynamicProfileColorBits(profile),
          );
        for (var i = 1; i < profileColorIds.length; i++) {
          _writeCompactUint(
            writer,
            profileColorIds[i] - profileColorIds[i - 1] - 1,
          );
        }
        break;
      case DynamicPaletteReferenceEncoding.rangeRuns:
        final runs = _dynamicPaletteRuns(profileColorIds);
        writer.writeBits(
          _dynamicPaletteDescriptorRangeRuns,
          _dynamicPaletteDescriptorBits,
        );
        _writeCompactUint(writer, runs.length - 1);
        var previousEnd = -1;
        for (var i = 0; i < runs.length; i++) {
          final run = runs[i];
          if (i == 0) {
            writer.writeBits(run.start, _dynamicProfileColorBits(profile));
          } else {
            _writeCompactUint(writer, run.start - previousEnd - 1);
          }
          _writeCompactUint(writer, run.length - 1);
          previousEnd = run.start + run.length - 1;
        }
        break;
      case DynamicPaletteReferenceEncoding.profileBitmap:
        writer.writeBits(
          _dynamicPaletteDescriptorProfileBitmap,
          _dynamicPaletteDescriptorBits,
        );
        final colorSet = profileColorIds.toSet();
        for (var id = 0; id < _dynamicProfileSize(profile); id++) {
          writer.writeBits(colorSet.contains(id) ? 1 : 0, 1);
        }
        break;
      case DynamicPaletteReferenceEncoding.bankBitmaps:
        if (profile != PaletteProfile.dynamicGlobal512) {
          throw const MCOImageInvalidInputException(
            'Bank bitmaps require dynamicGlobal512',
          );
        }
        writer.writeBits(
          _dynamicPaletteDescriptorBankBitmaps,
          _dynamicPaletteDescriptorBits,
        );
        final colorSet = profileColorIds.toSet();
        final bankMask = profileColorIds.fold<int>(
          0,
          (mask, id) => mask | (1 << (id >> 6)),
        );
        writer.writeBits(bankMask, 8);
        for (var bank = 0; bank < 8; bank++) {
          if ((bankMask & (1 << bank)) == 0) continue;
          for (var offset = 0; offset < 64; offset++) {
            writer.writeBits(
              colorSet.contains((bank << 6) | offset) ? 1 : 0,
              1,
            );
          }
        }
        break;
      case DynamicPaletteReferenceEncoding.flat:
      case DynamicPaletteReferenceEncoding.banked8x64:
        throw const MCOImageInvalidInputException(
          'Legacy dynamic palette encoding is not an extended descriptor',
        );
    }
  }

  void _validateSortedDynamicPalette(
    PaletteProfile profile,
    List<int> profileColorIds,
  ) {
    if (profileColorIds.isEmpty ||
        profileColorIds.length > _maxDynamicLocalPalette) {
      throw const MCOImageInvalidInputException(
        'Invalid dynamic local palette size',
      );
    }
    final maxId = _dynamicProfileSize(profile) - 1;
    var previous = -1;
    for (final id in profileColorIds) {
      if (id <= previous || id > maxId) {
        throw const MCOImageInvalidInputException(
          'Extended dynamic palette must be sorted and unique',
        );
      }
      previous = id;
    }
  }

  List<({int start, int length})> _dynamicPaletteRuns(List<int> colors) {
    final runs = <({int start, int length})>[];
    var start = colors.first;
    var previous = start;
    for (var i = 1; i < colors.length; i++) {
      final color = colors[i];
      if (color == previous + 1) {
        previous = color;
        continue;
      }
      runs.add((start: start, length: previous - start + 1));
      start = color;
      previous = color;
    }
    runs.add((start: start, length: previous - start + 1));
    return runs;
  }

  _DynamicLocalPalette _readDynamicLocalPalette(
    _BitReader reader,
    PaletteProfile profile,
    DynamicPaletteReferenceEncoding referenceEncoding,
  ) {
    final length = reader.readBitVarUint();
    if (length == 0) {
      return _readExtendedDynamicLocalPalette(reader, profile);
    }
    return _readDynamicLocalPaletteBody(
      reader,
      profile,
      referenceEncoding,
      length,
    );
  }

  _DynamicLocalPalette _readDynamicLocalPaletteBody(
    _BitReader reader,
    PaletteProfile profile,
    DynamicPaletteReferenceEncoding referenceEncoding,
    int length,
  ) {
    if (length <= 0 || length > _maxDynamicLocalPalette) {
      throw const MCOImageInvalidPayloadException(
        'Invalid dynamic local palette size',
      );
    }
    final profileColorIds = switch (referenceEncoding) {
      DynamicPaletteReferenceEncoding.flat => _readDynamicFlatPaletteBody(
        reader,
        profile,
        length,
      ),
      DynamicPaletteReferenceEncoding.banked8x64 =>
        _readDynamicBankedPaletteBody(reader, profile, length),
      DynamicPaletteReferenceEncoding.sortedDelta ||
      DynamicPaletteReferenceEncoding.rangeRuns ||
      DynamicPaletteReferenceEncoding.profileBitmap ||
      DynamicPaletteReferenceEncoding.bankBitmaps =>
        throw const MCOImageInvalidPayloadException(
          'Extended dynamic palette requires a zero marker',
        ),
    };
    final globalColors = profileColorIds
        .map((profileColorId) {
          final globalIndex = _globalIndexForProfileColorId(
            profile,
            profileColorId,
          );
          _validateColor(
            globalIndex,
            profile,
            'dynamicLocalPalette',
            payload: true,
          );
          return globalIndex;
        })
        .toList(growable: false);
    return _DynamicLocalPalette(globalColors);
  }

  _DynamicLocalPalette _readExtendedDynamicLocalPalette(
    _BitReader reader,
    PaletteProfile profile,
  ) {
    final descriptor = reader.readBits(_dynamicPaletteDescriptorBits);
    final profileColorIds = switch (descriptor) {
      _dynamicPaletteDescriptorSortedDelta =>
        _readDynamicSortedDeltaPalette(reader, profile),
      _dynamicPaletteDescriptorRangeRuns =>
        _readDynamicRangePalette(reader, profile),
      _dynamicPaletteDescriptorProfileBitmap =>
        _readDynamicProfileBitmapPalette(reader, profile),
      _dynamicPaletteDescriptorBankBitmaps =>
        _readDynamicBankBitmapsPalette(reader, profile),
      _ => throw const MCOImageInvalidPayloadException(
        'Unknown dynamic palette descriptor',
      ),
    };
    final globalColors = profileColorIds
        .map((id) => _globalIndexForProfileColorId(profile, id))
        .toList(growable: false);
    return _DynamicLocalPalette(globalColors);
  }

  List<int> _readDynamicSortedDeltaPalette(
    _BitReader reader,
    PaletteProfile profile,
  ) {
    final length = reader.readBits(6) + 1;
    final maxId = _dynamicProfileSize(profile) - 1;
    final colors = <int>[
      reader.readBits(_dynamicProfileColorBits(profile)),
    ];
    if (colors.first > maxId) {
      throw const MCOImageInvalidPayloadException(
        'Dynamic palette color id is out of range',
      );
    }
    while (colors.length < length) {
      final next = colors.last + _readCompactUint(reader) + 1;
      if (next > maxId) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic palette delta is out of range',
        );
      }
      colors.add(next);
    }
    return colors;
  }

  List<int> _readDynamicRangePalette(
    _BitReader reader,
    PaletteProfile profile,
  ) {
    final runCount = _readCompactUint(reader) + 1;
    if (runCount <= 0 || runCount > _maxDynamicLocalPalette) {
      throw const MCOImageInvalidPayloadException(
        'Invalid dynamic palette range count',
      );
    }
    final maxId = _dynamicProfileSize(profile) - 1;
    final colors = <int>[];
    var previousEnd = -1;
    for (var i = 0; i < runCount; i++) {
      final start = i == 0
          ? reader.readBits(_dynamicProfileColorBits(profile))
          : previousEnd + _readCompactUint(reader) + 1;
      final length = _readCompactUint(reader) + 1;
      final end = start + length - 1;
      if (start <= previousEnd || end > maxId) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic palette range is out of bounds',
        );
      }
      if (colors.length + length > _maxDynamicLocalPalette) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic palette has too many colors',
        );
      }
      for (var color = start; color <= end; color++) {
        colors.add(color);
      }
      previousEnd = end;
    }
    return colors;
  }

  List<int> _readDynamicProfileBitmapPalette(
    _BitReader reader,
    PaletteProfile profile,
  ) {
    final colors = <int>[];
    for (var id = 0; id < _dynamicProfileSize(profile); id++) {
      if (reader.readBits(1) != 0) colors.add(id);
    }
    _validateDecodedDynamicPaletteSize(colors);
    return colors;
  }

  List<int> _readDynamicBankBitmapsPalette(
    _BitReader reader,
    PaletteProfile profile,
  ) {
    if (profile != PaletteProfile.dynamicGlobal512) {
      throw const MCOImageInvalidPayloadException(
        'Bank bitmaps require dynamicGlobal512',
      );
    }
    final bankMask = reader.readBits(8);
    if (bankMask == 0) {
      throw const MCOImageInvalidPayloadException(
        'Dynamic bank bitmap is empty',
      );
    }
    final colors = <int>[];
    for (var bank = 0; bank < 8; bank++) {
      if ((bankMask & (1 << bank)) == 0) continue;
      final beforeBank = colors.length;
      for (var offset = 0; offset < 64; offset++) {
        if (reader.readBits(1) != 0) {
          colors.add((bank << 6) | offset);
        }
      }
      if (colors.length == beforeBank) {
        throw const MCOImageInvalidPayloadException(
          'Dynamic bank bitmap contains an empty bank',
        );
      }
    }
    _validateDecodedDynamicPaletteSize(colors);
    return colors;
  }

  void _validateDecodedDynamicPaletteSize(List<int> colors) {
    if (colors.isEmpty || colors.length > _maxDynamicLocalPalette) {
      throw const MCOImageInvalidPayloadException(
        'Invalid dynamic local palette size',
      );
    }
  }

  List<int> _readDynamicFlatPaletteBody(
    _BitReader reader,
    PaletteProfile profile,
    int length,
  ) {
    final bits = _dynamicProfileColorBits(profile);
    final maxProfileColorId = _dynamicProfileSize(profile) - 1;
    final seen = <int>{};
    final colors = <int>[];
    for (var i = 0; i < length; i++) {
      final profileColorId = reader.readBits(bits);
      if (profileColorId > maxProfileColorId || !seen.add(profileColorId)) {
        throw const MCOImageInvalidPayloadException(
          'Invalid dynamic local palette',
        );
      }
      colors.add(profileColorId);
    }
    return colors;
  }

  List<int> _readDynamicBankedPaletteBody(
    _BitReader reader,
    PaletteProfile profile,
    int length,
  ) {
    if (profile != PaletteProfile.dynamicGlobal512) {
      throw const MCOImageInvalidPayloadException(
        'Banked palette references require dynamicGlobal512',
      );
    }
    final bankCount = reader.readBitVarUint();
    if (bankCount <= 0 || bankCount > 8) {
      throw const MCOImageInvalidPayloadException('Invalid bank count');
    }
    final banks = <int>[];
    final seenBanks = <int>{};
    for (var i = 0; i < bankCount; i++) {
      final bank = reader.readBits(3);
      if (!seenBanks.add(bank)) {
        throw const MCOImageInvalidPayloadException('Duplicate bank index');
      }
      banks.add(bank);
    }
    final bankBits = _bitsForChoiceCount(bankCount);
    final seenColors = <int>{};
    final colors = <int>[];
    for (var i = 0; i < length; i++) {
      final bankLocalIndex = reader.readBits(bankBits);
      if (bankLocalIndex >= banks.length) {
        throw const MCOImageInvalidPayloadException(
          'Bank local index out of range',
        );
      }
      final offset = reader.readBits(6);
      final globalIndex = (banks[bankLocalIndex] << 6) | offset;
      if (globalIndex >= 512 || !seenColors.add(globalIndex)) {
        throw const MCOImageInvalidPayloadException(
          'Invalid banked dynamic color',
        );
      }
      colors.add(globalIndex);
    }
    return colors;
  }

  static List<_BackgroundCandidate> _dynamicBackgroundCandidates(
    MCOImage image,
    int? explicitBackground, {
    bool exhaustiveSmallImage = false,
  }) {
    final result = <_BackgroundCandidate>[];
    final seen = <int>{};

    void add(int color, int rank) {
      if (_profileColorIdForGlobalIndex(image.paletteProfile, color) == null) {
        return;
      }
      if (!seen.add(color)) return;
      result.add(_BackgroundCandidate(color, rank));
    }

    if (explicitBackground != null) add(explicitBackground, 0);
    add(MCOImageDynamicPalette.whiteGlobalIndexFor(image.paletteProfile), 1);

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

  static List<_BackgroundCandidate> _backgroundCandidatesFromPublic(
    List<MCOImageBackgroundCandidate> candidates,
  ) {
    final result = <_BackgroundCandidate>[];
    final seen = <int>{};
    for (final candidate in candidates) {
      if (!seen.add(candidate.color)) continue;
      result.add(_BackgroundCandidate(candidate.color, candidate.rank));
    }
    return result;
  }

  static bool _isBetterCandidate(
    EncodedMCOImage candidate,
    EncodedMCOImage? current,
    MCOImageOutputTarget outputTarget,
  ) {
    if (current == null) return true;
    final candidateLength = outputTarget == MCOImageOutputTarget.binary
        ? candidate.byteLength
        : candidate.charLength;
    final currentLength = outputTarget == MCOImageOutputTarget.binary
        ? current.byteLength
        : current.charLength;
    if (candidateLength != currentLength) {
      return candidateLength < currentLength;
    }
    if (candidate.backgroundRank != current.backgroundRank) {
      return candidate.backgroundRank < current.backgroundRank;
    }
    if (candidate.boundsPresent != current.boundsPresent) {
      return candidate.boundsPresent;
    }
    final candidateContainerRank = _containerRank(candidate);
    final currentContainerRank = _containerRank(current);
    if (candidateContainerRank != currentContainerRank) {
      return candidateContainerRank < currentContainerRank;
    }
    final candidateRank = _modeTieOrder.indexOf(candidate.mode);
    final currentRank = _modeTieOrder.indexOf(current.mode);
    if (candidateRank != currentRank) return candidateRank < currentRank;
    return candidate.scan.index < current.scan.index;
  }

  static int _containerRank(EncodedMCOImage candidate) {
    if (candidate.boundsPresent) return 0;
    if (candidate.mode == ImageMode.regionsBg) return 2;
    return 1;
  }

  static List<int> _toScanOrder(
    List<int> pixels,
    int width,
    int height,
    ScanMode scan,
  ) {
    return _scanPositions(width, height, scan).map((i) => pixels[i]).toList();
  }

  static List<int> _fromScanOrder(
    List<int> linear,
    int width,
    int height,
    ScanMode scan,
  ) {
    final result = List<int>.filled(width * height, 0);
    final positions = _scanPositions(width, height, scan);
    for (var i = 0; i < linear.length; i++) {
      result[positions[i]] = linear[i];
    }
    return result;
  }

  static List<int> _scanPositions(int width, int height, ScanMode scan) {
    final positions = <int>[];
    switch (scan) {
      case ScanMode.h:
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            positions.add(y * width + x);
          }
        }
        break;
      case ScanMode.v:
        for (var x = 0; x < width; x++) {
          for (var y = 0; y < height; y++) {
            positions.add(y * width + x);
          }
        }
        break;
      case ScanMode.s:
        for (var y = 0; y < height; y++) {
          final xs = y.isEven
              ? Iterable<int>.generate(width)
              : Iterable<int>.generate(width, (i) => width - 1 - i);
          for (final x in xs) {
            positions.add(y * width + x);
          }
        }
        break;
      case ScanMode.sv:
        for (var x = 0; x < width; x++) {
          final ys = x.isEven
              ? Iterable<int>.generate(height)
              : Iterable<int>.generate(height, (i) => height - 1 - i);
          for (final y in ys) {
            positions.add(y * width + x);
          }
        }
        break;
    }
    return positions;
  }

  static _LocalPalette _buildLocalPalette(
    List<int> pixels, {
    int? preferredFirstColor,
  }) {
    final counts = <int, int>{};
    for (final pixel in pixels) {
      counts[pixel] = (counts[pixel] ?? 0) + 1;
    }
    final colors = counts.keys.toList()
      ..sort((a, b) {
        if (preferredFirstColor != null) {
          final aPreferred = a == preferredFirstColor;
          final bPreferred = b == preferredFirstColor;
          if (aPreferred && !bPreferred) return -1;
          if (bPreferred && !aPreferred) return 1;
        }
        final byFrequency = counts[b]!.compareTo(counts[a]!);
        return byFrequency != 0 ? byFrequency : a.compareTo(b);
      });
    return _LocalPalette(colors);
  }

  static Map<int, int> _localIndexMap(List<int> colors) {
    return {for (var i = 0; i < colors.length; i++) colors[i]: i};
  }

  static List<_Run> _buildRuns(List<int> pixels) {
    final runs = <_Run>[];
    if (pixels.isEmpty) return runs;
    var color = pixels.first;
    var length = 1;
    for (var i = 1; i < pixels.length; i++) {
      if (pixels[i] == color) {
        length++;
      } else {
        runs.add(_Run(color, length));
        color = pixels[i];
        length = 1;
      }
    }
    runs.add(_Run(color, length));
    return runs;
  }

  int? _biColorForeground(List<int> pixels, int background) {
    int? foreground;
    for (final pixel in pixels) {
      if (pixel == background) continue;
      foreground ??= pixel;
      if (pixel != foreground) return null;
    }
    return foreground;
  }

  void _writeBiColorMask(
    _BitWriter writer,
    List<int> pixels,
    int background,
    int foreground,
  ) {
    for (final pixel in pixels) {
      if (pixel == background) {
        writer.writeBits(0, 1);
      } else if (pixel == foreground) {
        writer.writeBits(1, 1);
      } else {
        throw const MCOImageInvalidInputException(
          'BI_COLOR_MASK cannot encode more than two colors',
        );
      }
    }
  }

  List<int> _readBiColorMask(
    _BitReader reader,
    int count,
    int background,
    int foreground,
  ) {
    return List<int>.generate(count, (_) {
      return reader.readBits(1) == 0 ? background : foreground;
    });
  }

  static const int _rowDeltaOpBits = 2;
  static const int _rowDeltaOpRaw = 0;
  static const int _rowDeltaOpRepeat = 1;
  static const int _rowDeltaOpDelta = 2;
  static const int _rowDeltaOpExtended = 3;
  static const int _rowDeltaExtendedBits = 2;
  static const int _rowDeltaExtendedMask = 0;
  static const int _rowDeltaExtendedSegment = 1;
  static const int _rowDeltaExtendedSameColorMask = 2;
  static const int _rowDeltaPredictorBits = 2;
  static const int _rowDeltaPredictorSame = 0;
  static const int _rowDeltaPredictorLeft = 1;
  static const int _rowDeltaPredictorRight = 2;
  static const int _compactRowDeltaOpBits = 3;
  static const int _compactRowDeltaOpRepeat = 0;
  static const int _compactRowDeltaOpRaw = 1;
  static const int _compactRowDeltaOpIndexed = 2;
  static const int _compactRowDeltaOpSameScalar = 3;
  static const int _compactRowDeltaOpSegments = 4;
  static const int _compactRowDeltaOpTrimmedMask = 5;
  static const int _compactRowDeltaOpRepeatRun = 6;
  static const int _compactRowDeltaOpPredicted = 7;

  void _writeCompactRowDeltaBody(
    _BitWriter writer,
    List<int> values,
    int rowLength,
    int valueBits, {
    required bool directGrayscale,
  }) {
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
        writer.writeBits(
          _compactRowDeltaOpRepeatRun,
          _compactRowDeltaOpBits,
        );
        _writeCompactUint(writer, repeatCount - 2);
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

  int _compactRowDeltaBodyBitCost(
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
            _compactUintBitLength(repeatCount - 2);
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

  int _compactRepeatedRowCount(
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

  _CompactRowDeltaDecision _bestCompactRowDeltaDecision(
    List<int> values,
    int rowLength,
    int valueBits,
    int row, {
    required bool useVirtualBaseRow,
    required bool directGrayscale,
  }) {
    _CompactRowDeltaDecision best = _CompactRowDeltaDecision(
      op: _compactRowDeltaOpRaw,
      predictor: _rowDeltaPredictorSame,
      changes: const <_RowDeltaChange>[],
      useResidual: false,
      bitCost: _compactRowDeltaOpBits + rowLength * valueBits,
    );
    for (final predictor in _rowDeltaPredictorsForRow(
      row,
      useVirtualBaseRow: useVirtualBaseRow,
      allowShiftPredictors: true,
    )) {
      final changes = _rowDeltaChanges(
        values,
        rowLength,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
        predictor: predictor,
      );
      if (changes.isEmpty) {
        final decision = _CompactRowDeltaDecision(
          op: predictor == _rowDeltaPredictorSame
              ? _compactRowDeltaOpRepeat
              : _compactRowDeltaOpPredicted,
          predictor: predictor,
          changes: changes,
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
      final positionCost = _compactChangePositionsBitCost(changes);
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
      final indexed = _CompactRowDeltaDecision(
        op: _compactRowDeltaOpIndexed,
        predictor: predictor,
        changes: changes,
        useResidual: valuesEncoding.useResidual,
        bitCost: _compactRowDeltaOpBits +
            predictorCost +
            _compactUintBitLength(changes.length - 1) +
            positionCost +
            valuesEncoding.bitCost,
      );
      if (indexed.bitCost < best.bitCost) best = indexed;

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
        final decision = _CompactRowDeltaDecision(
          op: _compactRowDeltaOpSameScalar,
          predictor: predictor,
          changes: changes,
          useResidual: sameScalar.useResidual,
          bitCost: _compactRowDeltaOpBits +
              predictorCost +
              _compactUintBitLength(changes.length - 1) +
              positionCost +
              sameScalar.bitCost,
        );
        if (decision.bitCost < best.bitCost) best = decision;
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
      final segmentDecision = _CompactRowDeltaDecision(
        op: _compactRowDeltaOpSegments,
        predictor: predictor,
        changes: changes,
        useResidual: valuesEncoding.useResidual,
        bitCost: _compactRowDeltaOpBits +
            predictorCost +
            segmentGeometryCost +
            valuesEncoding.bitCost,
      );
      if (segmentDecision.bitCost < best.bitCost) best = segmentDecision;

      final span = changes.last.x - changes.first.x + 1;
      final maskDecision = _CompactRowDeltaDecision(
        op: _compactRowDeltaOpTrimmedMask,
        predictor: predictor,
        changes: changes,
        useResidual: valuesEncoding.useResidual,
        bitCost: _compactRowDeltaOpBits +
            predictorCost +
            _compactUintBitLength(changes.first.x) +
            _compactUintBitLength(span - 1) +
            span +
            valuesEncoding.bitCost,
      );
      if (maskDecision.bitCost < best.bitCost) best = maskDecision;
    }
    return best;
  }

  int _compactPredictorBitCost(int predictor) {
    return predictor == _rowDeltaPredictorSame ? 1 : 2;
  }

  int _compactChangePositionsBitCost(List<_RowDeltaChange> changes) {
    var cost = 0;
    var previousX = -1;
    for (final change in changes) {
      cost += _compactUintBitLength(change.x - previousX - 1);
      previousX = change.x;
    }
    return cost;
  }

  _CompactValueEncoding _bestCompactValueEncoding(
    List<int> values,
    int rowLength,
    int row,
    List<_RowDeltaChange> changes,
    int valueBits,
    int predictor, {
    required bool useVirtualBaseRow,
    required bool directGrayscale,
  }) {
    final absoluteCost = changes.length * valueBits;
    if (!directGrayscale) {
      return _CompactValueEncoding(false, absoluteCost);
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
        ? _CompactValueEncoding(true, 1 + residualCost)
        : _CompactValueEncoding(false, 1 + absoluteCost);
  }

  _CompactValueEncoding? _bestCompactSameScalarEncoding(
    List<int> values,
    int rowLength,
    int row,
    List<_RowDeltaChange> changes,
    int valueBits,
    int predictor, {
    required bool useVirtualBaseRow,
    required bool directGrayscale,
  }) {
    final absoluteValue = _sameRowDeltaChangeValue(changes);
    _CompactValueEncoding? best;
    if (absoluteValue != null) {
      best = _CompactValueEncoding(false, valueBits + (directGrayscale ? 1 : 0));
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
    final residual = _CompactValueEncoding(
      true,
      1 + _compactUintBitLength(_grayscaleDeltaCode(sharedDelta!) - 1),
    );
    return best == null || residual.bitCost < best.bitCost ? residual : best;
  }

  int _compactGrayscaleDelta(
    List<int> values,
    int rowLength,
    int row,
    _RowDeltaChange change,
    int predictor, {
    required bool useVirtualBaseRow,
  }) {
    final predicted = _rowDeltaPredictedValue(
      values,
      rowLength,
      row,
      change.x,
      row * rowLength - rowLength,
      useVirtualBaseRow: useVirtualBaseRow,
      predictor: predictor,
    );
    return change.value - predicted;
  }

  static int _grayscaleDeltaCode(int delta) {
    if (delta == 0) {
      throw const MCOImageInvalidInputException('Zero grayscale delta');
    }
    return delta > 0 ? delta * 2 - 1 : -delta * 2;
  }

  void _writeCompactRowDeltaDecision(
    _BitWriter writer,
    List<int> values,
    int rowLength,
    int valueBits,
    int row,
    _CompactRowDeltaDecision decision, {
    required bool useVirtualBaseRow,
    required bool directGrayscale,
  }) {
    writer.writeBits(decision.op, _compactRowDeltaOpBits);
    if (decision.op == _compactRowDeltaOpRepeat) return;
    if (decision.op == _compactRowDeltaOpRaw) {
      final rowStart = row * rowLength;
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
        _writeCompactUint(writer, changes.length - 1);
        _writeCompactChangePositions(writer, changes);
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
        _writeCompactUint(writer, changes.length - 1);
        _writeCompactChangePositions(writer, changes);
        if (decision.useResidual) {
          final delta = _compactGrayscaleDelta(
            values,
            rowLength,
            row,
            changes.first,
            decision.predictor,
            useVirtualBaseRow: useVirtualBaseRow,
          );
          _writeCompactUint(writer, _grayscaleDeltaCode(delta) - 1);
        } else {
          writer.writeBits(changes.first.value, valueBits);
        }
        break;
      case _compactRowDeltaOpSegments:
        final segments = _rowDeltaSegments(changes);
        _writeCompactUint(writer, segments.length - 1);
        var previousEnd = 0;
        for (var i = 0; i < segments.length; i++) {
          final segment = segments[i];
          _writeCompactUint(
            writer,
            i == 0 ? segment.x : segment.x - previousEnd,
          );
          _writeCompactUint(writer, segment.length - 1);
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
        _writeCompactUint(writer, start);
        _writeCompactUint(writer, span - 1);
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

  void _writeCompactRowDeltaPredictor(_BitWriter writer, int predictor) {
    if (predictor == _rowDeltaPredictorSame) {
      writer.writeBits(0, 1);
      return;
    }
    writer
      ..writeBits(1, 1)
      ..writeBits(predictor == _rowDeltaPredictorLeft ? 0 : 1, 1);
  }

  void _writeCompactChangePositions(
    _BitWriter writer,
    List<_RowDeltaChange> changes,
  ) {
    var previousX = -1;
    for (final change in changes) {
      _writeCompactUint(writer, change.x - previousX - 1);
      previousX = change.x;
    }
  }

  void _writeCompactChangedValues(
    _BitWriter writer,
    List<int> values,
    int rowLength,
    int valueBits,
    int row,
    List<_RowDeltaChange> changes,
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
        _writeCompactUint(writer, _grayscaleDeltaCode(delta) - 1);
      } else {
        writer.writeBits(change.value, valueBits);
      }
    }
  }

  void _writeRowRepeatBody(
    _BitWriter writer,
    List<int> localPixels,
    int rowLength,
    int localBits,
  ) {
    if (rowLength <= 0 || localPixels.length % rowLength != 0) {
      throw const MCOImageInvalidInputException('Invalid row-repeat geometry');
    }
    if (localPixels.isEmpty) return;

    for (var x = 0; x < rowLength; x++) {
      writer.writeBits(localPixels[x], localBits);
    }

    final rowCount = localPixels.length ~/ rowLength;
    for (var row = 1; row < rowCount; row++) {
      final rowStart = row * rowLength;
      final previousStart = rowStart - rowLength;
      var sameAsPrevious = true;
      for (var x = 0; x < rowLength; x++) {
        if (localPixels[rowStart + x] != localPixels[previousStart + x]) {
          sameAsPrevious = false;
          break;
        }
      }

      if (sameAsPrevious) {
        writer.writeBits(1, 1);
      } else {
        writer.writeBits(0, 1);
        for (var x = 0; x < rowLength; x++) {
          writer.writeBits(localPixels[rowStart + x], localBits);
        }
      }
    }
  }

  List<int> _readRowRepeatBody(
    _BitReader reader,
    int count,
    int rowLength,
    int localBits,
  ) {
    if (rowLength <= 0 || count % rowLength != 0) {
      throw const MCOImageInvalidPayloadException(
        'Invalid row-repeat geometry',
      );
    }
    if (count == 0) return const <int>[];

    final result = List<int>.filled(count, 0);
    for (var x = 0; x < rowLength; x++) {
      result[x] = reader.readBits(localBits);
    }

    final rowCount = count ~/ rowLength;
    for (var row = 1; row < rowCount; row++) {
      final rowStart = row * rowLength;
      final previousStart = rowStart - rowLength;
      final repeatPrevious = reader.readBits(1) != 0;
      if (repeatPrevious) {
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

  void _writeRowDeltaBody(
    _BitWriter writer,
    List<int> localPixels,
    int rowLength,
    int localBits,
  ) {
    if (rowLength <= 0 || localPixels.length % rowLength != 0) {
      throw const MCOImageInvalidInputException('Invalid row-delta geometry');
    }
    if (localPixels.isEmpty) return;

    final noShiftCost = _rowDeltaBodyBitCost(
      localPixels,
      rowLength,
      localBits,
      allowShiftPredictors: false,
    );
    final shiftCost = _rowDeltaBodyBitCost(
      localPixels,
      rowLength,
      localBits,
      allowShiftPredictors: true,
    );
    final allowShiftPredictors = shiftCost.bestCost < noShiftCost.bestCost;
    final rawFirstCost = allowShiftPredictors
        ? shiftCost.rawFirstCost
        : noShiftCost.rawFirstCost;
    final virtualBaseCost = allowShiftPredictors
        ? shiftCost.virtualBaseCost
        : noShiftCost.virtualBaseCost;
    final useVirtualBaseRow = virtualBaseCost < rawFirstCost;

    writer
      ..writeBits(useVirtualBaseRow ? 1 : 0, 1)
      ..writeBits(allowShiftPredictors ? 1 : 0, 1);
    _writeRowDeltaBodyVariant(
      writer,
      localPixels,
      rowLength,
      localBits,
      useVirtualBaseRow: useVirtualBaseRow,
      allowShiftPredictors: allowShiftPredictors,
    );
  }

  _RowDeltaBodyCost _rowDeltaBodyBitCost(
    List<int> localPixels,
    int rowLength,
    int localBits, {
    required bool allowShiftPredictors,
  }) {
    final rawFirstCost = _rowDeltaBodyVariantBitCost(
      localPixels,
      rowLength,
      localBits,
      useVirtualBaseRow: false,
      allowShiftPredictors: allowShiftPredictors,
    );
    final virtualBaseCost = _rowDeltaBodyVariantBitCost(
      localPixels,
      rowLength,
      localBits,
      useVirtualBaseRow: true,
      allowShiftPredictors: allowShiftPredictors,
    );
    return _RowDeltaBodyCost(
      rawFirstCost: rawFirstCost,
      virtualBaseCost: virtualBaseCost,
    );
  }

  int _rowDeltaBodyVariantBitCost(
    List<int> localPixels,
    int rowLength,
    int localBits, {
    required bool useVirtualBaseRow,
    required bool allowShiftPredictors,
  }) {
    var bits = 0;
    final rowCount = localPixels.length ~/ rowLength;
    final firstDeltaRow = useVirtualBaseRow ? 0 : 1;
    if (!useVirtualBaseRow) {
      bits += rowLength * localBits;
    }

    for (var row = firstDeltaRow; row < rowCount; row++) {
      final decision = _bestRowDeltaDecision(
        localPixels,
        rowLength,
        localBits,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
        allowShiftPredictors: allowShiftPredictors,
      );
      bits += decision.bitCost;
    }
    return bits;
  }

  void _writeRowDeltaBodyVariant(
    _BitWriter writer,
    List<int> localPixels,
    int rowLength,
    int localBits, {
    required bool useVirtualBaseRow,
    required bool allowShiftPredictors,
  }) {
    final rowCount = localPixels.length ~/ rowLength;
    final firstDeltaRow = useVirtualBaseRow ? 0 : 1;

    if (!useVirtualBaseRow) {
      for (var x = 0; x < rowLength; x++) {
        writer.writeBits(localPixels[x], localBits);
      }
    }

    for (var row = firstDeltaRow; row < rowCount; row++) {
      final rowStart = row * rowLength;
      final decision = _bestRowDeltaDecision(
        localPixels,
        rowLength,
        localBits,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
        allowShiftPredictors: allowShiftPredictors,
      );
      final changes = decision.changes;

      if (changes.isEmpty && decision.op == _rowDeltaOpRepeat) {
        writer.writeBits(_rowDeltaOpRepeat, _rowDeltaOpBits);
        continue;
      }

      switch (decision.op) {
        case _rowDeltaOpRaw:
          writer.writeBits(_rowDeltaOpRaw, _rowDeltaOpBits);
          for (var x = 0; x < rowLength; x++) {
            writer.writeBits(localPixels[rowStart + x], localBits);
          }
          break;
        case _rowDeltaOpDelta:
          writer.writeBits(_rowDeltaOpDelta, _rowDeltaOpBits);
          _writeRowDeltaPredictorIfNeeded(
            writer,
            decision.predictor,
            allowShiftPredictors,
          );
          final positionBits = _bitsForChoiceCount(rowLength);
          writer.writeBitVarUint(changes.length);
          var previousX = -1;
          for (final change in changes) {
            if (change.x <= previousX) {
              throw const MCOImageInvalidInputException(
                'Invalid row-delta change order',
              );
            }
            writer.writeBits(change.x, positionBits);
            writer.writeBits(change.value, localBits);
            previousX = change.x;
          }
          break;
        case _rowDeltaOpExtended:
          writer.writeBits(_rowDeltaOpExtended, _rowDeltaOpBits);
          _writeRowDeltaPredictorIfNeeded(
            writer,
            decision.predictor,
            allowShiftPredictors,
          );
          writer.writeBits(decision.extendedOp, _rowDeltaExtendedBits);
          switch (decision.extendedOp) {
            case _rowDeltaExtendedMask:
              _writeRowDeltaMaskRow(writer, changes, rowLength, localBits);
              break;
            case _rowDeltaExtendedSegment:
              _writeRowDeltaSegmentRow(writer, changes, rowLength, localBits);
              break;
            case _rowDeltaExtendedSameColorMask:
              _writeRowDeltaSameColorMaskRow(
                writer,
                changes,
                rowLength,
                localBits,
              );
              break;
            default:
              throw const MCOImageInvalidInputException(
                'Invalid row-delta extended op',
              );
          }
          break;
        default:
          throw const MCOImageInvalidInputException('Invalid row-delta op');
      }
    }
  }

  void _writeRowDeltaPredictorIfNeeded(
    _BitWriter writer,
    int predictor,
    bool allowShiftPredictors,
  ) {
    if (!allowShiftPredictors) return;
    writer.writeBits(predictor, _rowDeltaPredictorBits);
  }

  void _writeRowDeltaMaskRow(
    _BitWriter writer,
    List<_RowDeltaChange> changes,
    int rowLength,
    int localBits,
  ) {
    var changeIndex = 0;
    for (var x = 0; x < rowLength; x++) {
      final isChanged =
          changeIndex < changes.length && changes[changeIndex].x == x;
      writer.writeBits(isChanged ? 1 : 0, 1);
      if (isChanged) changeIndex++;
    }
    for (final change in changes) {
      writer.writeBits(change.value, localBits);
    }
  }

  void _writeRowDeltaSameColorMaskRow(
    _BitWriter writer,
    List<_RowDeltaChange> changes,
    int rowLength,
    int localBits,
  ) {
    final value = _sameRowDeltaChangeValue(changes);
    if (value == null) {
      throw const MCOImageInvalidInputException(
        'Row-delta changes are not same-color',
      );
    }
    var changeIndex = 0;
    for (var x = 0; x < rowLength; x++) {
      final isChanged =
          changeIndex < changes.length && changes[changeIndex].x == x;
      writer.writeBits(isChanged ? 1 : 0, 1);
      if (isChanged) changeIndex++;
    }
    writer.writeBits(value, localBits);
  }

  void _writeRowDeltaSegmentRow(
    _BitWriter writer,
    List<_RowDeltaChange> changes,
    int rowLength,
    int localBits,
  ) {
    final segments = _rowDeltaSegments(changes);
    final positionBits = _bitsForChoiceCount(rowLength);
    final lengthBits = _bitsForChoiceCount(rowLength);
    writer.writeBitVarUint(segments.length);
    for (final segment in segments) {
      writer.writeBits(segment.x, positionBits);
      writer.writeBits(segment.length - 1, lengthBits);
      for (final value in segment.values) {
        writer.writeBits(value, localBits);
      }
    }
  }

  List<_RowDeltaChange> _rowDeltaChanges(
    List<int> localPixels,
    int rowLength,
    int row, {
    required bool useVirtualBaseRow,
    required int predictor,
  }) {
    final rowStart = row * rowLength;
    final previousStart = rowStart - rowLength;
    final changes = <_RowDeltaChange>[];
    for (var x = 0; x < rowLength; x++) {
      final previousValue = _rowDeltaPredictedValue(
        localPixels,
        rowLength,
        row,
        x,
        previousStart,
        useVirtualBaseRow: useVirtualBaseRow,
        predictor: predictor,
      );
      final value = localPixels[rowStart + x];
      if (value != previousValue) {
        changes.add(_RowDeltaChange(x, value));
      }
    }
    return changes;
  }

  int _rowDeltaPredictedValue(
    List<int> localPixels,
    int rowLength,
    int row,
    int x,
    int previousStart, {
    required bool useVirtualBaseRow,
    required int predictor,
  }) {
    if (row == 0 && useVirtualBaseRow) return 0;

    final sourceX = switch (predictor) {
      _rowDeltaPredictorSame => x,
      _rowDeltaPredictorLeft => x + 1,
      _rowDeltaPredictorRight => x - 1,
      _ => throw const MCOImageInvalidInputException(
        'Invalid row-delta predictor',
      ),
    };

    if (sourceX < 0 || sourceX >= rowLength) return 0;
    return localPixels[previousStart + sourceX];
  }

  List<_RowDeltaSegment> _rowDeltaSegments(List<_RowDeltaChange> changes) {
    if (changes.isEmpty) return const <_RowDeltaSegment>[];

    final segments = <_RowDeltaSegment>[];
    var startX = changes.first.x;
    var values = <int>[changes.first.value];
    var previousX = startX;

    for (var i = 1; i < changes.length; i++) {
      final change = changes[i];
      if (change.x == previousX + 1) {
        values.add(change.value);
      } else {
        segments.add(_RowDeltaSegment(startX, List<int>.unmodifiable(values)));
        startX = change.x;
        values = <int>[change.value];
      }
      previousX = change.x;
    }

    segments.add(_RowDeltaSegment(startX, List<int>.unmodifiable(values)));
    return segments;
  }

  _RowDeltaDecision _bestRowDeltaDecision(
    List<int> localPixels,
    int rowLength,
    int localBits,
    int row, {
    required bool useVirtualBaseRow,
    required bool allowShiftPredictors,
  }) {
    _RowDeltaDecision? best;
    for (final predictor in _rowDeltaPredictorsForRow(
      row,
      useVirtualBaseRow: useVirtualBaseRow,
      allowShiftPredictors: allowShiftPredictors,
    )) {
      final changes = _rowDeltaChanges(
        localPixels,
        rowLength,
        row,
        useVirtualBaseRow: useVirtualBaseRow,
        predictor: predictor,
      );
      final decision = _rowDeltaDecisionForChanges(
        changes,
        rowLength,
        localBits,
        predictor,
        allowShiftPredictors: allowShiftPredictors,
      );
      if (best == null || decision.bitCost < best.bitCost) {
        best = decision;
      }
    }
    return best!;
  }

  List<int> _rowDeltaPredictorsForRow(
    int row, {
    required bool useVirtualBaseRow,
    required bool allowShiftPredictors,
  }) {
    if (!allowShiftPredictors || (row == 0 && useVirtualBaseRow)) {
      return const <int>[_rowDeltaPredictorSame];
    }
    return const <int>[
      _rowDeltaPredictorSame,
      _rowDeltaPredictorLeft,
      _rowDeltaPredictorRight,
    ];
  }

  _RowDeltaDecision _rowDeltaDecisionForChanges(
    List<_RowDeltaChange> changes,
    int rowLength,
    int localBits,
    int predictor, {
    required bool allowShiftPredictors,
  }) {
    final predictorBits = allowShiftPredictors ? _rowDeltaPredictorBits : 0;
    if (changes.isEmpty) {
      if (!allowShiftPredictors || predictor == _rowDeltaPredictorSame) {
        return _RowDeltaDecision(
          op: _rowDeltaOpRepeat,
          extendedOp: -1,
          predictor: _rowDeltaPredictorSame,
          changes: changes,
          bitCost: _rowDeltaOpBits,
        );
      }
      return _RowDeltaDecision(
        op: _rowDeltaOpDelta,
        extendedOp: -1,
        predictor: predictor,
        changes: changes,
        bitCost: _rowDeltaOpBits + predictorBits + _bitVarUintBitLength(0),
      );
    }

    final rawCost = _rowDeltaOpBits + rowLength * localBits;
    final indexedCost =
        _rowDeltaOpBits +
        predictorBits +
        _bitVarUintBitLength(changes.length) +
        changes.length * (_bitsForChoiceCount(rowLength) + localBits);
    final extendedOp = _bestRowDeltaExtendedOp(changes, rowLength, localBits);
    final extendedCost =
        _rowDeltaOpBits +
        predictorBits +
        _rowDeltaExtendedBits +
        _rowDeltaExtendedRowBitCostForOp(
          changes,
          rowLength,
          localBits,
          extendedOp,
        );

    if (indexedCost < rawCost && indexedCost <= extendedCost) {
      return _RowDeltaDecision(
        op: _rowDeltaOpDelta,
        extendedOp: -1,
        predictor: predictor,
        changes: changes,
        bitCost: indexedCost,
      );
    }
    if (extendedCost < rawCost) {
      return _RowDeltaDecision(
        op: _rowDeltaOpExtended,
        extendedOp: extendedOp,
        predictor: predictor,
        changes: changes,
        bitCost: extendedCost,
      );
    }
    return _RowDeltaDecision(
      op: _rowDeltaOpRaw,
      extendedOp: -1,
      predictor: _rowDeltaPredictorSame,
      changes: changes,
      bitCost: rawCost,
    );
  }

  int _rowDeltaExtendedRowBitCostForOp(
    List<_RowDeltaChange> changes,
    int rowLength,
    int localBits,
    int extendedOp,
  ) {
    return switch (extendedOp) {
      _rowDeltaExtendedMask => rowLength + changes.length * localBits,
      _rowDeltaExtendedSegment =>
        _bitVarUintBitLength(_rowDeltaSegments(changes).length) +
            _rowDeltaSegments(changes).length *
                (_bitsForChoiceCount(rowLength) +
                    _bitsForChoiceCount(rowLength)) +
            changes.length * localBits,
      _rowDeltaExtendedSameColorMask =>
        rowLength +
            (_sameRowDeltaChangeValue(changes) == null ? 1 << 30 : localBits),
      _ => throw const MCOImageInvalidInputException(
        'Invalid row-delta extended op',
      ),
    };
  }

  int _bestRowDeltaExtendedOp(
    List<_RowDeltaChange> changes,
    int rowLength,
    int localBits,
  ) {
    final maskBits = _rowDeltaExtendedRowBitCostForOp(
      changes,
      rowLength,
      localBits,
      _rowDeltaExtendedMask,
    );
    final segmentBits = _rowDeltaExtendedRowBitCostForOp(
      changes,
      rowLength,
      localBits,
      _rowDeltaExtendedSegment,
    );
    final sameColorMaskBits = _rowDeltaExtendedRowBitCostForOp(
      changes,
      rowLength,
      localBits,
      _rowDeltaExtendedSameColorMask,
    );

    if (sameColorMaskBits <= segmentBits && sameColorMaskBits <= maskBits) {
      return _rowDeltaExtendedSameColorMask;
    }
    return segmentBits < maskBits
        ? _rowDeltaExtendedSegment
        : _rowDeltaExtendedMask;
  }

  int? _sameRowDeltaChangeValue(List<_RowDeltaChange> changes) {
    if (changes.isEmpty) return null;
    final value = changes.first.value;
    for (var i = 1; i < changes.length; i++) {
      if (changes[i].value != value) return null;
    }
    return value;
  }

  List<int> _readRowDeltaBody(
    _BitReader reader,
    int count,
    int rowLength,
    int localBits,
  ) {
    if (rowLength <= 0 || count % rowLength != 0) {
      throw const MCOImageInvalidPayloadException('Invalid row-delta geometry');
    }
    if (count == 0) return const <int>[];

    final useVirtualBaseRow = reader.readBits(1) != 0;
    final allowShiftPredictors = reader.readBits(1) != 0;
    final positionBits = _bitsForChoiceCount(rowLength);
    final result = List<int>.filled(count, 0);
    final rowCount = count ~/ rowLength;
    final firstDeltaRow = useVirtualBaseRow ? 0 : 1;

    if (!useVirtualBaseRow) {
      for (var x = 0; x < rowLength; x++) {
        result[x] = reader.readBits(localBits);
      }
    }

    for (var row = firstDeltaRow; row < rowCount; row++) {
      final rowStart = row * rowLength;
      final previousStart = rowStart - rowLength;
      final op = reader.readBits(_rowDeltaOpBits);

      switch (op) {
        case _rowDeltaOpRaw:
          for (var x = 0; x < rowLength; x++) {
            result[rowStart + x] = reader.readBits(localBits);
          }
          break;
        case _rowDeltaOpRepeat:
          _copyRowDeltaPredictedRow(
            result,
            rowStart,
            previousStart,
            row,
            rowLength,
            useVirtualBaseRow: useVirtualBaseRow,
            predictor: _rowDeltaPredictorSame,
          );
          break;
        case _rowDeltaOpDelta:
          final predictor = _readRowDeltaPredictor(
            reader,
            row,
            useVirtualBaseRow,
            allowShiftPredictors,
          );
          _copyRowDeltaPredictedRow(
            result,
            rowStart,
            previousStart,
            row,
            rowLength,
            useVirtualBaseRow: useVirtualBaseRow,
            predictor: predictor,
          );

          final changeCount = reader.readBitVarUint();
          var previousX = -1;
          for (var i = 0; i < changeCount; i++) {
            final x = reader.readBits(positionBits);
            if (x >= rowLength || x <= previousX) {
              throw const MCOImageInvalidPayloadException(
                'Invalid row-delta change position',
              );
            }
            result[rowStart + x] = reader.readBits(localBits);
            previousX = x;
          }
          break;
        case _rowDeltaOpExtended:
          final predictor = _readRowDeltaPredictor(
            reader,
            row,
            useVirtualBaseRow,
            allowShiftPredictors,
          );
          final extendedOp = reader.readBits(_rowDeltaExtendedBits);
          switch (extendedOp) {
            case _rowDeltaExtendedMask:
              _readRowDeltaMaskRow(
                reader,
                result,
                rowStart,
                previousStart,
                row,
                rowLength,
                localBits,
                useVirtualBaseRow: useVirtualBaseRow,
                predictor: predictor,
              );
              break;
            case _rowDeltaExtendedSegment:
              _readRowDeltaSegmentRow(
                reader,
                result,
                rowStart,
                previousStart,
                row,
                rowLength,
                localBits,
                useVirtualBaseRow: useVirtualBaseRow,
                predictor: predictor,
              );
              break;
            case _rowDeltaExtendedSameColorMask:
              _readRowDeltaSameColorMaskRow(
                reader,
                result,
                rowStart,
                previousStart,
                row,
                rowLength,
                localBits,
                useVirtualBaseRow: useVirtualBaseRow,
                predictor: predictor,
              );
              break;
            default:
              throw const MCOImageInvalidPayloadException(
                'Unknown row-delta extended op',
              );
          }
          break;
        default:
          throw const MCOImageInvalidPayloadException(
            'Unknown row-delta row op',
          );
      }
    }

    return result;
  }

  int _readRowDeltaPredictor(
    _BitReader reader,
    int row,
    bool useVirtualBaseRow,
    bool allowShiftPredictors,
  ) {
    if (!allowShiftPredictors) return _rowDeltaPredictorSame;

    final predictor = reader.readBits(_rowDeltaPredictorBits);
    if ((row == 0 &&
            useVirtualBaseRow &&
            predictor != _rowDeltaPredictorSame) ||
        (predictor != _rowDeltaPredictorSame &&
            predictor != _rowDeltaPredictorLeft &&
            predictor != _rowDeltaPredictorRight)) {
      throw const MCOImageInvalidPayloadException(
        'Invalid row-delta predictor',
      );
    }
    return predictor;
  }

  int _decodedRowDeltaPredictedValue(
    List<int> result,
    int rowLength,
    int row,
    int x,
    int previousStart, {
    required bool useVirtualBaseRow,
    required int predictor,
  }) {
    if (row == 0 && useVirtualBaseRow) return 0;

    final sourceX = switch (predictor) {
      _rowDeltaPredictorSame => x,
      _rowDeltaPredictorLeft => x + 1,
      _rowDeltaPredictorRight => x - 1,
      _ => throw const MCOImageInvalidPayloadException(
        'Invalid row-delta predictor',
      ),
    };

    if (sourceX < 0 || sourceX >= rowLength) return 0;
    return result[previousStart + sourceX];
  }

  void _copyRowDeltaPredictedRow(
    List<int> result,
    int rowStart,
    int previousStart,
    int row,
    int rowLength, {
    required bool useVirtualBaseRow,
    required int predictor,
  }) {
    for (var x = 0; x < rowLength; x++) {
      result[rowStart + x] = _decodedRowDeltaPredictedValue(
        result,
        rowLength,
        row,
        x,
        previousStart,
        useVirtualBaseRow: useVirtualBaseRow,
        predictor: predictor,
      );
    }
  }

  void _readRowDeltaMaskRow(
    _BitReader reader,
    List<int> result,
    int rowStart,
    int previousStart,
    int row,
    int rowLength,
    int localBits, {
    required bool useVirtualBaseRow,
    required int predictor,
  }) {
    _copyRowDeltaPredictedRow(
      result,
      rowStart,
      previousStart,
      row,
      rowLength,
      useVirtualBaseRow: useVirtualBaseRow,
      predictor: predictor,
    );

    final changed = List<bool>.filled(rowLength, false);
    var changeCount = 0;
    for (var x = 0; x < rowLength; x++) {
      final isChanged = reader.readBits(1) != 0;
      changed[x] = isChanged;
      if (isChanged) changeCount++;
    }
    if (changeCount == 0) {
      throw const MCOImageInvalidPayloadException(
        'Invalid empty row-delta mask',
      );
    }
    for (var x = 0; x < rowLength; x++) {
      if (changed[x]) {
        result[rowStart + x] = reader.readBits(localBits);
      }
    }
  }

  void _readRowDeltaSameColorMaskRow(
    _BitReader reader,
    List<int> result,
    int rowStart,
    int previousStart,
    int row,
    int rowLength,
    int localBits, {
    required bool useVirtualBaseRow,
    required int predictor,
  }) {
    _copyRowDeltaPredictedRow(
      result,
      rowStart,
      previousStart,
      row,
      rowLength,
      useVirtualBaseRow: useVirtualBaseRow,
      predictor: predictor,
    );

    final changed = List<bool>.filled(rowLength, false);
    var changeCount = 0;
    for (var x = 0; x < rowLength; x++) {
      final isChanged = reader.readBits(1) != 0;
      changed[x] = isChanged;
      if (isChanged) changeCount++;
    }
    if (changeCount == 0) {
      throw const MCOImageInvalidPayloadException(
        'Invalid empty row-delta same-color mask',
      );
    }

    final value = reader.readBits(localBits);
    for (var x = 0; x < rowLength; x++) {
      if (changed[x]) {
        result[rowStart + x] = value;
      }
    }
  }

  void _readRowDeltaSegmentRow(
    _BitReader reader,
    List<int> result,
    int rowStart,
    int previousStart,
    int row,
    int rowLength,
    int localBits, {
    required bool useVirtualBaseRow,
    required int predictor,
  }) {
    _copyRowDeltaPredictedRow(
      result,
      rowStart,
      previousStart,
      row,
      rowLength,
      useVirtualBaseRow: useVirtualBaseRow,
      predictor: predictor,
    );

    final positionBits = _bitsForChoiceCount(rowLength);
    final lengthBits = _bitsForChoiceCount(rowLength);
    final segmentCount = reader.readBitVarUint();
    if (segmentCount <= 0) {
      throw const MCOImageInvalidPayloadException(
        'Invalid empty row-delta segment list',
      );
    }

    var previousEnd = -1;
    for (var i = 0; i < segmentCount; i++) {
      final x = reader.readBits(positionBits);
      final length = reader.readBits(lengthBits) + 1;
      if (x <= previousEnd || x + length > rowLength) {
        throw const MCOImageInvalidPayloadException(
          'Invalid row-delta segment',
        );
      }
      for (var dx = 0; dx < length; dx++) {
        result[rowStart + x + dx] = reader.readBits(localBits);
      }
      previousEnd = x + length - 1;
    }
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

  void _writeCompactUint(_BitWriter writer, int value) {
    if (value < 0) {
      throw const MCOImageInvalidInputException('Negative compact uint');
    }
    if (value <= 3) {
      writer
        ..writeBits(0, 1)
        ..writeBits(value, 2);
    } else if (value <= 19) {
      writer
        ..writeBits(1, 2)
        ..writeBits(value - 4, 4);
    } else if (value <= 275) {
      writer
        ..writeBits(3, 3)
        ..writeBits(value - 20, 8);
    } else {
      writer
        ..writeBits(7, 3)
        ..writeBitVarUint(value);
    }
  }

  int _readCompactUint(_BitReader reader) {
    if (reader.readBits(1) == 0) return reader.readBits(2);
    if (reader.readBits(1) == 0) return reader.readBits(4) + 4;
    if (reader.readBits(1) == 0) return reader.readBits(8) + 20;
    return reader.readBitVarUint();
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

  String _lzOptimizationCacheKey(List<int> pixels, int localBits) {
    return '$localBits:${String.fromCharCodes(
      pixels.map((pixel) => pixel + 1),
    )}';
  }

  int _lzPixelTokensBitCost(List<_LzPixelToken> tokens, int localBits) {
    var cost = 0;
    for (final token in tokens) {
      if (token.isMatch) {
        cost +=
            1 +
            _compactUintBitLength(token.distance - 1) +
            _compactUintBitLength(token.length - _minLzMatchLength);
      } else {
        cost +=
            1 +
            _compactUintBitLength(token.literals.length - 1) +
            token.literals.length * localBits;
      }
    }
    return cost;
  }

  static bool _lzPixelTokensEqual(
    List<_LzPixelToken> left,
    List<_LzPixelToken> right,
  ) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      final a = left[i];
      final b = right[i];
      if (a.distance != b.distance ||
          a.length != b.length ||
          !_intListsEqual(a.literals, b.literals)) {
        return false;
      }
    }
    return true;
  }

  List<_LzPixelToken>? _buildOptimalLzPixelTokens(
    List<int> pixels,
    int localBits,
  ) {
    if (pixels.isEmpty) return const <_LzPixelToken>[];
    final matches = _buildLzMatchOptions(pixels);
    final pixelCount = pixels.length;
    const infinity = 1 << 60;
    final steps = List<_LzParseStep?>.filled(pixelCount, null);
    final rawMin = _LzRangeMinimumTree(pixelCount + 1);
    final literalMin = _LzRangeMinimumTree(pixelCount + 1);
    rawMin.update(pixelCount, 0);
    literalMin.update(pixelCount, pixelCount * localBits);

    for (var position = pixelCount - 1; position >= 0; position--) {
      var bestCost = infinity;
      _LzParseStep? bestStep;
      final remaining = pixelCount - position;

      for (final range in _lzLengthCostRanges(1, remaining)) {
        final result = literalMin.query(
          position + range.minLength,
          position + range.maxLength + 1,
        );
        if (result == null) continue;
        final cost =
            1 + range.bitCost + result.cost - position * localBits;
        if (cost < bestCost ||
            (cost == bestCost && result.index > (bestStep?.end ?? -1))) {
          bestCost = cost;
          bestStep = _LzParseStep.literal(result.index);
        }
      }

      for (final match in matches[position]) {
        for (
          final range in _lzLengthCostRanges(
            _minLzMatchLength,
            match.maxLength,
          )
        ) {
          final result = rawMin.query(
            position + range.minLength,
            position + range.maxLength + 1,
          );
          if (result == null) continue;
          final cost = 1 + match.distanceBitCost + range.bitCost + result.cost;
          if (cost < bestCost ||
              (cost == bestCost && result.index > (bestStep?.end ?? -1))) {
            bestCost = cost;
            bestStep = _LzParseStep.match(result.index, match.distance);
          }
        }
      }

      if (bestStep == null) return null;
      steps[position] = bestStep;
      rawMin.update(position, bestCost);
      literalMin.update(position, bestCost + position * localBits);
    }

    final tokens = <_LzPixelToken>[];
    var position = 0;
    while (position < pixelCount) {
      final step = steps[position];
      if (step == null || step.end <= position || step.end > pixelCount) {
        return null;
      }
      final length = step.end - position;
      if (step.distance == 0) {
        tokens.add(
          _LzPixelToken.literal(pixels.sublist(position, step.end)),
        );
      } else {
        tokens.add(_LzPixelToken.match(step.distance, length));
      }
      position = step.end;
    }
    return tokens;
  }

  List<List<_LzMatchOption>> _buildLzMatchOptions(List<int> pixels) {
    final result = List.generate(
      pixels.length,
      (_) => <_LzMatchOption>[],
      growable: false,
    );
    final positionsByKey = <int, List<int>>{};
    for (var position = 0; position < pixels.length; position++) {
      if (position + _minLzMatchLength <= pixels.length) {
        final candidates = positionsByKey[_lzPixelKey(pixels, position)];
        if (candidates != null) {
          final bestByDistanceCost = <int, _LzMatchOption>{};
          final maxPossibleLength = pixels.length - position;
          for (var i = candidates.length - 1; i >= 0; i--) {
            final previous = candidates[i];
            final distance = position - previous;
            final distanceBitCost = _compactUintBitLength(distance - 1);
            final existing = bestByDistanceCost[distanceBitCost];
            if (existing?.maxLength == maxPossibleLength) continue;
            final maxLength = _lzMatchLength(pixels, position, distance);
            if (maxLength < _minLzMatchLength) continue;
            if (existing == null || maxLength > existing.maxLength) {
              bestByDistanceCost[distanceBitCost] = _LzMatchOption(
                distance,
                maxLength,
                distanceBitCost,
              );
            }
          }
          result[position].addAll(bestByDistanceCost.values);
        }
      }
      _addLzPixelPosition(positionsByKey, pixels, position);
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

  Iterable<_LzLengthCostRange> _lzLengthCostRanges(
    int valueOffset,
    int maxLength,
  ) sync* {
    if (maxLength < valueOffset) return;
    for (final valueRange in const [
      (min: 0, max: 3),
      (min: 4, max: 19),
      (min: 20, max: 275),
      (min: 276, max: 16383),
      (min: 16384, max: 2097151),
    ]) {
      final minLength = valueRange.min + valueOffset;
      if (minLength > maxLength) break;
      final rangeMaxLength = math.min(
        valueRange.max + valueOffset,
        maxLength,
      );
      yield _LzLengthCostRange(
        minLength,
        rangeMaxLength,
        _compactUintBitLength(valueRange.min),
      );
    }
  }

  List<_LzPixelToken> _buildGreedyLzPixelTokens(
    List<int> pixels,
    int localBits,
  ) {
    final tokens = <_LzPixelToken>[];
    final pendingLiterals = <int>[];
    final positionsByKey = <int, List<int>>{};

    void flushLiterals() {
      if (pendingLiterals.isEmpty) return;
      tokens.add(_LzPixelToken.literal(List<int>.of(pendingLiterals)));
      pendingLiterals.clear();
    }

    var position = 0;
    while (position < pixels.length) {
      var bestLength = 0;
      var bestDistance = 0;
      if (position + _minLzMatchLength <= pixels.length) {
        final key = _lzPixelKey(pixels, position);
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
                (length == bestLength && distance < bestDistance)) {
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
        tokens.add(_LzPixelToken.match(bestDistance, bestLength));
        for (var i = 0; i < bestLength; i++) {
          _addLzPixelPosition(positionsByKey, pixels, position + i);
        }
        position += bestLength;
      } else {
        pendingLiterals.add(pixels[position]);
        _addLzPixelPosition(positionsByKey, pixels, position);
        position++;
      }
    }
    flushLiterals();
    return tokens;
  }

  static int _lzPixelKey(List<int> pixels, int position) {
    return (pixels[position] << 12) |
        (pixels[position + 1] << 6) |
        pixels[position + 2];
  }

  static void _addLzPixelPosition(
    Map<int, List<int>> positionsByKey,
    List<int> pixels,
    int position,
  ) {
    if (position + _minLzMatchLength > pixels.length) return;
    final positions = positionsByKey.putIfAbsent(
      _lzPixelKey(pixels, position),
      () => <int>[],
    );
    positions.add(position);
    if (positions.length > _maxLzMatchCandidates) {
      positions.removeAt(0);
    }
  }

  static List<int> _buildBitplaneRuns(List<int> pixels, int bit) {
    final runs = <int>[];
    var current = (pixels.first >> bit) & 1;
    var length = 0;
    for (final pixel in pixels) {
      final value = (pixel >> bit) & 1;
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

  void _writeAdaptiveBitplanesBody(
    _BitWriter writer,
    List<int> pixels,
    int bitCount,
  ) {
    for (var bit = 0; bit < bitCount; bit++) {
      final decision = _chooseAdaptiveBitplaneEncoding(pixels, bit);
      switch (decision.mode) {
        case _AdaptiveBitplaneMode.raw:
          writer.writeBits(0, 1);
          for (final pixel in pixels) {
            writer.writeBits((pixel >> bit) & 1, 1);
          }
          break;
        case _AdaptiveBitplaneMode.legacyRle:
          writer
            ..writeBits(1, 2)
            ..writeBits(decision.startingBit, 1);
          for (final length in decision.runs) {
            _writeCompactUint(writer, length - 1);
          }
          break;
        case _AdaptiveBitplaneMode.shortRle:
          writer
            ..writeBits(3, 3)
            ..writeBits(decision.startingBit, 1);
          for (final length in decision.runs) {
            _writeShortBitplaneRunLength(writer, length);
          }
          break;
        case _AdaptiveBitplaneMode.constantZero:
          writer.writeBits(7, 5);
          break;
        case _AdaptiveBitplaneMode.constantOne:
          writer.writeBits(15, 5);
          break;
        case _AdaptiveBitplaneMode.sparseOne:
          writer.writeBits(23, 5);
          _writeSparseBitplanePositions(writer, decision.minorityPositions);
          break;
        case _AdaptiveBitplaneMode.sparseZero:
          writer.writeBits(31, 5);
          _writeSparseBitplanePositions(writer, decision.minorityPositions);
          break;
      }
    }
  }

  _AdaptiveBitplaneDecision _chooseAdaptiveBitplaneEncoding(
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

    final decisions = <_AdaptiveBitplaneDecision>[
      _AdaptiveBitplaneDecision(
        _AdaptiveBitplaneMode.raw,
        1 + pixels.length,
        startingBit: startingBit,
        runs: runs,
      ),
      _AdaptiveBitplaneDecision(
        _AdaptiveBitplaneMode.legacyRle,
        3 +
            runs.fold<int>(
              0,
              (sum, length) =>
                  sum + _compactUintBitLength(length - 1),
            ),
        startingBit: startingBit,
        runs: runs,
      ),
      _AdaptiveBitplaneDecision(
        _AdaptiveBitplaneMode.shortRle,
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
        _AdaptiveBitplaneDecision(
          onePositions.isEmpty
              ? _AdaptiveBitplaneMode.constantZero
              : _AdaptiveBitplaneMode.constantOne,
          5,
          startingBit: startingBit,
          runs: runs,
        ),
      );
    } else {
      decisions
        ..add(
          _AdaptiveBitplaneDecision(
            _AdaptiveBitplaneMode.sparseOne,
            5 + _sparseBitplanePositionCost(onePositions),
            startingBit: startingBit,
            runs: runs,
            minorityPositions: onePositions,
          ),
        )
        ..add(
          _AdaptiveBitplaneDecision(
            _AdaptiveBitplaneMode.sparseZero,
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

  List<int> _optimizeBitplanesPaletteOrder(
    List<int> pixels,
    List<int> palette,
  ) {
    if (palette.length < 2) return palette;

    var bestPalette = List<int>.of(palette);
    var bestCost = _adaptiveBitplanesCost(pixels, bestPalette);
    final exhaustiveSwaps = palette.length <= 8;
    final passCount = exhaustiveSwaps ? 2 : 1;
    for (var pass = 0; pass < passCount; pass++) {
      var improved = false;
      var passPalette = bestPalette;
      var passCost = bestCost;
      for (var left = 0; left < bestPalette.length - 1; left++) {
        final rightLimit = exhaustiveSwaps
            ? bestPalette.length
            : left + 2;
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

  List<int> _optimizeBitplanesPaletteOrderMultiStart(
    PaletteProfile profile,
    List<int> pixels,
    List<int> palette,
    int backgroundColor, {
    required bool allowLargeImage,
  }) {
    if (palette.length < 3 ||
        (!allowLargeImage && pixels.length > _maxMultiStartBitplanesPixels)) {
      return palette;
    }

    final seeds = <List<int>>[
      List<int>.of(palette),
      _orderPaletteByProfileId(profile, palette),
      _orderPaletteByRgb(profile, pixels, palette, backgroundColor),
      _optimizeTransitionPaletteOrder(pixels, palette, backgroundColor),
    ];
    final uniqueSeeds = <List<int>>[];
    final seenSeeds = <String>{};
    for (final seed in seeds) {
      if (seenSeeds.add(seed.join(','))) uniqueSeeds.add(seed);
    }

    final baselineOptimized = _optimizeBitplanesPaletteOrder(pixels, palette);
    var bestExistingCost = _adaptiveBitplanesCost(pixels, palette);
    for (final existing in [...uniqueSeeds, baselineOptimized]) {
      bestExistingCost = math.min(
        bestExistingCost,
        _adaptiveBitplanesCost(pixels, existing),
      );
    }

    List<int>? bestMultiStart;
    var bestMultiStartCost = bestExistingCost;
    for (final seed in uniqueSeeds.skip(1)) {
      final optimized = _optimizeBitplanesPaletteOrder(pixels, seed);
      final cost = _adaptiveBitplanesCost(pixels, optimized);
      if (cost < bestMultiStartCost) {
        bestMultiStart = optimized;
        bestMultiStartCost = cost;
      }
    }

    return bestMultiStart ?? palette;
  }

  List<int> _orderPaletteByProfileId(
    PaletteProfile profile,
    List<int> palette,
  ) {
    return List<int>.of(palette)..sort((left, right) {
      if (profile.isFixed) return left.compareTo(right);
      return _profileColorIdForGlobalIndex(profile, left)!.compareTo(
        _profileColorIdForGlobalIndex(profile, right)!,
      );
    });
  }

  List<int> _optimizeTransitionPaletteOrder(
    List<int> pixels,
    List<int> palette,
    int backgroundColor,
  ) {
    if (palette.length < 3) return palette;
    final counts = <int, int>{};
    final transitions = <int, Map<int, int>>{};
    for (final color in pixels) {
      counts[color] = (counts[color] ?? 0) + 1;
    }
    for (var i = 1; i < pixels.length; i++) {
      final left = pixels[i - 1];
      final right = pixels[i];
      if (left == right) continue;
      final leftEdges = transitions.putIfAbsent(left, () => <int, int>{});
      final rightEdges = transitions.putIfAbsent(right, () => <int, int>{});
      leftEdges[right] = (leftEdges[right] ?? 0) + 1;
      rightEdges[left] = (rightEdges[left] ?? 0) + 1;
    }

    final remaining = palette.toSet();
    var current = remaining.contains(backgroundColor)
        ? backgroundColor
        : palette.reduce(
            (left, right) =>
                (counts[left] ?? 0) >= (counts[right] ?? 0) ? left : right,
          );
    final result = <int>[];
    while (remaining.isNotEmpty) {
      result.add(current);
      remaining.remove(current);
      if (remaining.isEmpty) break;
      current = remaining.reduce((left, right) {
        final leftWeight = transitions[current]?[left] ?? 0;
        final rightWeight = transitions[current]?[right] ?? 0;
        if (leftWeight != rightWeight) {
          return leftWeight > rightWeight ? left : right;
        }
        final leftCount = counts[left] ?? 0;
        final rightCount = counts[right] ?? 0;
        if (leftCount != rightCount) {
          return leftCount > rightCount ? left : right;
        }
        return left < right ? left : right;
      });
    }
    return result;
  }

  List<int> _orderPaletteByRgb(
    PaletteProfile profile,
    List<int> pixels,
    List<int> palette,
    int backgroundColor,
  ) {
    if (palette.length < 3) return palette;
    final counts = <int, int>{};
    for (final color in pixels) {
      counts[color] = (counts[color] ?? 0) + 1;
    }
    final remaining = palette.toSet();
    var current = remaining.contains(backgroundColor)
        ? backgroundColor
        : palette.reduce(
            (left, right) =>
                (counts[left] ?? 0) >= (counts[right] ?? 0) ? left : right,
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
        if (leftCount != rightCount) {
          return leftCount > rightCount ? left : right;
        }
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

  int _adaptiveBitplanesCost(List<int> pixels, List<int> palette) {
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

  static bool _intListsEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
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

  void _writeSparseBitplanePositions(
    _BitWriter writer,
    List<int> positions,
  ) {
    _writeCompactUint(writer, positions.length - 1);
    var previous = -1;
    for (final position in positions) {
      _writeCompactUint(writer, position - previous - 1);
      previous = position;
    }
  }

  void _writeShortBitplaneRunLength(_BitWriter writer, int length) {
    if (length <= 0) {
      throw const MCOImageInvalidInputException('Invalid bitplane run');
    }
    if (length <= 3) {
      writer.writeBits((1 << (length - 1)) - 1, length);
      return;
    }
    writer.writeBits(7, 3);
    _writeCompactUint(writer, length - 4);
  }

  int _readShortBitplaneRunLength(_BitReader reader) {
    if (reader.readBits(1) == 0) return 1;
    if (reader.readBits(1) == 0) return 2;
    if (reader.readBits(1) == 0) return 3;
    return _readCompactUint(reader) + 4;
  }

  static int _shortBitplaneRunBitLength(int length) {
    if (length <= 0) {
      throw const MCOImageInvalidInputException('Invalid bitplane run');
    }
    if (length <= 3) return length;
    return 3 + _compactUintBitLength(length - 4);
  }

  void _writeQuadtreeNode(
    _BitWriter writer,
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
    for (final child in <_ImageBounds>[
      _ImageBounds(x: x, y: y, width: leftWidth, height: topHeight),
      _ImageBounds(
        x: x + leftWidth,
        y: y,
        width: width - leftWidth,
        height: topHeight,
      ),
      _ImageBounds(
        x: x,
        y: y + topHeight,
        width: leftWidth,
        height: height - topHeight,
      ),
      _ImageBounds(
        x: x + leftWidth,
        y: y + topHeight,
        width: width - leftWidth,
        height: height - topHeight,
      ),
    ]) {
      _writeQuadtreeNode(
        writer,
        pixels,
        stride,
        child.x,
        child.y,
        child.width,
        child.height,
        localBits,
      );
    }
  }

  static int _rowLengthForScan(ScanMode scan, int width, int height) {
    return switch (scan) {
      ScanMode.h || ScanMode.s => width,
      ScanMode.v || ScanMode.sv => height,
    };
  }

  static List<_SparseSegment> _buildSparseSegments(
    List<int> pixels,
    int background,
  ) {
    final segments = <_SparseSegment>[];
    var i = 0;
    while (i < pixels.length) {
      if (pixels[i] == background) {
        i++;
        continue;
      }
      final start = i;
      final color = pixels[i];
      var length = 0;
      while (i < pixels.length && pixels[i] == color) {
        length++;
        i++;
      }
      segments.add(_SparseSegment(start, color, length));
    }
    return segments;
  }

  static List<_SparseSegment> _buildDynamicSparseSegments(
    List<int> pixels,
    PaletteProfile profile,
    int background,
    Map<int, int> localIndexByProfileColorId,
  ) {
    final segments = <_SparseSegment>[];
    var i = 0;
    while (i < pixels.length) {
      if (pixels[i] == background) {
        i++;
        continue;
      }
      final start = i;
      final profileColorId = _profileColorIdForGlobalIndex(profile, pixels[i]);
      if (profileColorId == null) {
        throw MCOImageInvalidInputException(
          'Pixel globalIndex ${pixels[i]} is not available in ${profile.name}',
        );
      }
      final localIndex = localIndexByProfileColorId[profileColorId]!;
      var length = 0;
      while (i < pixels.length && pixels[i] != background) {
        final nextProfileColorId = _profileColorIdForGlobalIndex(
          profile,
          pixels[i],
        );
        if (nextProfileColorId == null ||
            localIndexByProfileColorId[nextProfileColorId] != localIndex) {
          break;
        }
        length++;
        i++;
      }
      segments.add(_SparseSegment(start, localIndex, length));
    }
    return segments;
  }

  static int _localBits(int colorCount) {
    if (colorCount <= 1) return 1;
    return (colorCount - 1).bitLength;
  }

  static bool _isGrayscaleProfile(PaletteProfile profile) {
    return profile == PaletteProfile.grayscale8 ||
        profile == PaletteProfile.grayscale16 ||
        profile == PaletteProfile.grayscale32;
  }

  static int _bitsForChoiceCount(int count) {
    if (count <= 1) return 0;
    return (count - 1).bitLength;
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
      PaletteProfile.dynamicGlobal512 => _global512Bits,
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

  static const int _global512Bits = 9;

  static int _dynamicProfileColorBits(PaletteProfile profile) =>
      _globalBits(profile);

  static int _dynamicProfileSize(PaletteProfile profile) =>
      _paletteSize(profile);

  static int _dynamicProfileId(PaletteProfile profile) {
    return switch (profile) {
      PaletteProfile.dynamicGlobal8 => 0,
      PaletteProfile.dynamicGlobal16 => 1,
      PaletteProfile.dynamicGlobal32 => 2,
      PaletteProfile.dynamicGlobal64 => 3,
      PaletteProfile.dynamicGlobal128 => 4,
      PaletteProfile.dynamicGlobal256 => 5,
      PaletteProfile.dynamicGlobal512 => 6,
      _ => throw const MCOImageInvalidInputException(
        'Not a dynamic palette profile',
      ),
    };
  }

  static PaletteProfile _dynamicProfileFromId(int value) {
    return switch (value) {
      0 => PaletteProfile.dynamicGlobal8,
      1 => PaletteProfile.dynamicGlobal16,
      2 => PaletteProfile.dynamicGlobal32,
      3 => PaletteProfile.dynamicGlobal64,
      4 => PaletteProfile.dynamicGlobal128,
      5 => PaletteProfile.dynamicGlobal256,
      6 => PaletteProfile.dynamicGlobal512,
      _ => throw MCOImageInvalidPayloadException(
        'Unknown dynamic palette profile $value',
      ),
    };
  }

  static int _fixedProfileId(PaletteProfile profile) {
    return switch (profile) {
      PaletteProfile.mono => 0,
      PaletteProfile.master4 => 1,
      PaletteProfile.master8 => 2,
      PaletteProfile.grayscale8 => 3,
      PaletteProfile.master16 => 4,
      PaletteProfile.grayscale16 => 5,
      PaletteProfile.master32 => 6,
      PaletteProfile.grayscale32 => 7,
      PaletteProfile.master64 => 8,
      _ => throw const MCOImageInvalidInputException(
        'Not a fixed palette profile',
      ),
    };
  }

  static PaletteProfile _fixedProfileFromId(int value) {
    return switch (value) {
      0 => PaletteProfile.mono,
      1 => PaletteProfile.master4,
      2 => PaletteProfile.master8,
      3 => PaletteProfile.grayscale8,
      4 => PaletteProfile.master16,
      5 => PaletteProfile.grayscale16,
      6 => PaletteProfile.master32,
      7 => PaletteProfile.grayscale32,
      8 => PaletteProfile.master64,
      _ => throw MCOImageInvalidPayloadException(
        'Unknown fixed palette profile $value',
      ),
    };
  }

  static List<DynamicPaletteReferenceEncoding> _dynamicReferenceEncodings(
    PaletteProfile profile,
  ) {
    if (profile == PaletteProfile.dynamicGlobal512) {
      return const [
        DynamicPaletteReferenceEncoding.flat,
        DynamicPaletteReferenceEncoding.banked8x64,
        DynamicPaletteReferenceEncoding.sortedDelta,
        DynamicPaletteReferenceEncoding.rangeRuns,
        DynamicPaletteReferenceEncoding.profileBitmap,
        DynamicPaletteReferenceEncoding.bankBitmaps,
      ];
    }
    return const [
      DynamicPaletteReferenceEncoding.flat,
      DynamicPaletteReferenceEncoding.sortedDelta,
      DynamicPaletteReferenceEncoding.rangeRuns,
      DynamicPaletteReferenceEncoding.profileBitmap,
    ];
  }

  static bool _usesExtendedDynamicPaletteDescriptor(
    DynamicPaletteReferenceEncoding encoding,
  ) =>
      encoding == DynamicPaletteReferenceEncoding.sortedDelta ||
      encoding == DynamicPaletteReferenceEncoding.rangeRuns ||
      encoding == DynamicPaletteReferenceEncoding.profileBitmap ||
      encoding == DynamicPaletteReferenceEncoding.bankBitmaps;

  static bool _supportsAlternativeAdaptivePaletteOrders(
    PaletteProfile profile,
    DynamicPaletteReferenceEncoding? referenceEncoding,
  ) {
    if (profile.isFixed) {
      return referenceEncoding == null &&
          switch (profile) {
            PaletteProfile.master4 ||
            PaletteProfile.master8 ||
            PaletteProfile.master16 ||
            PaletteProfile.master32 ||
            PaletteProfile.master64 => true,
            _ => false,
          };
    }
    return referenceEncoding != null &&
        !_usesExtendedDynamicPaletteDescriptor(referenceEncoding);
  }

  static bool _supportsTransitionOptimizedRowDelta(
    PaletteProfile profile,
    DynamicPaletteReferenceEncoding? referenceEncoding,
  ) {
    if (profile.isDynamic) {
      return referenceEncoding == DynamicPaletteReferenceEncoding.flat;
    }
    return _supportsAlternativeAdaptivePaletteOrders(
      profile,
      referenceEncoding,
    );
  }

  static bool _usesSortedDynamicPalette(
    DynamicPaletteReferenceEncoding encoding,
  ) => _usesExtendedDynamicPaletteDescriptor(encoding);

  static DynamicPaletteReferenceEncoding _dynamicReferenceEncodingFromBits(
    int value,
  ) {
    return switch (value) {
      0 => DynamicPaletteReferenceEncoding.flat,
      1 => DynamicPaletteReferenceEncoding.banked8x64,
      _ => throw MCOImageInvalidPayloadException(
        'Unknown dynamic palette reference encoding $value',
      ),
    };
  }

  static int? _profileColorIdForGlobalIndex(
    PaletteProfile profile,
    int globalIndex,
  ) {
    return MCOImageDynamicPalette.profileColorIdForGlobalIndex(
      profile,
      globalIndex,
    );
  }

  static int _globalIndexForProfileColorId(
    PaletteProfile profile,
    int profileColorId,
  ) {
    return MCOImageDynamicPalette.globalIndexForProfileColorId(
      profile,
      profileColorId,
    );
  }

  static int _modeBits(ImageMode mode) {
    return switch (mode) {
      ImageMode.rawGlobal => 0,
      ImageMode.rawLocal => 1,
      ImageMode.rleLocal => 2,
      ImageMode.sparseBg => 3,
      ImageMode.biColorMask => 4,
      ImageMode.rowDelta => 5,
      ImageMode.rowRepeat => 6,
      ImageMode.extended => 7,
      ImageMode.regionsBg => throw const MCOImageInvalidInputException(
        'REGIONS_BG has no block mode bits',
      ),
    };
  }

  static int _scanBits(ScanMode scan) => scan.index;
  static int _profileBits(PaletteProfile profile) => profile.index;

  static ImageMode _modeFromBits(int value) {
    return switch (value) {
      0 => ImageMode.rawGlobal,
      1 => ImageMode.rawLocal,
      2 => ImageMode.rleLocal,
      3 => ImageMode.sparseBg,
      4 => ImageMode.biColorMask,
      5 => ImageMode.rowDelta,
      6 => ImageMode.rowRepeat,
      7 => ImageMode.extended,
      _ => throw MCOImageInvalidPayloadException('Unknown image mode $value'),
    };
  }

  static ScanMode _scanFromBits(int value) {
    if (value < 0 || value >= ScanMode.values.length) {
      throw MCOImageInvalidPayloadException('Unknown scan mode $value');
    }
    return ScanMode.values[value];
  }

  static PaletteProfile _profileFromBits(int value) {
    if (value < 0 || value >= PaletteProfile.values.length || value > 0x0f) {
      throw MCOImageInvalidPayloadException('Unknown palette profile $value');
    }
    final profile = PaletteProfile.values[value];
    if (profile.isDynamic) {
      throw MCOImageInvalidPayloadException(
        'Dynamic palette profile $value requires codec version 2',
      );
    }
    return profile;
  }

  static void _validateImage(MCOImage image) {
    _validateDimensions(image.width, image.height);
    final expected = image.width * image.height;
    if (image.pixels.length != expected) {
      throw MCOImageInvalidInputException(
        'pixels.length must be $expected, got ${image.pixels.length}',
      );
    }
    for (final pixel in image.pixels) {
      _validateColor(pixel, image.paletteProfile, 'pixel');
    }
    if (image.transparentColor != null) {
      _validateColor(
        image.transparentColor!,
        image.paletteProfile,
        'transparentColor',
      );
    }
  }

  static void _validateDimensions(
    int width,
    int height, {
    bool payload = false,
  }) {
    if (width < _minSize ||
        height < _minSize ||
        width > _maxSize ||
        height > _maxSize) {
      final message = 'Image size must be $_minSize..$_maxSize in both axes';
      if (payload) throw MCOImageInvalidPayloadException(message);
      throw MCOImageInvalidInputException(message);
    }
  }

  static void _validateColor(
    int color,
    PaletteProfile profile,
    String label, {
    bool payload = false,
  }) {
    if (profile.isDynamic) {
      if (_profileColorIdForGlobalIndex(profile, color) != null) return;
      final message = '$label color must be in $profile, got $color';
      if (payload) throw MCOImageInvalidPayloadException(message);
      throw MCOImageInvalidInputException(message);
    }
    final max = _paletteSize(profile) - 1;
    if (color < 0 || color > max) {
      final message = '$label color must be 0..$max, got $color';
      if (payload) throw MCOImageInvalidPayloadException(message);
      throw MCOImageInvalidInputException(message);
    }
  }
}

class _BitWriter {
  final List<int> _bytes = [];
  var _bitOffset = 0;

  void writeAlignedByte(int value) {
    alignToByte();
    _bytes.add(value & 0xff);
  }

  void writeAlignedBytes(Uint8List values) {
    alignToByte();
    _bytes.addAll(values);
  }

  void writeBits(int value, int bitCount) {
    if (bitCount < 0) {
      throw const MCOImageInvalidInputException('Negative bit count');
    }
    var remaining = bitCount;
    var source = value;
    while (remaining > 0) {
      if (_bitOffset == 0) _bytes.add(0);
      final available = 8 - _bitOffset;
      final take = math.min(remaining, available);
      final mask = (1 << take) - 1;
      _bytes[_bytes.length - 1] |= (source & mask) << _bitOffset;
      source >>= take;
      _bitOffset = (_bitOffset + take) & 7;
      remaining -= take;
    }
  }

  void writeVarUint(int value) {
    if (value < 0) {
      throw const MCOImageInvalidInputException('Negative varuint');
    }
    alignToByte();
    var current = value;
    do {
      var byte = current & 0x7f;
      current >>= 7;
      if (current != 0) byte |= 0x80;
      _bytes.add(byte);
    } while (current != 0);
  }

  void writeBitVarUint(int value) {
    if (value < 0) {
      throw const MCOImageInvalidInputException('Negative varuint');
    }
    var current = value;
    do {
      var byte = current & 0x7f;
      current >>= 7;
      if (current != 0) byte |= 0x80;
      writeBits(byte, 8);
    } while (current != 0);
  }

  void alignToByte() {
    if (_bitOffset != 0) _bitOffset = 0;
  }

  Uint8List toBytes() {
    alignToByte();
    return Uint8List.fromList(_bytes);
  }
}

class _BitReader {
  final Uint8List _bytes;
  int byteIndex;
  var _bitOffset = 0;

  _BitReader(Uint8List bytes, {this.byteIndex = 0}) : _bytes = bytes;

  int readAlignedByte() {
    alignToByte();
    if (byteIndex >= _bytes.length) {
      throw const MCOImageInvalidPayloadException('Unexpected end of byte');
    }
    return _bytes[byteIndex++];
  }

  Uint8List readAlignedBytes(int length) {
    if (length < 0) {
      throw const MCOImageInvalidPayloadException('Negative byte length');
    }
    alignToByte();
    if (byteIndex + length > _bytes.length) {
      throw const MCOImageInvalidPayloadException('Unexpected end of bytes');
    }
    final result = Uint8List.sublistView(_bytes, byteIndex, byteIndex + length);
    byteIndex += length;
    return result;
  }

  int readBits(int bitCount) {
    if (bitCount < 0) {
      throw const MCOImageInvalidPayloadException('Negative bit count');
    }
    var result = 0;
    var shift = 0;
    var remaining = bitCount;
    while (remaining > 0) {
      if (byteIndex >= _bytes.length) {
        throw const MCOImageInvalidPayloadException('Unexpected end of bits');
      }
      final available = 8 - _bitOffset;
      final take = math.min(remaining, available);
      final mask = (1 << take) - 1;
      result |= ((_bytes[byteIndex] >> _bitOffset) & mask) << shift;
      _bitOffset += take;
      if (_bitOffset == 8) {
        _bitOffset = 0;
        byteIndex++;
      }
      shift += take;
      remaining -= take;
    }
    return result;
  }

  int readVarUint({int maxBytes = 5}) {
    alignToByte();
    var result = 0;
    var shift = 0;
    for (var i = 0; i < maxBytes; i++) {
      if (byteIndex >= _bytes.length) {
        throw const MCOImageInvalidPayloadException(
          'Unexpected end of varuint',
        );
      }
      final byte = _bytes[byteIndex++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return result;
      shift += 7;
    }
    throw const MCOImageInvalidPayloadException('Varuint is too long');
  }

  int readBitVarUint({int maxBytes = 5}) {
    var result = 0;
    var shift = 0;
    for (var i = 0; i < maxBytes; i++) {
      final byte = readBits(8);
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return result;
      shift += 7;
    }
    throw const MCOImageInvalidPayloadException('Varuint is too long');
  }

  void alignToByte() {
    if (_bitOffset != 0) {
      if (byteIndex >= _bytes.length) {
        throw const MCOImageInvalidPayloadException(
          'Unexpected end of padding',
        );
      }
      final unusedMask = 0xff << _bitOffset;
      if ((_bytes[byteIndex] & unusedMask) != 0) {
        throw const MCOImageInvalidPayloadException('Non-zero padding bits');
      }
      byteIndex++;
      _bitOffset = 0;
    }
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

class _Base91 {
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

class _LocalPalette {
  final List<int> colors;

  const _LocalPalette(this.colors);
}

class _PaletteRange {
  final int start;
  final int end;

  const _PaletteRange(this.start, this.end);

  int get length => end - start + 1;
}

class _Run {
  final int color;
  final int length;

  const _Run(this.color, this.length);
}

class _RowDeltaBodyCost {
  final int rawFirstCost;
  final int virtualBaseCost;

  const _RowDeltaBodyCost({
    required this.rawFirstCost,
    required this.virtualBaseCost,
  });

  int get bestCost => math.min(rawFirstCost, virtualBaseCost);
}

class _RowDeltaDecision {
  final int op;
  final int extendedOp;
  final int predictor;
  final List<_RowDeltaChange> changes;
  final int bitCost;

  const _RowDeltaDecision({
    required this.op,
    required this.extendedOp,
    required this.predictor,
    required this.changes,
    required this.bitCost,
  });
}

class _CompactRowDeltaDecision {
  final int op;
  final int predictor;
  final List<_RowDeltaChange> changes;
  final bool useResidual;
  final int bitCost;

  const _CompactRowDeltaDecision({
    required this.op,
    required this.predictor,
    required this.changes,
    required this.useResidual,
    required this.bitCost,
  });
}

class _CompactValueEncoding {
  final bool useResidual;
  final int bitCost;

  const _CompactValueEncoding(this.useResidual, this.bitCost);
}

class _RowDeltaChange {
  final int x;
  final int value;

  const _RowDeltaChange(this.x, this.value);
}

class _RowDeltaSegment {
  final int x;
  final List<int> values;

  const _RowDeltaSegment(this.x, this.values);

  int get length => values.length;
}

class _SparseSegment {
  final int start;
  final int color;
  final int length;

  const _SparseSegment(this.start, this.color, this.length);
}

class _LzPixelToken {
  final List<int> literals;
  final int distance;
  final int length;

  const _LzPixelToken.literal(this.literals) : distance = 0, length = 0;

  const _LzPixelToken.match(this.distance, this.length)
    : literals = const <int>[];

  bool get isMatch => distance > 0;
}

class _LzMatchOption {
  final int distance;
  final int maxLength;
  final int distanceBitCost;

  const _LzMatchOption(
    this.distance,
    this.maxLength,
    this.distanceBitCost,
  );
}

class _LzParseStep {
  final int end;
  final int distance;

  const _LzParseStep.literal(this.end) : distance = 0;

  const _LzParseStep.match(this.end, this.distance);
}

class _LzLengthCostRange {
  final int minLength;
  final int maxLength;
  final int bitCost;

  const _LzLengthCostRange(this.minLength, this.maxLength, this.bitCost);
}

class _LzRangeMinimum {
  final int cost;
  final int index;

  const _LzRangeMinimum(this.cost, this.index);
}

class _LzRangeMinimumTree {
  static const int _infinity = 1 << 60;

  final int _size;
  final List<int> _costs;
  final List<int> _indices;

  factory _LzRangeMinimumTree(int length) {
    var size = 1;
    while (size < length) {
      size <<= 1;
    }
    return _LzRangeMinimumTree._(
      size,
      List<int>.filled(size * 2, _infinity),
      List<int>.filled(size * 2, -1),
    );
  }

  _LzRangeMinimumTree._(this._size, this._costs, this._indices);

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

  _LzRangeMinimum? query(int start, int end) {
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
    return bestIndex < 0 ? null : _LzRangeMinimum(bestCost, bestIndex);
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
        (rightCost == leftCost && rightIndex > leftIndex)) {
      return (rightCost, rightIndex);
    }
    return (leftCost, leftIndex);
  }
}

class _SolidRect {
  final _ImageBounds bounds;
  final int color;

  const _SolidRect(this.bounds, this.color);
}

class _RegionPartition {
  final List<_ImageBounds> parts;
  final int savedArea;

  const _RegionPartition(this.parts, this.savedArea);
}

class _RegionBeamState {
  final List<_ImageBounds> regions;
  final int cost;

  const _RegionBeamState(this.regions, this.cost);
}

class _RegionBeamNeighbor {
  final List<_ImageBounds> regions;
  final int heuristic;

  const _RegionBeamNeighbor(this.regions, this.heuristic);
}

class _GreedyRectStrategy {
  final int horizontalDirection;
  final int verticalDirection;
  final int tieMode;

  const _GreedyRectStrategy(
    this.horizontalDirection,
    this.verticalDirection,
    this.tieMode,
  );
}

class _ImageBounds {
  final int x;
  final int y;
  final int width;
  final int height;

  const _ImageBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  int get area => width * height;
}

class _BackgroundCandidate {
  final int color;
  final int rank;

  const _BackgroundCandidate(this.color, this.rank);
}

class _BlockPayload {
  final Uint8List payload;
  final ImageMode mode;
  final ScanMode scan;

  const _BlockPayload(this.payload, this.mode, this.scan);
}

class _RegionPayload {
  final Uint8List payload;
  final int regionCount;

  const _RegionPayload(this.payload, this.regionCount);
}

class _V2Payload {
  final Uint8List payload;
  final int regionCount;
  final int? localPaletteSize;
  final int? usedBankCount;
  final int? bitsPerLocalPixel;
  final String? diagnosticContainer;

  const _V2Payload(
    this.payload, {
    this.regionCount = 0,
    this.localPaletteSize,
    this.usedBankCount,
    this.bitsPerLocalPixel,
    this.diagnosticContainer,
  });
}

class _V2BlockPayload {
  final Uint8List payload;
  final int? localPaletteSize;
  final int? usedBankCount;
  final int? bitsPerLocalPixel;

  const _V2BlockPayload(
    this.payload, {
    this.localPaletteSize,
    this.usedBankCount,
    this.bitsPerLocalPixel,
  });
}

class _DynamicLocalPalette {
  final List<int> globalColors;

  const _DynamicLocalPalette(this.globalColors);
}

enum _AdaptiveBitplaneMode {
  raw,
  legacyRle,
  shortRle,
  constantZero,
  constantOne,
  sparseOne,
  sparseZero,
}

class _AdaptiveBitplaneDecision {
  final _AdaptiveBitplaneMode mode;
  final int bitCost;
  final int startingBit;
  final List<int> runs;
  final List<int> minorityPositions;

  const _AdaptiveBitplaneDecision(
    this.mode,
    this.bitCost, {
    required this.startingBit,
    required this.runs,
    this.minorityPositions = const <int>[],
  });
}
