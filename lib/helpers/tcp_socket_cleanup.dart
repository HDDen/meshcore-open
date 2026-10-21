import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'connection_cleanup.dart';

/// A stream adapter can await socket data while its subscription is cancelled.
/// Start closing concurrently, then force-destroy this captured socket on exit.
Future<void> closeTcpSocket({
  Socket? socket,
  StreamSubscription<Uint8List>? subscription,
  Duration timeout = ConnectionCleanup.defaultTimeout,
  void Function(String stage, Object error, StackTrace stack)? onFailure,
}) async {
  void destroy() {
    try {
      socket?.destroy();
    } catch (error, stack) {
      onFailure?.call('TCP destroy', error, stack);
    }
  }

  try {
    await ConnectionCleanup(timeout: timeout, onFailure: onFailure).run(
      'TCP socket close/cancel',
      () async {
        await Future.wait<void>([
          Future<void>.sync(() async { await subscription?.cancel(); }),
          Future<void>.sync(() async {
            try {
              await socket?.close();
            } finally {
              destroy();
            }
          }),
        ], eagerError: true);
      },
    );
  } finally {
    // Also runs when close/flush or cancellation never completes. The pending
    // futures only retain this old socket and cannot close a later connection.
    destroy();
  }
}
