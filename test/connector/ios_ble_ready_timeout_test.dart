import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('mco_service/ios_ble_central');
  const events = MethodChannel('mco_service/ios_ble_central/events');
  const device = '00000000-0000-0000-0000-000000000001';
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // MethodChannel replies use real async execution, as in disconnect_cleanup_test.
  // A separate guard fails with StateError, never masquerading as the tested timeout.
  Future<T> bounded<T>(Future<T> operation, String stage) => operation.timeout(
    const Duration(seconds: 3),
    onTimeout: () => throw StateError('iOS BLE test did not finish: $stage'),
  );

  test('native iOS BLE readiness timeout cancels the attempt and permits a new connection', () async {
    final node = MeshCoreConnector();
    final pending = Completer<void>();
    final dispatched = Completer<void>();
    var connects = 0;
    var disconnects = 0;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'connect') {
        connects++;
        if (connects == 1) {
          dispatched.complete();
          await pending.future;
        }
      } else if (call.method == 'disconnect') {
        disconnects++;
      }
      return null;
    });
    try {
      final first = node.connectIosNativeBleForTest(
        device, readinessTimeout: const Duration(milliseconds: 50),
      );
      final checked = expectLater(
        bounded(first, 'readiness timeout and native cleanup'),
        throwsA(isA<TimeoutException>()),
      );
      await bounded(dispatched.future, 'first connect dispatch');
      await checked;
      expect(disconnects, 1);

      await bounded(node.connectIosNativeBleForTest(
        device, readinessTimeout: const Duration(milliseconds: 50),
      ), 'replacement connection');
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      expect(connects, 2);
      expect(disconnects, 1);
    } finally {
      if (!pending.isCompleted) pending.complete();
      node.dispose();
      await Future<void>.delayed(Duration.zero);
      messenger.setMockMethodCallHandler(native, null);
      messenger.setMockMethodCallHandler(events, null);
    }
  });
}
