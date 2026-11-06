import '../models/contact.dart';

/// Finds the first usable GPS pair without changing the Cayenne wire parser.
/// Zero/zero is the firmware's missing-fix sentinel; either axis alone may
/// legitimately be zero. NaN, infinity and out-of-range values are rejected.
({double latitude, double longitude})? telemetryGpsFix(
  List<Map<String, dynamic>> entries,
) {
  for (final entry in entries) {
    final values = entry['values'];
    if (values is! Map) {
      continue;
    }
    final gps = values['gps'];
    if (gps is! Map) {
      continue;
    }
    final lat = gps['latitude'];
    final lon = gps['longitude'];
    if (lat is! num || lon is! num) {
      continue;
    }
    final latitude = lat.toDouble();
    final longitude = lon.toDouble();
    if (validTelemetryLocation(latitude, longitude)) {
      return (latitude: latitude, longitude: longitude);
    }
  }
  return null;
}

bool validTelemetryLocation(double latitude, double longitude) =>
    latitude.isFinite &&
    longitude.isFinite &&
    (latitude.abs() > 1e-6 || longitude.abs() > 1e-6) &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180;

/// A fix supersedes one advert, not all future adverts. Compare adverts on
/// their own clock; comparing the node clock with phone receive time could
/// pin an old fix forever. An incoming newer telemetry fix wins as well.
Contact retainContactTelemetryFix(Contact previous, Contact incoming) {
  final fixAt = previous.telemetryFixAt;
  if (previous.publicKeyHex != incoming.publicKeyHex ||
      fixAt == null ||
      !previous.hasLocation ||
      incoming.lastSeen.isAfter(previous.lastSeen) ||
      (incoming.telemetryFixAt != null &&
          !fixAt.isAfter(incoming.telemetryFixAt!))) {
    return incoming;
  }
  return incoming.copyWith(
    latitude: previous.latitude,
    longitude: previous.longitude,
    telemetryFixAt: fixAt,
    // A delayed copy of an older advert must not move the fix's anchor back.
    lastSeen: previous.lastSeen,
  );
}
