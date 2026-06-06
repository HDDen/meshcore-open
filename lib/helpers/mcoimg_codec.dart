import 'dart:math' as math;
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
}

enum ImageMode { rawGlobal, rawLocal, rleLocal, sparseBg, regionsBg }

enum ScanMode { h, v, s, sv }

class MCOImage {
  final int width;
  final int height;
  final PaletteProfile paletteProfile;
  final List<int> pixels;

  MCOImage({
    required this.width,
    required this.height,
    required this.paletteProfile,
    required List<int> pixels,
  }) : pixels = List.unmodifiable(pixels);
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
  final int regionCount;
  final int backgroundRank;

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
    this.regionCount = 0,
    this.backgroundRank = 0,
  });
}

class MCOImageEncodeDiagnostics {
  final EncodedMCOImage result;
  final List<EncodedMCOImage> candidates;

  const MCOImageEncodeDiagnostics({
    required this.result,
    required this.candidates,
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
  static const String prefix = 'im:';
  static const int _encodeVersion = 1;
  static const int _minSupportedVersion = 0;
  static const int _maxSupportedVersion = 1;
  static const int _containerBlock = 0;
  static const int _containerRegions = 1;
  static const int _minSize = 1;
  static const int _maxSize = 85;
  static const int _defaultMaxRegions = 8;

  static const List<ImageMode> _blockModes = [
    ImageMode.rawGlobal,
    ImageMode.rawLocal,
    ImageMode.rleLocal,
    ImageMode.sparseBg,
  ];

  static const List<ImageMode> _modeTieOrder = [
    ImageMode.sparseBg,
    ImageMode.rleLocal,
    ImageMode.rawLocal,
    ImageMode.rawGlobal,
    ImageMode.regionsBg,
  ];

  EncodedMCOImage encode(
    MCOImage image, {
    int? maxChars,
    int? backgroundColor,
    int maxRegions = _defaultMaxRegions,
  }) {
    final diagnostics = debugEncode(
      image,
      backgroundColor: backgroundColor,
      maxRegions: maxRegions,
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
    int maxRegions = _defaultMaxRegions,
  }) {
    _validateImage(image);
    if (maxRegions < 0) {
      throw const MCOImageInvalidInputException('maxRegions must be >= 0');
    }
    if (backgroundColor != null) {
      _validateColor(backgroundColor, image.paletteProfile, 'backgroundColor');
    }

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
          candidates.add(candidate);
          if (_isBetterCandidate(candidate, best)) {
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
            candidates.add(candidate);
            if (_isBetterCandidate(candidate, best)) {
              best = candidate;
            }
          }
        }
      }

      final regionsPayload = _tryBuildRegionsPayload(
        image,
        bg,
        effectiveMaxRegions,
      );
      if (regionsPayload != null) {
        final candidate = _candidateFromPayload(
          regionsPayload.payload,
          ImageMode.regionsBg,
          ScanMode.h,
          backgroundColor: bg,
          backgroundRank: background.rank,
          regionCount: regionsPayload.regionCount,
        );
        candidates.add(candidate);
        if (_isBetterCandidate(candidate, best)) {
          best = candidate;
        }
      }
    }

    final result = best!;
    return MCOImageEncodeDiagnostics(
      result: result,
      candidates: List.unmodifiable(candidates),
    );
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
      );
    }

    final linear = _decodeBody(reader, width, height, profile, mode);
    reader.finish();

    return MCOImage(
      width: width,
      height: height,
      paletteProfile: profile,
      pixels: _fromScanOrder(linear, width, height, scan),
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
      ImageMode.regionsBg => throw const MCOImageInvalidPayloadException(
        'REGIONS_BG is not a block body mode',
      ),
    };
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
    if (regionCount <= 0 || regionCount > _defaultMaxRegions) {
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
      case ImageMode.regionsBg:
        throw const MCOImageInvalidInputException(
          'REGIONS_BG is not a block mode',
        );
    }
  }

  EncodedMCOImage _candidateFromPayload(
    Uint8List payload,
    ImageMode mode,
    ScanMode scan, {
    _ImageBounds? bounds,
    int? backgroundColor,
    int backgroundRank = 0,
    int regionCount = 0,
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
      backgroundRank: backgroundRank,
      regionCount: regionCount,
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

  static List<_BackgroundCandidate> _backgroundCandidates(
    MCOImage image,
    int? explicitBackground,
  ) {
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
    for (var i = 0; i < math.min(3, colors.length); i++) {
      add(colors[i], 2 + i);
    }
    return result;
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

  static bool _isBetterCandidate(
    EncodedMCOImage candidate,
    EncodedMCOImage? current,
  ) {
    if (current == null) return true;
    if (candidate.charLength != current.charLength) {
      return candidate.charLength < current.charLength;
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
    if (candidate.mode == ImageMode.regionsBg) return 1;
    return 2;
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

  static _LocalPalette _buildLocalPalette(List<int> pixels) {
    final counts = <int, int>{};
    for (final pixel in pixels) {
      counts[pixel] = (counts[pixel] ?? 0) + 1;
    }
    final colors = counts.keys.toList()
      ..sort((a, b) {
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

  static int _localBits(int colorCount) {
    if (colorCount <= 1) return 1;
    return (colorCount - 1).bitLength;
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
    };
  }

  static int _modeBits(ImageMode mode) {
    if (!_blockModes.contains(mode)) {
      throw const MCOImageInvalidInputException(
        'REGIONS_BG has no block mode bits',
      );
    }
    return mode.index;
  }

  static int _scanBits(ScanMode scan) => scan.index;
  static int _profileBits(PaletteProfile profile) => profile.index;

  static ImageMode _modeFromBits(int value) {
    if (value < 0 || value >= _blockModes.length) {
      throw MCOImageInvalidPayloadException('Unknown image mode $value');
    }
    return ImageMode.values[value];
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
    return PaletteProfile.values[value];
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

class _Run {
  final int color;
  final int length;

  const _Run(this.color, this.length);
}

class _SparseSegment {
  final int start;
  final int color;
  final int length;

  const _SparseSegment(this.start, this.color, this.length);
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
