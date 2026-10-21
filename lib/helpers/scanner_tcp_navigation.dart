import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../screens/tcp_screen.dart';

/// Stop BLE discovery before switching away from the scanner to TCP.
Future<void> openTcpFromScanner(
  BuildContext context,
  MeshCoreConnector connector, {
  Future<void>? scanStartup,
}) async {
  final scannerRoute = ModalRoute.of(context);
  // startScan can still be waiting for the adapter before native discovery
  // starts. Join that setup so it cannot restart discovery after our stop.
  await scanStartup;
  if (!context.mounted || (scannerRoute != null && !scannerRoute.isCurrent)) {
    return;
  }
  await connector.stopScan();
  // A delayed stop must not open TCP after leaving the scanner, or push a
  // second TCP route when several taps waited for the same scan to stop.
  if (!context.mounted || (scannerRoute != null && !scannerRoute.isCurrent)) {
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const TcpScreen()),
  );
}
