import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcoimg_codec.dart';
import 'package:meshcore_open/helpers/mcoimg_palette.dart';

const _dynamicProfiles = [
  PaletteProfile.dynamicGlobal8,
  PaletteProfile.dynamicGlobal16,
  PaletteProfile.dynamicGlobal32,
  PaletteProfile.dynamicGlobal64,
  PaletteProfile.dynamicGlobal128,
  PaletteProfile.dynamicGlobal256,
  PaletteProfile.dynamicGlobal512,
];

void main() {
  final codec = MCOImageCodec();

  group('MCOImageCodec dynamic optimization matrix', () {
    for (final profile in _dynamicProfiles) {
      test('${profile.name} optimized candidates roundtrip', () {
        final profileColors = MCOImageDynamicPalette.indicesFor(profile);
        final usedColorCount = profileColors.length.clamp(2, 32).toInt();
        final selected = profileColors.take(usedColorCount).toList();
        final image = _image(
          8,
          8,
          (x, y) => selected[(x * 3 + y * 5) % selected.length],
          profile,
        );
        final diagnostics = codec.debugEncode(
          image,
          backgroundColor: selected.first,
        );

        expect(codec.decode(diagnostics.result.text).pixels, image.pixels);
        final encodings = diagnostics.candidates
            .map((candidate) => candidate.dynamicReferenceEncoding)
            .whereType<DynamicPaletteReferenceEncoding>()
            .toSet();
        expect(
          encodings,
          containsAll(<DynamicPaletteReferenceEncoding>{
            DynamicPaletteReferenceEncoding.flat,
            DynamicPaletteReferenceEncoding.sortedDelta,
            DynamicPaletteReferenceEncoding.rangeRuns,
            DynamicPaletteReferenceEncoding.profileBitmap,
            if (profile == PaletteProfile.dynamicGlobal512)
              DynamicPaletteReferenceEncoding.banked8x64,
            if (profile == PaletteProfile.dynamicGlobal512)
              DynamicPaletteReferenceEncoding.bankBitmaps,
          }),
        );

        final representatives =
            <DynamicPaletteReferenceEncoding, EncodedMCOImage>{};
        for (final candidate in diagnostics.candidates) {
          final encoding = candidate.dynamicReferenceEncoding;
          if (encoding != null) {
            representatives.putIfAbsent(encoding, () => candidate);
          }
        }
        for (final candidate in representatives.values) {
          expect(codec.decode(candidate.text).pixels, image.pixels);
        }
      });
    }
  });

  test('dynamic optimization size report', () {
    final cases = _benchmarkCases();
    final report = StringBuffer(
      '\nMCOimg dynamic optimization report\n'
      'case | text chars | binary bytes | selected candidate\n',
    );

    for (final benchmark in cases) {
      final diagnostics = codec.debugEncode(
        benchmark.image,
        backgroundColor: benchmark.backgroundColor,
      );
      final baseline = diagnostics.candidates.where(_isBaselineCandidate);
      expect(baseline, isNotEmpty, reason: benchmark.name);

      final baselineText = _shortestBy(
        baseline,
        (candidate) => candidate.charLength,
      );
      final baselineBinary = _shortestBy(
        baseline,
        (candidate) => candidate.byteLength,
      );
      final bestText = _shortestBy(
        diagnostics.candidates,
        (candidate) => candidate.charLength,
      );
      final bestBinary = _shortestBy(
        diagnostics.candidates,
        (candidate) => candidate.byteLength,
      );

      expect(
        bestText.charLength,
        lessThanOrEqualTo(baselineText.charLength),
        reason: '${benchmark.name} text',
      );
      expect(
        bestBinary.byteLength,
        lessThanOrEqualTo(baselineBinary.byteLength),
        reason: '${benchmark.name} binary',
      );
      expect(codec.decode(bestText.text).pixels, benchmark.image.pixels);
      expect(codec.decode(bestBinary.text).pixels, benchmark.image.pixels);

      report.writeln(
        '${benchmark.name} | '
        '${baselineText.charLength} -> ${bestText.charLength} '
        '(-${baselineText.charLength - bestText.charLength}) | '
        '${baselineBinary.byteLength} -> ${bestBinary.byteLength} '
        '(-${baselineBinary.byteLength - bestBinary.byteLength}) | '
        '${bestText.container}, '
        '${bestText.dynamicReferenceEncoding?.name ?? 'fixed'}',
      );
    }

    debugPrint(report.toString());
  });
}

