import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mco_service/tcp_overlay.dart' show isMcoTcpOverlayEndpoint;
import 'package:meshcore_open/services/ios_background_tcp_service.dart';

// Соседний NEAppPushManager-контракт до встраивания режима исполнения.
// Только синтетические адреса и mock channel; это не проверка фоновой работы iOS.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('mco_advanced/ios_background_tcp');
  const service = IosBackgroundTcpService.forTest(isIos: true);
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, Object?>{
        ...Map<String, Object?>.from(call.arguments as Map),
        'active': false,
      };
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('baseline: LAN configuration is normalized without claiming active', () async {
    final result = await service.configure(
      host: ' mesh.test ', port: 5000, wifiSsid: ' Synthetic Wi-Fi ',
      enabled: true,
    );

    expect(calls.single.method, 'configure');
    expect(calls.single.arguments, <String, Object?>{
      'host': 'mesh.test', 'port': 5000,
      'wifiSsid': 'Synthetic Wi-Fi', 'enabled': true,
    });
    expect(result, isNotNull);
    expect(result!.enabled, isTrue);
    expect(result.active, isFalse);
    expect(result.host, 'mesh.test');
    expect(result.port, 5000);
    expect(result.wifiSsid, 'Synthetic Wi-Fi');
  });

  test('baseline: enabling local push without an SSID makes no native call', () async {
    expect(await service.configure(
      host: 'mesh.test', port: 5000, wifiSsid: ' ', enabled: true,
    ), isNull);
    expect(calls, isEmpty);
  });

  test('baseline: disabling an old local-push session needs no SSID', () async {
    final result = await service.configure(
      host: 'mesh.test', port: 5000, wifiSsid: ' ', enabled: false,
    );
    expect(calls.single.arguments, <String, Object?>{
      'host': 'mesh.test', 'port': 5000, 'wifiSsid': '', 'enabled': false,
    });
    expect(result!.enabled, isFalse);
  });

  test('baseline: invalid endpoints never reach native, including disable', () async {
    for (final enabled in <bool>[false, true]) {
      for (final port in <int>[0, -1, 65536]) {
        expect(await service.configure(
          host: 'mesh.test', port: port, wifiSsid: 'Synthetic', enabled: enabled,
        ), isNull);
      }
      expect(await service.configure(
        host: ' ', port: 5000, wifiSsid: 'Synthetic', enabled: enabled,
      ), isNull);
    }
    expect(calls, isEmpty);
  });

  test('baseline: recognized overlay disables local push without an SSID', () async {
    final result = await service.configure(
      host: ' tailscale://synthetic-peer ', port: 5000,
      wifiSsid: '', enabled: true,
    );
    // Публичный профиль не распознаёт premium overlay; фиксируем и его guard.
    if (!isMcoTcpOverlayEndpoint('tailscale://synthetic-peer')) {
      expect(result, isNull);
      expect(calls, isEmpty);
      return;
    }
    expect(calls.single.arguments, <String, Object?>{
      'host': 'tailscale://synthetic-peer', 'port': 5000,
      'wifiSsid': '', 'enabled': false,
    });
    expect(result!.enabled, isFalse);
    expect(result.active, isFalse);
  });

  test('baseline: native null and errors are not reported as successful setup', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await service.configure(
      host: 'mesh.test', port: 5000, wifiSsid: 'Synthetic', enabled: true,
    ), isNull);

    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'synthetic_failure');
    });
    await expectLater(service.configure(
      host: 'mesh.test', port: 5000, wifiSsid: 'Synthetic', enabled: true,
    ), throwsA(isA<PlatformException>().having(
      (error) => error.code, 'code', 'synthetic_failure',
    )));
  });

  test('baseline: non-iOS configuration has no native side effects', () async {
    const otherPlatform = IosBackgroundTcpService.forTest(isIos: false);
    expect(await otherPlatform.configure(
      host: 'mesh.test', port: 5000, wifiSsid: 'Synthetic', enabled: true,
    ), isNull);
    expect(calls, isEmpty);
  });
}
