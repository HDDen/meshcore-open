import 'dart:io';

import 'package:meshcore_open/helpers/mco_image_raster_rects.dart';

void main() {
  for (final entry in {
    'reported-white-256': List<int>.filled(256 * 256, 0),
    'checkerboard-256': List<int>.generate(256 * 256, (i) => (i + i ~/ 256) % 2),
    'striped-256': List<int>.generate(256 * 256, (i) => i % 256 ~/ 16),
  }.entries) {
    final timer = Stopwatch()..start();
    final rects = mcoImageRasterRects(entry.value, 256, 256);
    timer.stop();
    final restored = List<int?>.filled(entry.value.length, null);
    for (final rect in rects) {
      for (var y = rect.y; y < rect.y + rect.height; y++) {
        for (var x = rect.x; x < rect.x + rect.width; x++) {
          final i = y * 256 + x;
          if (restored[i] != null) throw StateError('Overlap');
          restored[i] = rect.color;
        }
      }
    }
    for (var i = 0; i < restored.length; i++) {
      if (restored[i] != entry.value[i]) throw StateError('Pixel mismatch');
    }
    stdout.writeln('${entry.key}: oldDraws=${entry.value.length}, newDraws=${rects.length}, '
        'planUs=${timer.elapsedMicroseconds}, exact=true');
  }
}
