import 'dart:io';

import 'package:mco_service/tcp_overlay.dart';

/// Keeps optional fork transports outside the ordinary TCP framing service.
Future<Socket> connectCompanionTcp({
  required String host,
  required int port,
  required Duration timeout,
}) async {
  final overlay = await openMcoTcpSocket(
    host: host,
    port: port,
    timeout: timeout,
  );
  if (overlay != null) {
    if (overlay is Socket) return overlay;
    throw StateError('The optional TCP transport returned an invalid socket');
  }
  return Socket.connect(host, port, timeout: timeout);
}
