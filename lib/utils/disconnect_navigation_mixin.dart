import 'package:flutter/material.dart';
import '../connector/meshcore_connector.dart';

/// Mixin that automatically navigates back to scanner when disconnected.
/// Use in State classes for screens that require active connection.
mixin DisconnectNavigationMixin<T extends StatefulWidget> on State<T> {
  /// Call this in your Widget build method to enable auto-navigation.
  /// Returns true if still connected, false if navigation was triggered.
  bool checkConnectionAndNavigate(MeshCoreConnector connector) {
    if (!connector.isConnected) {
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
