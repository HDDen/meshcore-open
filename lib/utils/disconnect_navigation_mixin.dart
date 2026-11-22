import 'package:flutter/material.dart';
import '../connector/meshcore_connector.dart';

/// Keep saved-radio screens available offline. Only a screen without readable
/// data or a recoverable/restarting connection returns to its first route.
mixin DisconnectNavigationMixin<T extends StatefulWidget> on State<T> {
  /// A recoverable BLE loss keeps the current route and its unsaved state alive
  /// while the connector reconnects in the background, and so does a transport
  /// restart: the connector tears the link down as a manual disconnect and
  /// brings it straight back, and a pop here would leave the user on the
  /// scanner with the radio connected.
  bool checkConnectionAndNavigate(MeshCoreConnector connector) {
    if (!connector.hasRadioData && !connector.hasReadableSession &&
        !connector.isRecoveringConnection &&
        !connector.isRestartingTransport) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !connector.hasRadioData &&
            !connector.hasReadableSession && !connector.isRecoveringConnection &&
            !connector.isRestartingTransport) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      });
      return false;
    }
    return true;
  }
}
