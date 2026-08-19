/// A run of message text: either plain, or a `lat,lon` pair that should be
/// tappable and open the map.
class CoordinateSegment {
  final String text;
  final double? latitude;
  final double? longitude;

  const CoordinateSegment(this.text, {this.latitude, this.longitude});

  bool get isCoordinate => latitude != null && longitude != null;
}

/// Finds `lat,lon` pairs written inside ordinary message text, so
/// "I'm at 45.0,38.9, see you" links to the map the way a bare coordinate
/// message already does.
class CoordinateText {
  CoordinateText._();

  /// Both halves must carry a decimal point, or "1,5" written as a price and
  /// "steps 1,2" would read as coordinates. The pair may not continue into a
  /// longer number on either side, which keeps version strings out — but a
  /// sentence-ending dot right after it is fine.
  static final RegExp pattern = RegExp(
    r'(?<![\w.])([+-]?\d{1,3}\.\d+)\s*,\s*([+-]?\d{1,3}\.\d+)(?!\d)(?!\.\d)',
  );

  /// Cheap pre-check before the full scan: a pair needs both a dot and a
  /// comma, and most messages carry neither.
  static bool has(String text) {
    if (!text.contains(',') || !text.contains('.')) return false;
    for (final match in pattern.allMatches(text)) {
      if (_parse(match) != null) return true;
    }
    return false;
  }

  /// Splits [text] into alternating plain and coordinate runs, in order.
  static List<CoordinateSegment> split(String text) {
    final segments = <CoordinateSegment>[];
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      final parsed = _parse(match);
      if (parsed == null) continue;
      if (match.start > cursor) {
        segments.add(CoordinateSegment(text.substring(cursor, match.start)));
      }
      segments.add(
        CoordinateSegment(
          text.substring(match.start, match.end),
          latitude: parsed.$1,
          longitude: parsed.$2,
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      segments.add(CoordinateSegment(text.substring(cursor)));
    }
    return segments;
  }

  static (double, double)? _parse(RegExpMatch match) {
    final latitude = double.tryParse(match.group(1) ?? '');
    final longitude = double.tryParse(match.group(2) ?? '');
    if (latitude == null || longitude == null) return null;
    if (latitude < -90.0 || latitude > 90.0) return null;
    if (longitude < -180.0 || longitude > 180.0) return null;
    return (latitude, longitude);
  }
}
