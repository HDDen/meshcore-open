import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoimg_codec.dart';

void main() {
  final codec = MCOImageCodec();

  group('MCOImageCodec roundtrip', () {
    test('empty 11x11 color 0', () {
      _expectRoundTrip(codec, _solid(11, 11, 0));
    });

    test('checkerboard 11x11', () {
      _expectRoundTrip(codec, _image(11, 11, (x, y) => (x + y) & 1));
    });

    test('vertical stripes 11x11', () {
      _expectRoundTrip(codec, _image(11, 11, (x, _) => x % 4));
    });

    test('horizontal stripes 11x11', () {
      _expectRoundTrip(codec, _image(11, 11, (_, y) => y % 4));
    });

    test('plus on background', () {
      _expectRoundTrip(
        codec,
        _image(11, 11, (x, y) => x == 5 || y == 5 ? 3 : 0),
      );
    });

    test('diagonal on background', () {
      _expectRoundTrip(codec, _image(11, 11, (x, y) => x == y ? 4 : 0));
    });

    test('checkerboard mono', () {
      _expectRoundTrip(
        codec,
        _image(11, 11, (x, y) => (x + y) & 1, profile: PaletteProfile.mono),
      );
    });

    test('four color master-4', () {
      _expectRoundTrip(
        codec,
        _image(11, 11, (x, y) => (x + y) % 4, profile: PaletteProfile.master4),
      );
    });

    test('random 11x11 master-8', () {
      _expectRoundTrip(codec, _randomImage(11, 11, PaletteProfile.master8, 4));
    });

    test('random 11x11 master-16', () {
      _expectRoundTrip(codec, _randomImage(11, 11, PaletteProfile.master16, 4));
    });

    test('random 11x11 master-32', () {
      _expectRoundTrip(codec, _randomImage(11, 11, PaletteProfile.master32, 1));
    });

    test('random 15x8 master-32', () {
      _expectRoundTrip(codec, _randomImage(15, 8, PaletteProfile.master32, 2));
    });

    test('random 16x16 master-64', () {
      _expectRoundTrip(codec, _randomImage(16, 16, PaletteProfile.master64, 3));
    });

    test('single non-zero color', () {
      _expectRoundTrip(codec, _solid(11, 11, 7));
    });

    test('1x1', () {
      _expectRoundTrip(codec, _solid(1, 1, 7));
    });

    test('1x20', () {
      _expectRoundTrip(codec, _image(1, 20, (_, y) => y % 8));
    });

    test('20x1', () {
      _expectRoundTrip(codec, _image(20, 1, (x, _) => x % 8));
    });
  });

  group('MCOImageCodec mode selection', () {
    test('solid canvas is short and sparse', () {
      final encoded = codec.encode(_solid(11, 11, 0));
      expect(encoded.mode, ImageMode.sparseBg);
      expect(encoded.text.length, lessThan(16));
    });

    test('checkerboard prefers a raw local-like representation', () {
      final encoded = codec.encode(_image(11, 11, (x, y) => (x + y) & 1));
      expect(encoded.mode, isNot(ImageMode.rleLocal));
      expect(encoded.byteLength, lessThan(30));
    });

    test('vertical stripes benefit from column scan RLE', () {
      final encoded = codec.encode(_image(11, 11, (x, _) => x % 4));
      expect(encoded.mode, ImageMode.rleLocal);
      expect(encoded.scan, anyOf(ScanMode.v, ScanMode.sv));
    });
  });

  group('MCOImageCodec errors', () {
    test('missing prefix fails', () {
      expect(
        () => codec.decode('xx:abc'),
        throwsA(isA<MCOImageInvalidPayloadException>()),
      );
    });

    test('invalid basE91 fails', () {
      expect(
        () => codec.decode("im:'"),
        throwsA(isA<MCOImageInvalidPayloadException>()),
      );
    });

    test('invalid width or height fails', () {
      final payload = Uint8List.fromList([0, 0, 85, 0]);
      expect(
        () => codec.decode('im:${_base91(payload)}'),
        throwsA(isA<MCOImageInvalidPayloadException>()),
      );
    });

    test('reserved header bits fail', () {
      final payload = Uint8List.fromList([1, 0, 0, 0]);
      expect(
        () => codec.decode('im:${_base91(payload)}'),
        throwsA(isA<MCOImageInvalidPayloadException>()),
      );
    });

    test('unknown palette profile fails', () {
      final payload = Uint8List.fromList([0, 0x20, 0, 0]);
      expect(
        () => codec.decode('im:${_base91(payload)}'),
        throwsA(isA<MCOImageInvalidPayloadException>()),
      );
    });

    test('RLE overrun fails', () {
      final payload = Uint8List.fromList([0x20, 0, 0, 0, 1, 0, 1, 0, 2]);
      expect(
        () => codec.decode('im:${_base91(payload)}'),
        throwsA(isA<MCOImageInvalidPayloadException>()),
      );
    });

    test('wrong pixel count fails', () {
      expect(
        () => codec.encode(
          MCOImage(
            width: 2,
            height: 2,
            paletteProfile: PaletteProfile.master32,
            pixels: const [0, 1, 2],
          ),
        ),
        throwsA(isA<MCOImageInvalidInputException>()),
      );
    });

    test('color outside palette fails', () {
      expect(
        () => codec.encode(_image(2, 2, (_, _) => 32)),
        throwsA(isA<MCOImageInvalidInputException>()),
      );
    });

    test('maxChars fails when output is too long', () {
      expect(
        () => codec.encode(_solid(11, 11, 0), maxChars: 1),
        throwsA(isA<MCOImageTooLargeException>()),
      );
    });
  });
}

