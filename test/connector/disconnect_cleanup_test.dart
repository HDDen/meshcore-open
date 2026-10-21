import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/services/app_debug_log_service.dart';
import 'package:meshcore_open/services/image_codec_service.dart';
import 'package:meshcore_open/services/translation_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Duration(milliseconds: 20);
  const nativeBle = MethodChannel('mco_service/ios_ble_central');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MeshCoreConnector connector;
  late AppDebugLogService log;

  setUp(() async {
    PrefsManager.reset();
    SharedPreferences.setMockInitialValues({});
    await PrefsManager.initialize();
    connector = MeshCoreConnector();
    log = AppDebugLogService()..setEnabled(true);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(nativeBle, null);
    connector.dispose();
    // The ordinary connector still debounces its final UI notification.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    log.dispose();
  });

  test('model timeouts do not strand disconnecting or block the next teardown', () async {
    final oldTranslation = Completer<void>();
    final oldImage = Completer<void>();
    final image = _Image(oldImage.future);
    connector.attachDisconnectServicesForTest(
      translationService: _Translation(oldTranslation.future),
      imageCodecService: image, debugLog: log, timeout: timeout,
    );
    final first = connector.disconnect(manual: true);
    expect(connector.state, MeshCoreConnectionState.disconnecting);
    // A second click joins the same teardown instead of resetting the deadline.
    final joined = connector.disconnect(manual: true);
    await Future.wait([first, joined]).timeout(const Duration(seconds: 2));
    expect(image.cancelled, isTrue);
    expect(connector.state, MeshCoreConnectionState.disconnected);
    expect(connector.wasManuallyDisconnected, isTrue);
    expect(connector.isAutoReconnectScheduled, isFalse);
    final messages = log.entries.map((entry) => entry.message).join('\n');
    expect(messages, contains('stage=Translation model'));
    expect(messages, contains('stage=Image codec model'));

    connector.attachDisconnectServicesForTest(debugLog: log, timeout: timeout);
    await connector.disconnect(manual: true).timeout(const Duration(seconds: 2));
    oldTranslation.completeError(StateError('late old translation error'));
    oldImage.complete();
    await Future<void>.delayed(Duration.zero);
    expect(connector.state, MeshCoreConnectionState.disconnected);
  });

  test('a missing iOS BLE reply is bounded and a late reply cannot resume teardown', () async {
    final reply = Completer<Object?>();
    var disconnectCalls = 0;
    messenger.setMockMethodCallHandler(nativeBle, (call) {
      expect(call.method, 'disconnect');
      disconnectCalls++;
      return reply.future;
    });
    connector.attachDisconnectServicesForTest(
      debugLog: log, timeout: timeout, iosNativeBleCentral: true,
    );
    await connector.disconnect(manual: true).timeout(const Duration(seconds: 2));
    expect(disconnectCalls, 1);
    expect(connector.state, MeshCoreConnectionState.disconnected);
    expect(log.entries.any((entry) => entry.message.contains('stage=iOS BLE disconnect')), isTrue);
    connector.attachDisconnectServicesForTest(debugLog: log, timeout: timeout);
    await connector.disconnect(manual: true);
    reply.complete(null);
    await Future<void>.delayed(Duration.zero);
    expect(connector.state, MeshCoreConnectionState.disconnected);
    expect(disconnectCalls, 1);
  });
}

class _Translation extends Fake implements TranslationService {
  _Translation(this.pending);
  final Future<void> pending;
  @override
  Future<void> releaseModel() => pending;
}

class _Image extends Fake implements ImageCodecService {
  _Image(this.pending);
  final Future<void> pending;
  bool cancelled = false;
  @override
  void cancelCodecJob() { cancelled = true; }
  @override
  Future<void> releaseModel() => pending;
}
