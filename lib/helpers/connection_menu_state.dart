import '../connector/meshcore_connector.dart';

/// A pending or recovering link can be cancelled even without an open socket.
bool connectionMenuShowsDisconnect(MeshCoreConnector connector) =>
    connector.isConnected ||
    connector.state == MeshCoreConnectionState.connecting ||
    connector.state == MeshCoreConnectionState.disconnecting ||
    connector.isRecoveringConnection ||
    connector.isAutoReconnectScheduled ||
    connector.isRestartingTransport;
