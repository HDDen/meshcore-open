import 'package:latlong2/latlong.dart';

import '../connector/meshcore_connector.dart';
import '../services/wardrive_service.dart';

class MapLocationHelper {
  const MapLocationHelper._();

  /// Resolves display coordinates only; it never writes them to the node.
  static Future<LatLng?> resolve({
    required bool enabled,
    required WardriveService wardrive,
    required MeshCoreConnector connector,
  }) async {
    if (!enabled) return null;

    final phoneLocation = await wardrive.requestPhoneLocation();
    if (phoneLocation != null) {
      return LatLng(phoneLocation.latitude, phoneLocation.longitude);
    }

    final nodeLocation = await connector.refreshSelfLocation();
    if (nodeLocation == null) return null;
    return LatLng(nodeLocation.latitude, nodeLocation.longitude);
  }

  static LatLng? nodeLocation(MeshCoreConnector connector) {
    final latitude = connector.selfLatitude;
    final longitude = connector.selfLongitude;
    if (latitude == null || longitude == null) return null;
    return LatLng(latitude, longitude);
  }
}
