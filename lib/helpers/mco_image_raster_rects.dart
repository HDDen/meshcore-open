/// Pixel-exact non-overlapping rectangles for raster painting, independent of
/// the wire codec. Equal horizontal runs on adjacent rows share one rectangle.
typedef McoRasterRect = ({int x, int y, int width, int height, int color});

List<McoRasterRect> mcoImageRasterRects(
  List<int> pixels,
  int width,
  int height, {
  int? transparentColor,
}) {
  if (width <= 0 || height <= 0 || pixels.length != width * height) {
    throw ArgumentError('Invalid raster dimensions');
  }
  final result = <McoRasterRect>[];
  var previous = <(int, int, int), int>{};
  for (var y = 0; y < height; y++) {
    final current = <(int, int, int), int>{};
    var x = 0;
    while (x < width) {
      final start = x;
      final color = pixels[y * width + x++];
      while (x < width && pixels[y * width + x] == color) {
        x++;
      }
      if (color == transparentColor) {
        continue;
      }
      final key = (start, x - start, color);
      final old = previous[key];
      if (old == null) {
        current[key] = result.length;
        result.add((x: start, y: y, width: x - start, height: 1, color: color));
      } else {
        current[key] = old;
        final rect = result[old];
        result[old] = (
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height + 1,
          color: color,
        );
      }
    }
    previous = current;
  }
  return result;
}
