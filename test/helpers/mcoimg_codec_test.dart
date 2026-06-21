import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoimg_codec.dart';
import 'package:meshcore_open/helpers/mcoimg_palette.dart';

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

    test('random 11x11 grayscale-8', () {
      _expectRoundTrip(
        codec,
        _randomImage(11, 11, PaletteProfile.grayscale8, 4),
      );
    });

    test('random 11x11 master-16', () {
      _expectRoundTrip(codec, _randomImage(11, 11, PaletteProfile.master16, 4));
    });

    test('random 11x11 grayscale-16', () {
      _expectRoundTrip(
        codec,
        _randomImage(11, 11, PaletteProfile.grayscale16, 4),
      );
    });

    test('random 11x11 master-32', () {
      _expectRoundTrip(codec, _randomImage(11, 11, PaletteProfile.master32, 1));
    });

    test('random 11x11 grayscale-32', () {
      _expectRoundTrip(
        codec,
        _randomImage(11, 11, PaletteProfile.grayscale32, 1),
      );
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

  group('MCOImageCodec dynamic palette tables', () {
    test('global512 and dynamic profile index tables are valid', () {
      expect(MCOImageDynamicPalette.global512, hasLength(512));
      for (final profile in _dynamicProfiles) {
        final indices = MCOImageDynamicPalette.indicesFor(profile);
        expect(indices, hasLength(_paletteSize(profile)));
        expect(indices.toSet(), hasLength(indices.length));
        for (final index in indices) {
          expect(index, inInclusiveRange(0, 511));
        }
      }
      expect(
        MCOImageDynamicPalette.indicesFor(PaletteProfile.dynamicGlobal512),
        List<int>.generate(512, (index) => index),
      );
    });
  });

  group('MCOImageCodec mode selection', () {
    test('solid canvas stays short', () {
      final encoded = codec.encode(_solid(11, 11, 0));
      expect(encoded.text.length, lessThan(16));
      expect(codec.decode(encoded.text).pixels, List<int>.filled(121, 0));
    });

    test('checkerboard prefers a raw local-like representation', () {
      final encoded = codec.encode(_image(11, 11, (x, y) => (x + y) & 1));
      expect(encoded.mode, isNot(ImageMode.rleLocal));
      expect(encoded.byteLength, lessThan(30));
    });

    test('vertical stripes encode no worse than column scan RLE', () {
      final image = _image(11, 11, (x, _) => x % 4);
      final diagnostics = codec.debugEncode(image);
      final columnRleLength = diagnostics.candidates
          .where(
            (candidate) =>
                candidate.mode == ImageMode.rleLocal &&
                (candidate.scan == ScanMode.v ||
                    candidate.scan == ScanMode.sv),
          )
          .map((candidate) => candidate.charLength)
          .reduce(math.min);

      expect(
        diagnostics.result.charLength,
        lessThanOrEqualTo(columnRleLength),
      );
      expect(codec.decode(diagnostics.result.text).pixels, image.pixels);
    });

    test('new payloads use format version 2 by default', () {
      final encoded = codec.encode(_solid(11, 11, 0), backgroundColor: 0);
      final bytes = _base91Decode(
        encoded.text.substring(MCOImageCodec.prefix.length),
      );
      expect((bytes[0] >> 6) & 0x03, 2);
      expect(encoded.codecVersion, 2);
    });

    test(
      'explicit legacy v1 encoding remains available for fixed palettes',
      () {
        final image = _solid(11, 11, 0, profile: PaletteProfile.master8);
        final encoded = codec.encode(
          image,
          backgroundColor: 0,
          encodingVersion: MCOImageEncodingVersion.v1Legacy,
        );
        final bytes = _base91Decode(
          encoded.text.substring(MCOImageCodec.prefix.length),
        );
        expect((bytes[0] >> 6) & 0x03, 1);
        expect(encoded.codecVersion, 1);
        expect(codec.decode(encoded.text).pixels, image.pixels);
      },
    );

    test('legacy v1 encoding rejects dynamic palettes', () {
      final image = _solid(
        2,
        2,
        MCOImageDynamicPalette.whiteGlobalIndexFor(
          PaletteProfile.dynamicGlobal8,
        ),
        profile: PaletteProfile.dynamicGlobal8,
      );
      expect(
        () => codec.encode(
          image,
          encodingVersion: MCOImageEncodingVersion.v1Legacy,
        ),
        throwsA(isA<MCOImageInvalidInputException>()),
      );
    });

    test('larger empty canvas stays close to small drawing size', () {
      final small = _image(
        11,
        11,
        (x, y) => x == 5 || y == 5 ? 1 : 0,
        profile: PaletteProfile.mono,
      );
      final large = _image(
        20,
        20,
        (x, y) => x >= 4 && x <= 14 && y >= 4 && y <= 14
            ? (x == 9 || y == 9 ? 1 : 0)
            : 0,
        profile: PaletteProfile.mono,
      );

      final smallEncoded = codec.encode(small, backgroundColor: 0);
      final largeEncoded = codec.encode(large, backgroundColor: 0);
      final decoded = codec.decode(largeEncoded.text);

      expect(
        largeEncoded.charLength,
        lessThanOrEqualTo(smallEncoded.charLength + 20),
      );
      expect(decoded.width, 20);
      expect(decoded.height, 20);
      expect(decoded.pixels, large.pixels);
    });

    test('empty white canvases stay very short across sizes', () {
      final small = codec.encode(
        _solid(11, 11, 0, profile: PaletteProfile.mono),
        backgroundColor: 0,
      );
      final large = codec.encode(
        _solid(30, 30, 0, profile: PaletteProfile.mono),
        backgroundColor: 0,
      );

      expect(small.charLength, lessThan(20));
      expect(large.charLength, lessThan(20));
      expect(large.charLength, lessThanOrEqualTo(small.charLength + 3));
    });

    test('most frequent non-zero background can win', () {
      final image = _image(30, 30, (x, y) {
        final compactPlus =
            (x == 15 && y >= 13 && y <= 17) || (y == 15 && x >= 13 && x <= 17);
        if (compactPlus) return 1;
        return 2;
      });

      final encoded = codec.encode(image);

      expect(encoded.backgroundColor, 2);
      expect(encoded.boundsPresent, isTrue);
      expect(codec.decode(encoded.text).pixels, image.pixels);
    });

    test('background candidates are measured by final text length', () {
      final image = _image(18, 18, (x, y) {
        if (x == 8 && y == 8) return 1;
        if (x >= 7 && x <= 10 && y >= 7 && y <= 10) return 2;
        return 0;
      });

      final diagnostics = codec.debugEncode(image);
      final minLength = diagnostics.candidates
          .map((candidate) => candidate.charLength)
          .reduce(math.min);

      expect(diagnostics.result.charLength, minLength);
      expect(
        diagnostics.candidates.map((candidate) => candidate.backgroundColor),
        containsAll([0, 2]),
      );
      expect(codec.decode(diagnostics.result.text).pixels, image.pixels);
    });

    test('all frequent master8 colors are considered as backgrounds', () {
      final image = _image(
        16,
        16,
        (x, y) => (x + y * 3) % 8,
        profile: PaletteProfile.master8,
      );
      final diagnostics = codec.debugEncode(image);
      final backgrounds = diagnostics.candidates
          .map((candidate) => candidate.backgroundColor)
          .toSet();

      expect(backgrounds, containsAll(List<int>.generate(8, (index) => index)));
    });

    test('text output selects the shortest final Base91 text', () {
      final image = _image(22, 22, (x, y) => (x * 3 + y * 5) % 8);
      final diagnostics = codec.debugEncode(
        image,
        outputTarget: MCOImageOutputTarget.text,
      );
      final shortest = diagnostics.candidates
          .map((candidate) => candidate.charLength)
          .reduce(math.min);

      expect(diagnostics.result.charLength, shortest);
    });

    test('binary output selects the shortest binary payload', () {
      final image = _image(22, 22, (x, y) => (x * 3 + y * 5) % 8);
      final diagnostics = codec.debugEncode(
        image,
        outputTarget: MCOImageOutputTarget.binary,
      );
      final shortest = diagnostics.candidates
          .map((candidate) => candidate.byteLength)
          .reduce(math.min);

      expect(diagnostics.result.byteLength, shortest);
      expect(codec.decode(diagnostics.result.text).pixels, image.pixels);
    });

    test('bounds are recomputed for each background candidate', () {
      final image = _image(10, 10, (x, y) {
        if (x == 4 && y == 4) return 1;
        if (x >= 3 && x <= 5 && y >= 3 && y <= 5) return 2;
        return 0;
      });

      final diagnostics = codec.debugEncode(image);
      final bg0Bounds = diagnostics.candidates.firstWhere(
        (candidate) =>
            candidate.backgroundColor == 0 && candidate.boundsPresent,
      );
      final bg2Bounds = diagnostics.candidates.firstWhere(
        (candidate) =>
            candidate.backgroundColor == 2 && candidate.boundsPresent,
        orElse: () => diagnostics.candidates.firstWhere(
          (candidate) =>
              candidate.backgroundColor == 2 && !candidate.boundsPresent,
        ),
      );

      expect(bg0Bounds.boundsWidth! * bg0Bounds.boundsHeight!, lessThan(100));
      expect(bg2Bounds.boundsPresent, isFalse);
    });

    test(
      'fragmented drawing inside large background uses bounded local body',
      () {
        final image = _image(40, 40, (x, y) {
          if (x < 15 || x > 20 || y < 12 || y > 17) return 0;
          return (x + y).isEven ? 3 : 7;
        });

        final encoded = codec.encode(image, backgroundColor: 0);

        expect(encoded.boundsPresent, isTrue);
        expect(
          encoded.mode,
          anyOf(
            ImageMode.rawLocal,
            ImageMode.rleLocal,
            ImageMode.extended,
          ),
        );
        expect(codec.decode(encoded.text).pixels, image.pixels);
      },
    );

    test('separate compact regions remain competitive and roundtrip', () {
      final image = _image(40, 40, (x, y) {
        final first = x >= 2 && x <= 4 && y >= 2 && y <= 4;
        final second = x >= 31 && x <= 33 && y >= 31 && y <= 33;
        return first || second ? 1 : 0;
      }, profile: PaletteProfile.mono);

      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final regions = diagnostics.candidates.where(
        (candidate) => candidate.mode == ImageMode.regionsBg,
      );

      expect(regions, isNotEmpty);
      expect(regions.length, greaterThan(1));
      expect(regions.first.regionCount, 2);
      final shortestRegionLength = regions
          .map((candidate) => candidate.charLength)
          .reduce(math.min);
      expect(
        diagnostics.result.charLength,
        lessThanOrEqualTo(shortestRegionLength),
      );
      expect(codec.decode(diagnostics.result.text).pixels, image.pixels);
    });

    test('beam regions merge nearby components when payload is smaller', () {
      final image = _image(16, 16, (x, y) {
        final selected =
            (x == 5 || x == 7) &&
            (y == 5 || y == 7);
        return selected ? 1 : 0;
      }, profile: PaletteProfile.mono);
      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final beamCandidates = diagnostics.candidates.where(
        (candidate) => candidate.container == 'regions-beam',
      );
      final existingRegions = diagnostics.candidates.where(
        (candidate) => candidate.container == 'regions',
      );

      expect(beamCandidates, isNotEmpty);
      expect(existingRegions, isNotEmpty);
      final shortestExisting = existingRegions
          .map((candidate) => candidate.byteLength)
          .reduce(math.min);
      for (final candidate in beamCandidates) {
        expect(candidate.byteLength, lessThan(shortestExisting));
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('beam regions support dynamic palettes', () {
      final colors = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal32,
      );
      final image = _image(16, 16, (x, y) {
        final selected =
            (x == 5 || x == 7) &&
            (y == 5 || y == 7);
        return selected ? colors[3] : colors[0];
      }, profile: PaletteProfile.dynamicGlobal32);
      final diagnostics = codec.debugEncode(
        image,
        backgroundColor: colors[0],
      );
      final candidates = diagnostics.candidates.where(
        (candidate) => candidate.container == 'regions-beam',
      );

      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('single compact drawing prefers bounds over regions', () {
      final image = _image(40, 40, (x, y) {
        return x >= 18 && x <= 21 && y >= 18 && y <= 21 ? 1 : 0;
      }, profile: PaletteProfile.mono);

      final encoded = codec.encode(image, backgroundColor: 0);

      expect(encoded.mode, isNot(ImageMode.regionsBg));
      expect(encoded.boundsPresent, isTrue);
      expect(codec.decode(encoded.text).pixels, image.pixels);
    });

    test('too many isolated components skip regions candidates', () {
      final image = _image(40, 40, (x, y) {
        for (var i = 0; i < 9; i++) {
          if (x == 2 + i * 4 && y == 2) return 1;
        }
        return 0;
      }, profile: PaletteProfile.mono);

      final diagnostics = codec.debugEncode(
        image,
        backgroundColor: 0,
        maxRegions: 8,
      );

      expect(
        diagnostics.candidates.any(
          (candidate) =>
              candidate.backgroundColor == 0 &&
              candidate.mode == ImageMode.regionsBg,
        ),
        isFalse,
      );
      expect(codec.decode(diagnostics.result.text).pixels, image.pixels);
    });

    test('larger canvas around same separated regions stays compact', () {
      final small = _image(20, 20, (x, y) {
        final first = x >= 2 && x <= 3 && y >= 2 && y <= 3;
        final second = x >= 16 && x <= 17 && y >= 16 && y <= 17;
        return first || second ? 1 : 0;
      }, profile: PaletteProfile.mono);
      final large = _image(50, 50, (x, y) {
        final first = x >= 8 && x <= 9 && y >= 8 && y <= 9;
        final second = x >= 42 && x <= 43 && y >= 42 && y <= 43;
        return first || second ? 1 : 0;
      }, profile: PaletteProfile.mono);

      final smallEncoded = codec.encode(small, backgroundColor: 0);
      final largeEncoded = codec.encode(large, backgroundColor: 0);

      expect(
        largeEncoded.charLength,
        lessThanOrEqualTo(smallEncoded.charLength + 10),
      );
      expect(codec.decode(largeEncoded.text).pixels, large.pixels);
    });

    test('v2 compact bounds candidates roundtrip', () {
      final image = _image(24, 24, (x, y) {
        final plus = (x == 12 && y >= 9 && y <= 15) ||
            (y == 12 && x >= 9 && x <= 15);
        return plus ? 1 : 0;
      }, profile: PaletteProfile.mono);
      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final compactCandidates = diagnostics.candidates.where(
        (candidate) => candidate.container == 'compact-bounds',
      );

      expect(compactCandidates, isNotEmpty);
      for (final candidate in compactCandidates) {
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('v2 compact regions use extended mode and roundtrip', () {
      final image = _image(24, 24, (x, y) {
        final first = x >= 2 && x <= 4 && y >= 3 && y <= 5;
        final second = x >= 18 && x <= 21 && y >= 17 && y <= 20;
        return first || second ? 1 : 0;
      }, profile: PaletteProfile.mono);
      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final regionCandidate = diagnostics.candidates.firstWhere(
        (candidate) {
          if (candidate.mode != ImageMode.regionsBg) return false;
          final bytes = _base91Decode(
            candidate.text.substring(MCOImageCodec.prefix.length),
          );
          return ((bytes.first >> 3) & 0x07) == 7;
        },
      );
      final bytes = _base91Decode(
        regionCandidate.text.substring(MCOImageCodec.prefix.length),
      );

      expect((bytes.first >> 3) & 0x07, 7);
      expect(codec.decode(regionCandidate.text).pixels, image.pixels);
    });

    test('solid rectangles candidate roundtrips and can win', () {
      final image = _image(24, 24, (x, y) {
        if (x >= 2 && x <= 10 && y >= 3 && y <= 12) return 1;
        if (x >= 15 && x <= 21 && y >= 16 && y <= 21) return 2;
        return 0;
      }, profile: PaletteProfile.master8);
      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final solidCandidate = diagnostics.candidates.firstWhere(
        (candidate) => candidate.container == 'solid-rects',
      );

      expect(codec.decode(solidCandidate.text).pixels, image.pixels);
      expect(diagnostics.result.byteLength, lessThanOrEqualTo(20));
    });

    test('compact RLE candidates roundtrip', () {
      final image = _image(
        24,
        24,
        (x, y) => ((x ~/ 3) + (y ~/ 4)) % 4,
        profile: PaletteProfile.master8,
      );
      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final compactCandidates = diagnostics.candidates.where(
        (candidate) => candidate.container.startsWith('compact-rle'),
      );

      expect(compactCandidates, isNotEmpty);
      for (final candidate in compactCandidates) {
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('compact sparse candidates roundtrip', () {
      final image = _image(24, 24, (x, y) {
        if (x < 7 || x > 16 || y < 6 || y > 17) return 0;
        if ((x + y) % 5 == 0) return 1;
        if ((x * 3 + y) % 11 == 0) return 4;
        return 0;
      }, profile: PaletteProfile.master8);
      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final compactCandidates = diagnostics.candidates.where(
        (candidate) => candidate.container.startsWith('compact-sparse'),
      );

      expect(compactCandidates, isNotEmpty);
      expect(
        compactCandidates.any(
          (candidate) => candidate.container == 'compact-sparse-bounds',
        ),
        isTrue,
      );
      for (final candidate in compactCandidates) {
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('legacy and adaptive bitplanes candidates coexist and roundtrip', () {
      final image = _image(
        16,
        16,
        (x, y) => ((x ~/ 2) + (y ~/ 3)) % 8,
        profile: PaletteProfile.master8,
      );
      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final bitplanesCandidates = diagnostics.candidates.where(
        (candidate) => candidate.container.contains('bitplanes'),
      );

      expect(
        bitplanesCandidates.map((candidate) => candidate.container),
        contains('bitplanes'),
      );
      expect(
        bitplanesCandidates.map((candidate) => candidate.container),
        contains('adaptive-bitplanes'),
      );
      for (final candidate in bitplanesCandidates) {
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('direct grayscale bitplanes candidate roundtrips', () {
      final image = _image(
        17,
        13,
        (x, y) => (x + y * 2) % 8,
        profile: PaletteProfile.grayscale8,
      );
      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final candidates = diagnostics.candidates.where(
        (candidate) =>
            candidate.container == 'direct-grayscale-bitplanes' ||
            candidate.container == 'direct-grayscale-bitplanes-bounds',
      );

      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('optimal LZ parsing beats greedy tokenization when useful', () {
      final image = MCOImage(
        width: 10,
        height: 1,
        paletteProfile: PaletteProfile.master4,
        pixels: const [0, 1, 2, 3, 1, 2, 3, 0, 2, 0],
      );
      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final optimalCandidates = diagnostics.candidates.where(
        (candidate) => candidate.container == 'lz-pixels-optimal',
      );

      expect(optimalCandidates, isNotEmpty);
      for (final optimal in optimalCandidates) {
        final greedy = diagnostics.candidates.firstWhere(
          (candidate) =>
              candidate.container == 'lz-pixels' &&
              candidate.scan == optimal.scan &&
              candidate.backgroundColor == optimal.backgroundColor &&
              candidate.dynamicReferenceEncoding ==
                  optimal.dynamicReferenceEncoding,
        );
        expect(optimal.byteLength, lessThanOrEqualTo(greedy.byteLength));
        expect(codec.decode(optimal.text).pixels, image.pixels);
      }
    });

    test('optimal LZ bounds candidates roundtrip', () {
      const sequence = [0, 1, 2, 3, 1, 2, 3, 0, 2, 0];
      final image = _image(
        14,
        3,
        (x, y) {
          if (y != 1 || x < 2 || x >= 12) return 0;
          return sequence[x - 2];
        },
        profile: PaletteProfile.master4,
      );
      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final candidates = diagnostics.candidates.where(
        (candidate) => candidate.container == 'lz-pixels-optimal-bounds',
      );

      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('optimal LZ parsing supports dynamic palettes', () {
      final colors = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal128,
      );
      final pattern = [
        colors[0],
        colors[1],
        colors[2],
        colors[3],
        colors[1],
        colors[2],
        colors[3],
        colors[0],
        colors[2],
        colors[0],
      ];
      final image = MCOImage(
        width: pattern.length,
        height: 1,
        paletteProfile: PaletteProfile.dynamicGlobal128,
        pixels: pattern,
      );
      final diagnostics = codec.debugEncode(
        image,
        backgroundColor: colors.first,
      );
      final candidates = diagnostics.candidates.where(
        (candidate) => candidate.container == 'lz-pixels-optimal',
      );

      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('dynamic adaptive bitplanes candidates roundtrip', () {
      final colors = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal8,
      );
      final image = _image(
        15,
        11,
        (x, y) => colors[((x ~/ 3) + y) % colors.length],
        profile: PaletteProfile.dynamicGlobal8,
      );
      final diagnostics = codec.debugEncode(
        image,
        backgroundColor: colors.first,
      );
      final candidates = diagnostics.candidates.where(
        (candidate) => candidate.container.startsWith('adaptive-bitplanes'),
      );

      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('dynamic adaptive bitplanes palette orders roundtrip', () {
      final colors = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal32,
      );
      final sequence = [
        colors[0],
        colors[29],
        colors[29],
        colors[29],
        colors[4],
        colors[24],
        colors[7],
        colors[18],
        colors[12],
      ];
      final image = _image(
        18,
        12,
        (x, y) => sequence[(x + y * 5) % sequence.length],
        profile: PaletteProfile.dynamicGlobal32,
      );
      final diagnostics = codec.debugEncode(
        image,
        backgroundColor: colors.first,
      );

      for (final container in const [
        'adaptive-bitplanes-profile-order',
        'adaptive-bitplanes-rgb-order',
        'adaptive-bitplanes-transition-order',
      ]) {
        final candidate = diagnostics.candidates.firstWhere(
          (candidate) => candidate.container == container,
        );
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('master palettes support adaptive bitplanes palette orders', () {
      for (final profile in const [
        PaletteProfile.master4,
        PaletteProfile.master8,
        PaletteProfile.master16,
        PaletteProfile.master32,
        PaletteProfile.master64,
      ]) {
        final paletteSize = MCOImagePalette.colorsFor(profile).length;
        final image = _image(
          18,
          14,
          (x, y) {
            if (x < 2 || x >= 16 || y < 2 || y >= 12) return 0;
            if (x == 2 || x == 15 || y == 2 || y == 11) return 1;
            return paletteSize - 1;
          },
          profile: profile,
        );
        final diagnostics = codec.debugEncode(image, backgroundColor: 0);
        final adaptiveCandidates = diagnostics.candidates.where(
          (candidate) =>
              candidate.container.startsWith('adaptive-bitplanes-') &&
              candidate.container.contains('-order'),
        ).toList();
        final rowDeltaCandidates = diagnostics.candidates.where(
          (candidate) => candidate.container.startsWith(
            'compact-row-delta-palette-optimized',
          ),
        ).toList();

        for (final container in const [
          'adaptive-bitplanes-profile-order',
          'adaptive-bitplanes-rgb-order',
          'adaptive-bitplanes-transition-order',
        ]) {
          expect(
            adaptiveCandidates.any(
              (candidate) => candidate.container == container,
            ),
            isTrue,
            reason: '$profile has no $container candidate',
          );
        }
        expect(
          rowDeltaCandidates,
          isNotEmpty,
          reason: '$profile has no row delta order variant',
        );
        for (final candidate in [
          ...adaptiveCandidates,
          ...rowDeltaCandidates,
        ]) {
          expect(
            codec.decode(candidate.text).pixels,
            image.pixels,
            reason: '$profile ${candidate.container}',
          );
        }
      }
    });

    test('multi-start adaptive bitplanes improve a structured corpus', () {
      final images = <MCOImage>[
        _image(
          24,
          20,
          (x, y) => (x * 3 + y * 5 + (x * y) % 7) % 12,
          profile: PaletteProfile.master16,
        ),
        _image(
          24,
          20,
          (x, y) => ((x ~/ 3) * 5 + (y ~/ 2) * 7 + y) % 14,
          profile: PaletteProfile.master16,
        ),
        _image(
          24,
          20,
          (x, y) => ((x + y) % 5 == 0 ? x + y * 3 : x ~/ 2 + y) % 16,
          profile: PaletteProfile.master16,
        ),
      ];
      final multiStartCandidates = <EncodedMCOImage>[];

      for (final image in images) {
        final diagnostics = codec.debugEncode(image, backgroundColor: 0);
        final candidates = diagnostics.candidates.where(
          (candidate) => candidate.container.startsWith(
            'adaptive-bitplanes-multistart',
          ),
        );
        for (final candidate in candidates) {
          multiStartCandidates.add(candidate);
          final existing = diagnostics.candidates.where(
            (other) =>
                other.container.startsWith('adaptive-bitplanes') &&
                !other.container.contains('multistart') &&
                other.scan == candidate.scan &&
                other.boundsPresent == candidate.boundsPresent &&
                other.boundsX == candidate.boundsX &&
                other.boundsY == candidate.boundsY &&
                other.boundsWidth == candidate.boundsWidth &&
                other.boundsHeight == candidate.boundsHeight &&
                other.backgroundColor == candidate.backgroundColor &&
                other.dynamicReferenceEncoding ==
                    candidate.dynamicReferenceEncoding,
          );
          final shortestExisting = existing
              .map((other) => other.byteLength)
              .reduce(math.min);
          expect(candidate.byteLength, lessThanOrEqualTo(shortestExisting));
          expect(codec.decode(candidate.text).pixels, image.pixels);
        }
      }

      expect(multiStartCandidates, isNotEmpty);
    });

    test('direct dynamic bitplanes candidate roundtrips', () {
      final colors = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal32,
      );
      final image = _image(
        16,
        12,
        (x, y) => colors[(x * 3 + y * 5) % colors.length],
        profile: PaletteProfile.dynamicGlobal32,
      );
      final diagnostics = codec.debugEncode(
        image,
        backgroundColor: colors.first,
      );
      final candidates = diagnostics.candidates.where(
        (candidate) =>
            candidate.container == 'direct-dynamic-bitplanes' ||
            candidate.container == 'direct-dynamic-bitplanes-bounds',
      );

      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        final decoded = codec.decode(candidate.text);
        expect(decoded.paletteProfile, image.paletteProfile);
        expect(decoded.pixels, image.pixels);
      }
    });

    test('direct dynamic bitplanes supports more than 64 used colors', () {
      final colors = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal128,
      );
      final image = _image(
        16,
        8,
        (x, y) => colors[y * 16 + x],
        profile: PaletteProfile.dynamicGlobal128,
      );
      final diagnostics = codec.debugEncode(
        image,
        backgroundColor: colors.first,
      );
      final decoded = codec.decode(diagnostics.result.text);

      expect(
        diagnostics.result.container,
        startsWith('direct-dynamic-bitplanes'),
      );
      expect(decoded.paletteProfile, image.paletteProfile);
      expect(decoded.pixels, image.pixels);
    });

    test('debug diagnostics include decodable candidates for all palettes', () {
      for (final profile in _fixedProfiles) {
        final image = _image(
          13,
          9,
          (x, y) => (x * 3 + y * 5) % _paletteSize(profile),
          profile: profile,
        );
        final diagnostics = codec.debugEncode(image, backgroundColor: 0);
        final scans = diagnostics.candidates.map((c) => c.scan).toSet();
        expect(scans, containsAll(ScanMode.values));
        for (final candidate in diagnostics.candidates) {
          final decoded = codec.decode(candidate.text);
          expect(decoded.width, image.width);
          expect(decoded.height, image.height);
          expect(decoded.paletteProfile, image.paletteProfile);
          expect(decoded.pixels, image.pixels);
        }
      }
    });

    test('dynamicGlobal8 encodes as version 2 and decodes global indices', () {
      final colors = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal8,
      );
      final image = _image(
        11,
        11,
        (x, y) => colors[(x + y) % colors.length],
        profile: PaletteProfile.dynamicGlobal8,
      );

      final encoded = codec.encode(image, backgroundColor: colors.first);
      final bytes = _base91Decode(
        encoded.text.substring(MCOImageCodec.prefix.length),
      );

      expect(bytes.first >> 6, 2);
      expect(encoded.codecVersion, 2);
      expect(codec.decode(encoded.text).pixels, image.pixels);
    });

    test('dynamicGlobal512 supports banked candidates and roundtrips', () {
      final image = _image(8, 8, (x, y) {
        final bank = (x + y) % 4;
        final offset = (x * 7 + y * 5) & 0x3f;
        return (bank << 6) | offset;
      }, profile: PaletteProfile.dynamicGlobal512);

      final diagnostics = codec.debugEncode(image, backgroundColor: 0);

      expect(
        diagnostics.candidates.map((c) => c.dynamicReferenceEncoding),
        contains(DynamicPaletteReferenceEncoding.banked8x64),
      );
      expect(codec.decode(diagnostics.result.text).pixels, image.pixels);
    });

    test('compact dynamic palette descriptors roundtrip', () {
      final colors = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal128,
      );
      final selected = colors.sublist(64, 72);
      final image = _image(
        16,
        12,
        (x, y) => selected[(x + y * 3) % selected.length],
        profile: PaletteProfile.dynamicGlobal128,
      );
      final diagnostics = codec.debugEncode(
        image,
        backgroundColor: selected.first,
      );

      for (final encoding in const [
        DynamicPaletteReferenceEncoding.sortedDelta,
        DynamicPaletteReferenceEncoding.rangeRuns,
        DynamicPaletteReferenceEncoding.profileBitmap,
      ]) {
        final candidates = diagnostics.candidates.where(
          (candidate) => candidate.dynamicReferenceEncoding == encoding,
        );
        expect(candidates, isNotEmpty);
        final representatives = <String, EncodedMCOImage>{};
        for (final candidate in candidates) {
          representatives.putIfAbsent(candidate.container, () => candidate);
        }
        for (final candidate in representatives.values) {
          expect(codec.decode(candidate.text).pixels, image.pixels);
        }
      }
    });

    test('range descriptor shrinks a contiguous dynamic palette', () {
      final colors = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal128,
      );
      final selected = colors.sublist(64, 72);
      final image = _image(
        16,
        8,
        (x, y) => selected[(x + y) % selected.length],
        profile: PaletteProfile.dynamicGlobal128,
      );
      final diagnostics = codec.debugEncode(
        image,
        backgroundColor: selected.first,
      );

      EncodedMCOImage candidateFor(
        DynamicPaletteReferenceEncoding encoding,
      ) => diagnostics.candidates.firstWhere(
        (candidate) =>
            candidate.container == 'compact-rle' &&
            candidate.scan == ScanMode.h &&
            candidate.backgroundColor == selected.first &&
            candidate.dynamicReferenceEncoding == encoding,
      );

      final flat = candidateFor(DynamicPaletteReferenceEncoding.flat);
      final ranges = candidateFor(
        DynamicPaletteReferenceEncoding.rangeRuns,
      );
      expect(ranges.byteLength, lessThan(flat.byteLength));
      expect(codec.decode(ranges.text).pixels, image.pixels);
    });

    test('profile bitmap shrinks a dense scattered dynamic palette', () {
      final colors = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal128,
      );
      final selected = List<int>.generate(64, (index) => colors[index * 2]);
      final image = _image(
        16,
        8,
        (x, y) => selected[(x + y * 5) % selected.length],
        profile: PaletteProfile.dynamicGlobal128,
      );
      final diagnostics = codec.debugEncode(
        image,
        backgroundColor: selected.first,
      );

      EncodedMCOImage candidateFor(
        DynamicPaletteReferenceEncoding encoding,
      ) => diagnostics.candidates.firstWhere(
        (candidate) =>
            candidate.container == 'compact-rle' &&
            candidate.scan == ScanMode.h &&
            candidate.backgroundColor == selected.first &&
            candidate.dynamicReferenceEncoding == encoding,
      );

      final flat = candidateFor(DynamicPaletteReferenceEncoding.flat);
      final bitmap = candidateFor(
        DynamicPaletteReferenceEncoding.profileBitmap,
      );
      expect(bitmap.byteLength, lessThan(flat.byteLength));
      expect(codec.decode(bitmap.text).pixels, image.pixels);
    });

    test('bank bitmaps shrink a dense dynamicGlobal512 bank', () {
      final selected = List<int>.generate(32, (index) => 64 + index);
      final image = _image(
        16,
        8,
        (x, y) => selected[(x + y * 3) % selected.length],
        profile: PaletteProfile.dynamicGlobal512,
      );
      final diagnostics = codec.debugEncode(
        image,
        backgroundColor: selected.first,
      );

      EncodedMCOImage candidateFor(
        DynamicPaletteReferenceEncoding encoding,
      ) => diagnostics.candidates.firstWhere(
        (candidate) =>
            candidate.container == 'compact-rle' &&
            candidate.scan == ScanMode.h &&
            candidate.backgroundColor == selected.first &&
            candidate.dynamicReferenceEncoding == encoding,
      );

      final banked = candidateFor(
        DynamicPaletteReferenceEncoding.banked8x64,
      );
      final bitmaps = candidateFor(
        DynamicPaletteReferenceEncoding.bankBitmaps,
      );
      expect(bitmaps.byteLength, lessThan(banked.byteLength));
      expect(codec.decode(bitmaps.text).pixels, image.pixels);
    });

    test('dynamic white background is implicit and roundtrips', () {
      final colors = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal128,
      );
      final white = MCOImageDynamicPalette.whiteGlobalIndexFor(
        PaletteProfile.dynamicGlobal128,
      );
      final image = _image(20, 20, (x, y) {
        final inside = x >= 7 && x <= 12 && y >= 7 && y <= 12;
        return inside ? colors[70] : white;
      }, profile: PaletteProfile.dynamicGlobal128);
      final diagnostics = codec.debugEncode(image, backgroundColor: white);
      final candidates = diagnostics.candidates.where(
        (candidate) => candidate.backgroundColor == white,
      );

      expect(candidates, isNotEmpty);
      final representatives = <String, EncodedMCOImage>{};
      for (final candidate in candidates) {
        representatives.putIfAbsent(candidate.container, () => candidate);
      }
      for (final candidate in representatives.values) {
        final bytes = _base91Decode(
          candidate.text.substring(MCOImageCodec.prefix.length),
        );
        expect(bytes[1] & 0x08, isNot(0));
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('transition-optimized dynamic row delta roundtrips', () {
      final colors = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal32,
      );
      final sequence = [colors[0], colors[3], colors[1], colors[2]];
      final image = _image(
        16,
        12,
        (x, y) => sequence[(x + y) % sequence.length],
        profile: PaletteProfile.dynamicGlobal32,
      );
      final diagnostics = codec.debugEncode(
        image,
        backgroundColor: sequence.first,
      );
      final candidates = diagnostics.candidates.where(
        (candidate) => candidate.container.startsWith(
          'compact-row-delta-palette-optimized',
        ),
      );

      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('dynamic profiles support regions candidates', () {
      final colors = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal8,
      );
      final image = _image(20, 20, (x, y) {
        final first = x >= 2 && x <= 3 && y >= 2 && y <= 3;
        final second = x >= 15 && x <= 16 && y >= 15 && y <= 16;
        return first || second ? colors[3] : colors[0];
      }, profile: PaletteProfile.dynamicGlobal8);

      final diagnostics = codec.debugEncode(image, backgroundColor: colors[0]);

      expect(
        diagnostics.candidates.map((c) => c.mode),
        contains(ImageMode.regionsBg),
      );
      for (final candidate in diagnostics.candidates.where(
        (candidate) => candidate.mode == ImageMode.regionsBg,
      )) {
        final decoded = codec.decode(candidate.text);
        expect(decoded.paletteProfile, image.paletteProfile);
        expect(decoded.pixels, image.pixels);
      }
    });

    test('dynamic encoder preserves the selected dynamic profile', () {
      final image = _image(
        11,
        11,
        (x, y) => ((x + y) & 1) == 0 ? 0 : 63,
        profile: PaletteProfile.dynamicGlobal32,
      );

      final encoded = codec.encode(image, backgroundColor: 0);
      final decoded = codec.decode(encoded.text);

      expect(encoded.codecVersion, 2);
      expect(decoded.paletteProfile, PaletteProfile.dynamicGlobal32);
      expect(decoded.pixels, image.pixels);
    });

    test('compact dynamic profiles mirror existing master palettes', () {
      expect(
        MCOImageDynamicPalette.colorsFor(PaletteProfile.dynamicGlobal8),
        MCOImagePalette.master8,
      );
      expect(
        MCOImageDynamicPalette.colorsFor(PaletteProfile.dynamicGlobal16),
        MCOImagePalette.master16,
      );
      expect(
        MCOImageDynamicPalette.colorsFor(PaletteProfile.dynamicGlobal32),
        MCOImagePalette.master32,
      );
      expect(
        MCOImageDynamicPalette.colorsFor(PaletteProfile.dynamicGlobal64),
        MCOImagePalette.master64,
      );
    });

    test('fixed local palettes can use compact descriptors', () {
      final image = _image(
        16,
        16,
        (x, y) => (x + y * 3) % 16,
        profile: PaletteProfile.master64,
      );
      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final candidate = diagnostics.candidates.firstWhere(
        (item) =>
            item.mode == ImageMode.rawLocal &&
            item.scan == ScanMode.h &&
            !item.boundsPresent,
      );
      final bytes = _base91Decode(
        candidate.text.substring(MCOImageCodec.prefix.length),
      );

      expect(bytes[4], 0);
      expect(codec.decode(candidate.text).pixels, image.pixels);
    });

    test('fixed regions can share one local palette', () {
      final image = _image(
        24,
        24,
        (x, y) {
          final first = x >= 2 && x <= 5 && y >= 2 && y <= 5;
          final second = x >= 18 && x <= 21 && y >= 18 && y <= 21;
          if (first) return 8 + ((x + y) & 3);
          if (second) return 8 + ((x * 3 + y) & 3);
          return 0;
        },
        profile: PaletteProfile.master32,
      );
      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final candidates = diagnostics.candidates.where(
        (item) => item.container.contains('regions-shared-fixed'),
      );

      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        final bytes = _base91Decode(
          candidate.text.substring(MCOImageCodec.prefix.length),
        );
        expect(bytes[1] & 0x20, isNot(0));
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('fixed extended blocks can start without byte alignment', () {
      final image = _image(
        13,
        11,
        (x, y) => (x ~/ 2 + y) % 8,
        profile: PaletteProfile.master16,
      );
      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final candidates = diagnostics.candidates.where(
        (item) => item.mode == ImageMode.extended,
      );

      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        final bytes = _base91Decode(
          candidate.text.substring(MCOImageCodec.prefix.length),
        );
        expect(bytes[1] & 0x20, isNot(0));
        expect(codec.decode(candidate.text).pixels, image.pixels);
      }
    });

    test('empty fixed canvas uses the short solid background grammar', () {
      final image = _solid(
        30,
        30,
        0,
        profile: PaletteProfile.master64,
      );
      final diagnostics = codec.debugEncode(image, backgroundColor: 0);
      final candidate = diagnostics.candidates.firstWhere(
        (item) => item.container == 'solid-bg',
      );

      expect(candidate.byteLength, 4);
      expect(codec.decode(candidate.text).pixels, image.pixels);
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

    test('width or height above 256 fails on encode', () {
      expect(
        () => codec.encode(
          MCOImage(
            width: 257,
            height: 1,
            paletteProfile: PaletteProfile.mono,
            pixels: List<int>.filled(257, 0),
          ),
        ),
        throwsA(isA<MCOImageInvalidInputException>()),
      );
    });

    test('256x256 dimensions are valid', () {
      final image = MCOImage(
        width: 256,
        height: 256,
        paletteProfile: PaletteProfile.mono,
        pixels: List<int>.filled(256 * 256, 0),
      );
      final encoded = codec.encode(image, backgroundColor: 0);
      final decoded = codec.decode(encoded.text);
      expect(decoded.width, 256);
      expect(decoded.height, 256);
      expect(decoded.pixels.first, 0);
    });

    test('reserved header bits fail', () {
      final payload = Uint8List.fromList([1, 0, 0, 0]);
      expect(
        () => codec.decode('im:${_base91(payload)}'),
        throwsA(isA<MCOImageInvalidPayloadException>()),
      );
    });

    test('old version 0 payloads still decode', () {
      final encoded = codec.decode(
        'im:${_base91(Uint8List.fromList([0, 0, 0, 0, 0]))}',
      );
      expect(encoded.width, 1);
      expect(encoded.height, 1);
      expect(encoded.pixels, [0]);
    });

    test('unknown newer version fails', () {
      final payload = Uint8List.fromList([0xc0, 0, 0, 0]);
      expect(
        () => codec.decode('im:${_base91(payload)}'),
        throwsA(isA<MCOImageInvalidPayloadException>()),
      );
    });

    test('invalid bounds fail', () {
      final payload = Uint8List.fromList([0x41, 0, 1, 1, 0, 1, 1, 2, 2]);
      expect(
        () => codec.decode('im:${_base91(payload)}'),
        throwsA(isA<MCOImageInvalidPayloadException>()),
      );
    });

    test('invalid regions fail', () {
      final outside = _monoRegionsPayload(2, 2, [
        1,
        ..._monoRawRegion(1, 1, 2, 1, const [1]),
      ]);
      expect(
        () => codec.decode('im:${_base91(outside)}'),
        throwsA(isA<MCOImageInvalidPayloadException>()),
      );

      final overlapping = _monoRegionsPayload(2, 2, [
        2,
        ..._monoRawRegion(0, 0, 1, 1, const [1]),
        ..._monoRawRegion(0, 0, 1, 1, const [1]),
      ]);
      expect(
        () => codec.decode('im:${_base91(overlapping)}'),
        throwsA(isA<MCOImageInvalidPayloadException>()),
      );

      final truncated = _monoRegionsPayload(2, 2, [
        1,
        ..._monoRawRegion(0, 0, 1, 1, const [1], payloadLength: 2),
      ]);
      expect(
        () => codec.decode('im:${_base91(truncated)}'),
        throwsA(isA<MCOImageInvalidPayloadException>()),
      );

      final wrongPixelCount = _monoRegionsPayload(2, 2, [
        1,
        ..._monoRawRegion(0, 0, 1, 1, const []),
      ]);
      expect(
        () => codec.decode('im:${_base91(wrongPixelCount)}'),
        throwsA(isA<MCOImageInvalidPayloadException>()),
      );

      final wrongRegionCount = _monoRegionsPayload(2, 2, const [0]);
      expect(
        () => codec.decode('im:${_base91(wrongRegionCount)}'),
        throwsA(isA<MCOImageInvalidPayloadException>()),
      );

      final tooManyRegions = _monoRegionsPayload(2, 2, const [9]);
      expect(
        () => codec.decode('im:${_base91(tooManyRegions)}'),
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

    test('dynamic color outside selected profile fails', () {
      expect(
        () => codec.encode(
          _image(2, 2, (_, _) => 511, profile: PaletteProfile.dynamicGlobal8),
        ),
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

const List<PaletteProfile> _fixedProfiles = [
  PaletteProfile.mono,
  PaletteProfile.master4,
  PaletteProfile.master8,
  PaletteProfile.grayscale8,
  PaletteProfile.master16,
  PaletteProfile.grayscale16,
  PaletteProfile.master32,
  PaletteProfile.grayscale32,
  PaletteProfile.master64,
];

const List<PaletteProfile> _dynamicProfiles = [
  PaletteProfile.dynamicGlobal8,
  PaletteProfile.dynamicGlobal16,
  PaletteProfile.dynamicGlobal32,
  PaletteProfile.dynamicGlobal64,
  PaletteProfile.dynamicGlobal128,
  PaletteProfile.dynamicGlobal256,
  PaletteProfile.dynamicGlobal512,
];

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

Uint8List _monoRegionsPayload(int width, int height, List<int> regionData) {
  return Uint8List.fromList([
    0x42,
    0x01,
    width - 1,
    height - 1,
    0,
    ...regionData,
  ]);
}

List<int> _monoRawRegion(
  int x,
  int y,
  int width,
  int height,
  List<int> payload, {
  int? payloadLength,
}) {
  return [
    x,
    y,
    width,
    height,
    0,
    0,
    payloadLength ?? payload.length,
    ...payload,
  ];
}

Uint8List _base91Decode(String text) {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
      '!#\$%&()*+,./:;<=>?@[]^_`{|}~"';
  final decodeTable = {
    for (var i = 0; i < alphabet.length; i++) alphabet.codeUnitAt(i): i,
  };
  final output = <int>[];
  var value = -1;
  var queue = 0;
  var bitCount = 0;
  for (final codeUnit in text.codeUnits) {
    final decoded = decodeTable[codeUnit];
    if (decoded == null) {
      throw StateError('Invalid basE91 character');
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
