import 'dart:async';
import 'dart:typed_data';

import '../helpers/connection_cleanup.dart';
import '../services/app_debug_log_service.dart';
import '../services/tcp_transport_service.dart';

/// Manages TCP transport for MeshCore devices.
///
/// Owns the [TcpTransportService] and TCP-specific connection state.
/// The main [MeshCoreConnector] delegates all TCP operations here.
class MeshCoreTcpConnector {
  final TcpTransportService _service = TcpTransportService();
  AppDebugLogService? _debugLog;
  StreamSubscription<Uint8List>? _frameSubscription;

  // --- Getters ---
  String? get activeEndpoint => _service.activeEndpoint;
  Object? get activeConnectionIdentity => _service.activeConnectionIdentity;
  bool get isConnected => _service.isConnected;

  // --- Configuration ---
  void setDebugLogService(AppDebugLogService? service) {
    _debugLog = service;
    _service.setDebugLogService(service);
  }

  // --- Connection lifecycle ---
  Future<void> connect({required String host, required int port}) async {
    _debugLog?.info('TcpConnector.connect endpoint=$host:$port', tag: 'TCP');
    await cancelFrameSubscription();
    await _service.connect(host: host, port: port);
    _debugLog?.info(
      'TcpConnector.connect done, endpoint=${_service.activeEndpoint}',
      tag: 'TCP',
    );
  }

  StreamSubscription<Uint8List> listenFrames({
    required void Function(Uint8List) onFrame,
    required void Function(Object, StackTrace?) onError,
    required void Function() onDone,
  }) {
    _frameSubscription = _service.frameStream.listen(
      onFrame,
      onError: onError,
      onDone: onDone,
    );
    return _frameSubscription!;
  }

  Future<void> cancelFrameSubscription() async {
    final subscription = _frameSubscription;
    _frameSubscription = null;
    await ConnectionCleanup(onFailure: _logCleanupFailure).run(
      'TCP frame subscription', () => subscription?.cancel(),
    );
  }

  Future<void> disconnect() async {
    _debugLog?.info('TcpConnector.disconnect', tag: 'TCP');
    // Start native socket shutdown before waiting for subscriptions to drain.
    await Future.wait<void>([_service.disconnect(), cancelFrameSubscription()]);
  }

  void _logCleanupFailure(String stage, Object error, StackTrace stack) {
    _debugLog?.warn('Disconnect cleanup stage=$stage failed: $error', tag: 'TCP');
  }

  Future<void> write(Uint8List data) => _service.write(data);

  void dispose() {
    _frameSubscription?.cancel();
    _service.dispose();
  }
}
