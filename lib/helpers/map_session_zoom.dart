abstract final class MapSessionZoom {
  static double? _value;

  static double? get value => _value;

  static double resolve(
    double fallback, {
    required double minZoom,
    required double maxZoom,
  }) {
    return (_value ?? fallback).clamp(minZoom, maxZoom).toDouble();
  }

  static void remember(double zoom) {
    if (zoom.isFinite) _value = zoom;
  }
}
