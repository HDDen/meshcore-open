import 'dart:math' as math;

import 'package:flutter/painting.dart';

const _cacheLimit = 256;
final _accentCache = <(Color, Color, double), Color>{};

double _ratio(double a, double b) =>
    (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

/// Contrast ratio between opaque colors; composite translucent paint first.
double meshContrastRatio(Color a, Color b) =>
    _ratio(a.computeLuminance(), b.computeLuminance());

/// Keep an accent's hue while meeting contrast against an opaque card/tint.
/// Text uses 4.5 by default; status marks use 3. Preserve already readable
/// colors. Theme/palette pairs are cached so list redraws do not repeat HSL
/// searches; FIFO eviction bounds memory even with arbitrary custom colors.
Color readableAccent(Color accent, Color background, {double minContrast = 4.5}) {
  final key = (accent, background, minContrast);
  final cached = _accentCache[key];
  if (cached != null) return cached;
  final result = _correctAccent(accent, background, minContrast);
  if (_accentCache.length >= _cacheLimit) {
    _accentCache.remove(_accentCache.keys.first);
  }
  _accentCache[key] = result;
  return result;
}

Color _correctAccent(Color accent, Color background, double threshold) {
  final luminance = background.computeLuminance();
  double contrast(Color color) => _ratio(
    Color.alphaBlend(color, background).computeLuminance(), luminance,
  );
  if (contrast(accent) >= threshold) return accent;
  final darken = luminance > 0.18;
  final hsl = HSLColor.fromColor(accent);
  for (var step = 1; step <= 20; step++) {
    final lightness =
        (hsl.lightness + (darken ? -0.05 : 0.05) * step).clamp(0.0, 1.0);
    final candidate = hsl.withLightness(lightness).toColor();
    if (contrast(candidate) >= threshold) return candidate;
  }
  // A low-alpha accent may never reach the target. Use opaque paint then.
  return luminance > 0.18 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
}
