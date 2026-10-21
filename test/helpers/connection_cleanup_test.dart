import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/connection_cleanup.dart';
import 'package:meshcore_open/helpers/tcp_socket_cleanup.dart';

void main() {
  test('a stuck cleanup step times out and consumes its late failure', () async {
    final pending = Completer<void>();
    final failures = <Object>[];
    final cleanup = ConnectionCleanup(
      timeout: const Duration(milliseconds: 20),
      onFailure: (stage, error, stack) => failures.add(error),
    );
    await cleanup.run('stalled', () => pending.future)
        .timeout(const Duration(seconds: 2));
    expect(failures.single, isA<TimeoutException>());
    pending.completeError(StateError('late old cleanup error'));
    var continued = false;
    await cleanup.run('next', () async { continued = true; });
    expect(continued, isTrue);
    expect(failures, hasLength(1));
  });

  test('cleanup handles synchronous errors and absent resources', () async {
    final stages = <String>[];
    final cleanup = ConnectionCleanup(
      onFailure: (stage, error, stack) => stages.add(stage),
    );
    await cleanup.run('failed', () => throw StateError('fixture'));
    await cleanup.run('empty', () => null);
    expect(stages, ['failed']);
  });

  test('TCP closes the socket while stream cancellation waits for that close', () async {
    final closed = Completer<void>();
    var cancelling = false;
    final stream = StreamController<Uint8List>(onCancel: () {
      cancelling = true;
      return closed.future;
    });
    final subscription = stream.stream.listen((_) {});
    final socket = _ClosingSocket(onClose: () => closed.complete());
    try {
      await closeTcpSocket(socket: socket, subscription: subscription)
          .timeout(const Duration(seconds: 2));
      expect(cancelling, isTrue);
      expect(socket.destroyCalls, greaterThan(0));
    } finally {
      if (!closed.isCompleted) {
        closed.complete();
      }
      await subscription.cancel();
      await stream.close();
    }
  });

  test('TCP timeout forces destruction and drains a late close failure', () async {
    final stuck = Completer<void>();
    final oldSocket = _ClosingSocket(pending: stuck.future);
    final failures = <Object>[];
    await closeTcpSocket(
      socket: oldSocket, timeout: const Duration(milliseconds: 20),
      onFailure: (stage, error, stack) => failures.add(error),
    ).timeout(const Duration(seconds: 2));
    expect(failures.single, isA<TimeoutException>());
    expect(oldSocket.destroyCalls, greaterThan(0));
    stuck.completeError(StateError('old close failed late'));
    await Future<void>.delayed(Duration.zero);
    expect(failures, hasLength(1));
  });
}

class _ClosingSocket extends Fake implements Socket {
  _ClosingSocket({this.onClose, this.pending});
  final void Function()? onClose;
  final Future<void>? pending;
  int destroyCalls = 0;
  @override
  Future<void> close() {
    onClose?.call();
    return pending ?? Future<void>.value();
  }
  @override
  void destroy() { destroyCalls++; }
}
