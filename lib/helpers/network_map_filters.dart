import '../connector/meshcore_protocol.dart';
import '../models/app_settings.dart';
import '../services/network_map/network_map_api_client.dart';

/// Applies the map's visibility settings to a fetched online snapshot.
List<NetworkMapRepeater> filterNetworkMapRepeaters(
  List<NetworkMapRepeater> repeaters, {
  required AppSettings settings,
  required DateTime now,
  Set<NetworkMapRepeaterStatus>? statuses,
}) {
  final keyPrefix = settings.mapKeyPrefixEnabled
      ? settings.mapKeyPrefix.trim().toLowerCase()
      : '';
  return repeaters.where((repeater) {
    final typeVisible = switch (repeater.type) {
      advTypeRepeater => settings.mapShowRepeaters,
      advTypeChat => settings.mapShowChatNodes,
      _ => settings.mapShowOtherNodes,
    };
    if (!typeVisible) return false;
    if (repeater.isEstimated && !settings.mapShowGuessedLocations) return false;
    if (statuses != null && !statuses.contains(repeater.status)) return false;

    final lastSeen = repeater.lastSeen;
    if (lastSeen != null &&
        settings.mapTimeFilterHours > 0 &&
        now.difference(lastSeen).inHours > settings.mapTimeFilterHours) {
      return false;
    }
    return keyPrefix.isEmpty ||
        repeater.key.toLowerCase().startsWith(keyPrefix);
  }).toList();
}
