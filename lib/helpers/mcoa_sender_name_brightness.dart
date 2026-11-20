import 'package:flutter/painting.dart';

/// Neutral at zero; darken toward black or lighten toward white while
/// retaining the original hue, saturation and alpha.
Color adjustSenderNameBrightness(Color color, int brightness) {
  final amount = brightness.clamp(-100, 100) / 100;
  if (amount == 0) {
    return color;
  }
  final hsl = HSLColor.fromColor(color);
  final lightness = amount < 0
      ? hsl.lightness * (1 + amount)
      : hsl.lightness + (1 - hsl.lightness) * amount;
  return hsl.withLightness(lightness.clamp(0.0, 1.0).toDouble())
      .toColor().withValues(alpha: color.a);
}
