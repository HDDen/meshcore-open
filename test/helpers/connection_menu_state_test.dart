import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/connection_menu_state.dart';

class _Connection extends Fake implements MeshCoreConnector {
  _Connection({
    this.state = MeshCoreConnectionState.disconnected,
    this.isRecoveringConnection = false,
    this.isAutoReconnectScheduled = false,
    this.isRestartingTransport = false,
  });
  @override
  final MeshCoreConnectionState state;
  @override
  bool get isConnected => state == MeshCoreConnectionState.connected;
  @override
  final bool isRecoveringConnection;
  @override
  final bool isAutoReconnectScheduled;
  @override
  final bool isRestartingTransport;
}

void main() {
  for (final state in [
    MeshCoreConnectionState.connecting,
    MeshCoreConnectionState.connected,
    MeshCoreConnectionState.disconnecting,
  ]) {
    test('$state offers Disconnect', () {
      expect(connectionMenuShowsDisconnect(_Connection(state: state)), isTrue);
    });
  }
  test('recovery, scheduled retry and restart offer Disconnect without a socket', () {
    expect(connectionMenuShowsDisconnect(_Connection(isRecoveringConnection: true)), isTrue);
    expect(connectionMenuShowsDisconnect(_Connection(isAutoReconnectScheduled: true)), isTrue);
    expect(connectionMenuShowsDisconnect(_Connection(isRestartingTransport: true)), isTrue);
  });
  test('idle offline and scanning offer Connect', () {
    expect(connectionMenuShowsDisconnect(_Connection()), isFalse);
    expect(connectionMenuShowsDisconnect(_Connection(state: MeshCoreConnectionState.scanning)), isFalse);
  });
}
