import 'package:flutter/material.dart';
import '../connector/meshcore_connector.dart';

/// Mixin that returns to the scanner when the connection cannot recover in
/// place (for example, after a manual disconnect or an unexpected USB/TCP
/// disconnect).
/// Use in State classes for screens that require active connection.
mixin DisconnectNavigationMixin<T extends StatefulWidget> on State<T> {
  /// A recoverable BLE loss keeps the current route and its unsaved state alive
  /// while the connector reconnects in the background.
  bool checkConnectionAndNavigate(MeshCoreConnector connector) {
    if (!connector.isConnected && !connector.isRecoveringConnection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      });
      return false;
    }
    return true;
  }
}