void _expectRoundTrip(MCOImageCodec codec, MCOImage image) {
  final encoded = codec.encode(image);
  expect(encoded.text, startsWith(MCOImageCodec.prefix));

  final decoded = codec.decode(encoded.text);
  expect(decoded.width, image.width);
  expect(decoded.height, image.height);
  expect(decoded.paletteProfile, image.paletteProfile);
  expect(decoded.pixels, image.pixels);

  final decodedAgain = codec.decode(codec.encode(decoded).text);
  expect(decodedAgain.pixels, image.pixels);
}

MCOImage _solid(
  int width,
  int height,
  int color, {
  PaletteProfile profile = PaletteProfile.master32,
}) {
  return MCOImage(
    width: width,
    height: height,
    paletteProfile: profile,
    pixels: List<int>.filled(width * height, color),
  );
}

MCOImage _image(
  int width,
  int height,
  int Function(int x, int y) colorAt, {
  PaletteProfile profile = PaletteProfile.master32,
}) {
  return MCOImage(
    width: width,
    height: height,
    paletteProfile: profile,
    pixels: [
      for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++) colorAt(x, y),
    ],
  );
}

MCOImage _randomImage(int width, int height, PaletteProfile profile, int seed) {
  final random = math.Random(seed);
  final colorCount = _paletteSize(profile);
  return MCOImage(
    width: width,
    height: height,
    paletteProfile: profile,
    pixels: List<int>.generate(
      width * height,
      (_) => random.nextInt(colorCount),
    ),
  );
}

int _paletteSize(PaletteProfile profile) {
  return switch (profile) {
    PaletteProfile.mono => 2,
    PaletteProfile.master4 => 4,
    PaletteProfile.master8 => 8,
    PaletteProfile.master16 => 16,
    PaletteProfile.master32 => 32,
    PaletteProfile.master64 => 64,
  };
}

String _base91(Uint8List bytes) {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
      '!#\$%&()*+,./:;<=>?@[]^_`{|}~"';
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
        ..write(alphabet[value % 91])
        ..write(alphabet[value ~/ 91]);
    }
  }
  if (bitCount > 0) {
    output.write(alphabet[queue % 91]);
    if (bitCount > 7 || queue > 90) {
      output.write(alphabet[queue ~/ 91]);
    }
  }
  return output.toString();
}
