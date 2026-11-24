import '../connector/meshcore_connector.dart';
import '../storage/connection_transport_preference_store.dart';
import '../utils/app_logger.dart';
import '../utils/platform_info.dart';

/// Saved-radio startup stays on the scanner until an automatic connect succeeds.
/// Call once after the first frame; first-run TcpScreen autoconnect remains separate.
Future<bool> autoconnectSavedTcpRadio(
  MeshCoreConnector connector, {
  ConnectionTransportPreferenceStore? preferences,
  bool? isWeb,
}) async {
  final prefs = preferences ?? ConnectionTransportPreferenceStore();
  final radio = connector.lastRadio;
  if ((isWeb ?? PlatformInfo.isWeb) ||
      !connector.hasRadioData ||
      connector.isReviewMode ||
      connector.isLegacyOfflineSession ||
      connector.wasManuallyDisconnected ||
      connector.shouldSuppressAutoconnect(MeshCoreTransportType.tcp) ||
      connector.state != MeshCoreConnectionState.disconnected ||
      connector.isAutoReconnectScheduled ||
      !prefs.isAutoconnectEnabled(ConnectionTransportPreferenceStore.tcp) ||
      radio == null ||
      !radio.canReconnectTcp ||
      radio.tcpHost!.trim().isEmpty ||
      radio.tcpPort! < 1 ||
      radio.tcpPort! > 65535) {
    return false;
  }
  try {
    await connector.connectTcp(host: radio.tcpHost!, port: radio.tcpPort!, automaticReconnect: true);
    return connector.isConnected;
  } catch (error) {
    appLogger.warn(
      'Startup TCP autoconnect failed: ${error.runtimeType}',
      tag: 'TCP',
    );
    return false;
  }
}