List<_BenchmarkCase> _benchmarkCases() {
  final dynamic8 = MCOImageDynamicPalette.indicesFor(
    PaletteProfile.dynamicGlobal8,
  );
  final dynamic128 = MCOImageDynamicPalette.indicesFor(
    PaletteProfile.dynamicGlobal128,
  );
  final white128 = MCOImageDynamicPalette.whiteGlobalIndexFor(
    PaletteProfile.dynamicGlobal128,
  );
  final contiguous128 = dynamic128.sublist(64, 80);
  final scattered128 = List<int>.generate(
    64,
    (index) => dynamic128[index * 2],
  );
  final denseBank512 = List<int>.generate(32, (index) => 64 + index);

  return [
    _BenchmarkCase(
      'dynamic8-all',
      _image(
        20,
        20,
        (x, y) => dynamic8[(x + y * 3) % dynamic8.length],
        PaletteProfile.dynamicGlobal8,
      ),
      dynamic8.first,
    ),
    _BenchmarkCase(
      'dynamic128-contiguous16',
      _image(
        24,
        24,
        (x, y) => contiguous128[(x * 3 + y) % contiguous128.length],
        PaletteProfile.dynamicGlobal128,
      ),
      contiguous128.first,
    ),
    _BenchmarkCase(
      'dynamic128-scattered64',
      _image(
        24,
        24,
        (x, y) => scattered128[(x * 7 + y * 5) % scattered128.length],
        PaletteProfile.dynamicGlobal128,
      ),
      scattered128.first,
    ),
    _BenchmarkCase(
      'dynamic512-dense-bank32',
      _image(
        24,
        24,
        (x, y) => denseBank512[(x + y * 3) % denseBank512.length],
        PaletteProfile.dynamicGlobal512,
      ),
      denseBank512.first,
    ),
    _BenchmarkCase(
      'dynamic128-white-bounds',
      _image(
        24,
        24,
        (x, y) {
          if (x < 7 || x > 16 || y < 7 || y > 16) return white128;
          return contiguous128[(x + y) % contiguous128.length];
        },
        PaletteProfile.dynamicGlobal128,
      ),
      white128,
    ),
  ];
}

bool _isBaselineCandidate(EncodedMCOImage candidate) {
  final reference = candidate.dynamicReferenceEncoding;
  return (reference == DynamicPaletteReferenceEncoding.flat ||
          reference == DynamicPaletteReferenceEncoding.banked8x64) &&
      !candidate.container.startsWith('direct-dynamic') &&
      !candidate.container.contains('palette-optimized');
}

EncodedMCOImage _shortestBy(
  Iterable<EncodedMCOImage> candidates,
  int Function(EncodedMCOImage candidate) lengthOf,
) {
  return candidates.reduce(
    (best, candidate) =>
        lengthOf(candidate) < lengthOf(best) ? candidate : best,
  );
}

MCOImage _image(
  int width,
  int height,
  int Function(int x, int y) pixel,
  PaletteProfile profile,
) {
  return MCOImage(
    width: width,
    height: height,
    paletteProfile: profile,
    pixels: [
      for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++) pixel(x, y),
    ],
  );
}

class _BenchmarkCase {
  final String name;
  final MCOImage image;
  final int backgroundColor;

  const _BenchmarkCase(this.name, this.image, this.backgroundColor);
}
