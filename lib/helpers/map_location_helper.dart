import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import '../connector/meshcore_connector.dart';
import '../services/wardrive_service.dart';

class MapLocationHelper {
  const MapLocationHelper._();

  static Future<LatLng?> resolveForScreen(
    BuildContext context, {
    required bool enabled,
    required WardriveService wardrive,
    required MeshCoreConnector connector,
    void Function(LatLng position)? onPhoneLocation,
  }) async {
    if (!enabled) return null;

    final scheduler = SchedulerBinding.instance;
    // Wardrive notifies listeners synchronously when the request starts.
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      await scheduler.endOfFrame;
      if (!context.mounted) return null;
    }

    return resolve(
      enabled: true,
      wardrive: wardrive,
      connector: connector,
      onPhoneLocation: onPhoneLocation,
    );
  }

  /// Resolves display coordinates only; it never writes them to the node.
  static Future<LatLng?> resolve({
    required bool enabled,
    required WardriveService wardrive,
    required MeshCoreConnector connector,
    void Function(LatLng position)? onPhoneLocation,
  }) async {
    if (!enabled) return null;

    final phoneLocation = await wardrive.requestPhoneLocation();
    if (phoneLocation != null) {
      final position = LatLng(phoneLocation.latitude, phoneLocation.longitude);
      // Let path maps cache only a phone fix, never a stale node fallback.
      onPhoneLocation?.call(position);
      return position;
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
