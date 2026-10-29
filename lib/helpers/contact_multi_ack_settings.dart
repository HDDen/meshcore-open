import '../connector/meshcore_connector.dart';

/// Multi ACK shares a firmware command with privacy settings. Read the other
/// values at save time so this dialog cannot overwrite newer privacy choices.
Future<void> saveContactMultiAcks(
  MeshCoreConnector connector, {
  required int initialValue,
  required int selectedValue,
}) async {
  if (selectedValue == initialValue) return;
  await connector.setTelemetryModeBase(
    connector.telemetryModeBase,
    connector.telemetryModeLoc,
    connector.telemetryModeEnv,
    connector.advertLocationPolicy,
    selectedValue,
  );
  await connector.refreshDeviceInfo();
}
