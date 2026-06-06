import 'dart:math' as math;
import 'dart:typed_data';

enum PaletteProfile { mono, master4, master8, master16, master32, master64 }

enum ImageMode { rawGlobal, rawLocal, rleLocal, sparseBg }

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

  const EncodedMCOImage({
    required this.text,
    required this.mode,
    required this.scan,
    required this.byteLength,
    required this.charLength,
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
  static const int _version = 0;
  static const int _minSize = 1;
  static const int _maxSize = 85;

  static const List<ImageMode> _modeTieOrder = [
    ImageMode.sparseBg,
    ImageMode.rleLocal,
    ImageMode.rawLocal,
    ImageMode.rawGlobal,
  ];

  EncodedMCOImage encode(
    MCOImage image, {
    int? maxChars,
    int? backgroundColor,
  }) {
    _validateImage(image);
    if (backgroundColor != null) {
      _validateColor(backgroundColor, image.paletteProfile, 'backgroundColor');
    }

    EncodedMCOImage? best;
    for (final scan in ScanMode.values) {
      final linear = _toScanOrder(
        image.pixels,
        image.width,
        image.height,
        scan,
      );
      for (final mode in ImageMode.values) {
        final payload = _buildPayload(
          image,
          linear,
          mode,
          scan,
          backgroundColor: backgroundColor,
        );
        final text = '$prefix${_Base91.encode(payload)}';
        final candidate = EncodedMCOImage(
          text: text,
          mode: mode,
          scan: scan,
          byteLength: payload.length,
          charLength: text.length,
        );
        if (_isBetterCandidate(candidate, best)) {
          best = candidate;
        }
      }
    }

    final result = best!;
    if (maxChars != null && result.charLength > maxChars) {
      throw MCOImageTooLargeException(
        'Encoded image is ${result.charLength} chars, max is $maxChars',
      );
    }
    return result;
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
    if (version != _version) {
      throw MCOImageInvalidPayloadException('Unsupported version $version');
    }

    final mode = _modeFromBits((header >> 4) & 0x03);
    final scan = _scanFromBits((header >> 2) & 0x03);
    final bgPresent = ((header >> 1) & 0x01) != 0;
    if ((header & 0x01) != 0) {
      throw const MCOImageInvalidPayloadException('Reserved header bit is set');
    }
    final profileHeader = bytes[1];
    final profile = _profileFromBits((profileHeader >> 4) & 0x0f);
    if ((profileHeader & 0x0f) != 0) {
      throw const MCOImageInvalidPayloadException(
        'Reserved palette bits are set',
      );
    }
    if (bgPresent != (mode == ImageMode.sparseBg)) {
      throw const MCOImageInvalidPayloadException(
        'Background flag does not match mode',
      );
    }

    final width = bytes[2] + 1;
    final height = bytes[3] + 1;
    _validateDimensions(width, height, payload: true);

    final reader = _BitReader(bytes, byteIndex: 4);
    final linear = switch (mode) {
      ImageMode.rawGlobal => _decodeRawGlobal(reader, width, height, profile),
      ImageMode.rawLocal => _decodeRawLocal(reader, width, height, profile),
      ImageMode.rleLocal => _decodeRleLocal(reader, width, height, profile),
      ImageMode.sparseBg => _decodeSparseBg(reader, width, height, profile),
    };
    reader.finish();

    return MCOImage(
      width: width,
      height: height,
      paletteProfile: profile,
      pixels: _fromScanOrder(linear, width, height, scan),
    );
  }

  Uint8List _buildPayload(
    MCOImage image,
    List<int> linear,
    ImageMode mode,
    ScanMode scan, {
    int? backgroundColor,
  }) {
    final writer = _BitWriter();
    final bgPresent = mode == ImageMode.sparseBg;
    writer.writeAlignedByte(
      (_version << 6) |
          (_modeBits(mode) << 4) |
          (_scanBits(scan) << 2) |
          (bgPresent ? 0x02 : 0),
    );
    writer.writeAlignedByte(_profileBits(image.paletteProfile) << 4);
    writer.writeAlignedByte(image.width - 1);
    writer.writeAlignedByte(image.height - 1);

    switch (mode) {
      case ImageMode.rawGlobal:
        _encodeRawGlobal(writer, linear, image.paletteProfile);
        break;
      case ImageMode.rawLocal:
        _encodeRawLocal(writer, linear, image.paletteProfile);
        break;
      case ImageMode.rleLocal:
        _encodeRleLocal(writer, linear, image.paletteProfile);
        break;
      case ImageMode.sparseBg:
        _encodeSparseBg(
          writer,
          linear,
          image.paletteProfile,
          backgroundColor: backgroundColor,
        );
        break;
    }
    return writer.toBytes();
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
    int? backgroundColor,
  }) {
    final bg = backgroundColor ?? _mostFrequentColor(linear);
    final globalBits = _globalBits(profile);
    writer.writeBits(bg, globalBits);

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
    PaletteProfile profile,
  ) {
    final count = width * height;
    final bg = reader.readBits(_globalBits(profile));
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
    final candidateRank = _modeTieOrder.indexOf(candidate.mode);
    final currentRank = _modeTieOrder.indexOf(current.mode);
    if (candidateRank != currentRank) return candidateRank < currentRank;
    return candidate.scan.index < current.scan.index;
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

  static int _mostFrequentColor(List<int> pixels) {
    final counts = <int, int>{};
    for (final pixel in pixels) {
      counts[pixel] = (counts[pixel] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) {
      if (a.value != b.value) return a.value > b.value ? a : b;
      return a.key < b.key ? a : b;
    }).key;
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
      PaletteProfile.master16 => 4,
      PaletteProfile.master32 => 5,
      PaletteProfile.master64 => 6,
    };
  }

  static int _paletteSize(PaletteProfile profile) {
    return switch (profile) {
      PaletteProfile.mono => 2,
      PaletteProfile.master4 => 4,
      PaletteProfile.master8 => 8,
      PaletteProfile.master16 => 16,
      PaletteProfile.master32 => 32,
      PaletteProfile.master64 => 64,
    };
  }

  static int _modeBits(ImageMode mode) => mode.index;
  static int _scanBits(ScanMode scan) => scan.index;
  static int _profileBits(PaletteProfile profile) => profile.index;

  static ImageMode _modeFromBits(int value) => ImageMode.values[value];
  static ScanMode _scanFromBits(int value) => ScanMode.values[value];
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
