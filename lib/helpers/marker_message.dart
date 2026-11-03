import 'package:latlong2/latlong.dart';

class MarkerPayload {
  final LatLng position;
  final String label;
  final String flags;

  MarkerPayload({
    required this.position,
    required this.label,
    required this.flags,
  });
}

// Reuse the existing grammar for map, chat and notification summaries.
// Keep the unanchored match: older messages can include a sender prefix.
final _markerPattern = RegExp(r'm:([\-0-9.]+),([\-0-9.]+)\|([^|]*)\|(.*)');

/// Parse a shared marker text message of the form
/// `m:<lat>,<lon>|<label>|<flags>` and return a [MarkerPayload].
MarkerPayload? parseMarkerText(String text) {
  final trimmed = text.trim();
  // Ordinary notifications need no regular-expression match or allocations.
  if (!trimmed.contains('m:')) return null;
  final match = _markerPattern.firstMatch(trimmed);
  if (match == null) return null;
  final lat = double.tryParse(match.group(1) ?? '');
  final lon = double.tryParse(match.group(2) ?? '');
  if (lat == null || lon == null) return null;
  if (lat.abs() > 90 || lon.abs() > 180) return null;
  final label = (match.group(3) ?? '').trim();
  final flags = (match.group(4) ?? '').trim();
  return MarkerPayload(position: LatLng(lat, lon), label: label, flags: flags);
}
