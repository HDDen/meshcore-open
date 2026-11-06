import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/readable_accent.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';

void main() {
  test('accent correction reaches text/icon contrast on standard surfaces', () {
    for (final background in [MeshPalette.lightBg1, MeshPalette.bg1,
      Colors.white, Colors.black]) {
      for (final accent in [MeshPalette.warn, MeshPalette.blue,
        MeshPalette.magenta, MeshPalette.signal, Colors.grey]) {
        for (final threshold in [3.0, 4.5]) {
          final result = readableAccent(accent, background,
              minContrast: threshold);
          expect(meshContrastRatio(Color.alphaBlend(result, background),
              background), greaterThanOrEqualTo(threshold));
        }
      }
    }
  });

  test('an already readable accent keeps its original color', () {
    expect(readableAccent(Colors.black, Colors.white), Colors.black);
    expect(readableAccent(Colors.white, Colors.black), Colors.white);
  });

  test('translucent accents are checked as painted, with an opaque fallback', () {
    final result = readableAccent(Colors.amber.withValues(alpha: 0.2),
        Colors.white);
    expect(meshContrastRatio(Color.alphaBlend(result, Colors.white),
        Colors.white), greaterThanOrEqualTo(4.5));
  });

  test('contrast ratio is symmetric and has the opaque black/white limits', () {
    expect(meshContrastRatio(Colors.white, Colors.black), 21);
    expect(meshContrastRatio(Colors.black, Colors.white), 21);
    expect(meshContrastRatio(Colors.grey, Colors.grey), 1);
  });

  test('warm pairs reuse their Color and old palette entries are evicted', () {
    final first = readableAccent(Colors.amber, Colors.white);
    expect(identical(first, readableAccent(Colors.amber, Colors.white)), isTrue);
    expect(identical(first, Colors.amber), isFalse);
    // A bounded cache cannot retain every color from a large dynamic palette.
    for (var i = 0; i < 300; i++) {
      readableAccent(Color(0xFF010000 | i), Colors.white);
    }
    final again = readableAccent(Colors.amber, Colors.white);
    expect(again, first);
    expect(identical(again, first), isFalse);
  });
}
