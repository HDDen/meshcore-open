import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/flutter_foreground_task_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/background_service.dart';

class _ForegroundProbe extends FlutterForegroundTaskPlatform {
  int runningChecks = 0;

  @override
  Future<bool> get isRunningService async {
    runningChecks++;
    return false;
  }
}

// Настоящий BackgroundService, подменён только ответ платформенного канала.
// Проверяется Dart-контракт; это не Android Wi-Fi, lock или замер энергии.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(seconds: 10));
  const wifiChannel = MethodChannel('mco_advanced/tcp_wifi_lock');
  const cpuChannel = MethodChannel('mco_advanced/cpu_policy');
  const engineChannel = MethodChannel('mco_advanced/engine_lifecycle');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FlutterForegroundTaskPlatform originalPlatform;
  late _ForegroundProbe foreground;
  late BackgroundService service;
  late List<MethodCall> wifiCalls;
  late List<MethodCall> unrelatedCalls;

  setUp(() {
    FlutterForegroundTask.resetStatic();
    originalPlatform = FlutterForegroundTaskPlatform.instance;
    foreground = _ForegroundProbe();
    FlutterForegroundTaskPlatform.instance = foreground;
    service = BackgroundService.forTest(isAndroid: true);
    wifiCalls = [];
    unrelatedCalls = [];
    messenger.setMockMethodCallHandler(wifiChannel, (call) async {
      wifiCalls.add(call);
      return null;
    });
    for (final channel in [cpuChannel, engineChannel]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        unrelatedCalls.add(call);
        return null;
      });
    }
  });

  tearDown(() {
    for (final channel in [wifiChannel, cpuChannel, engineChannel]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    FlutterForegroundTask.resetStatic();
    FlutterForegroundTaskPlatform.instance = originalPlatform;
    // Wi-Fi-запрос сам по себе не должен менять CPU/engine/FGS.
    expect(unrelatedCalls, isEmpty);
    expect(foreground.runningChecks, 0);
  });

  group('TCP Wi-Fi lock baseline', () {
    test('enable and release use the existing channel and exact arguments',
        () async {
      await service.setTcpWifiLock(true);
      await service.setTcpWifiLock(false);

      expect(wifiCalls.map((call) => call.method), ['setEnabled', 'setEnabled']);
      expect(wifiCalls.map((call) => call.arguments), [
        {'enabled': true},
        {'enabled': false},
      ]);
    }, timeout: timeout);

    test('a rejected release does not prevent a later acquire', () async {
      messenger.setMockMethodCallHandler(wifiChannel, (call) async {
        wifiCalls.add(call);
        if ((call.arguments as Map)['enabled'] == false) {
          throw PlatformException(code: 'synthetic_release_rejected');
        }
        return null;
      });

      await expectLater(service.setTcpWifiLock(false), completes);
      await expectLater(service.setTcpWifiLock(true), completes);

      expect(wifiCalls.map((call) => call.arguments), [
        {'enabled': false},
        {'enabled': true},
      ]);
    }, timeout: timeout);

    test('release without an earlier acquire remains an explicit native release',
        () async {
      await service.setTcpWifiLock(false);

      expect(wifiCalls, hasLength(1));
      expect(wifiCalls.single.method, 'setEnabled');
      expect(wifiCalls.single.arguments, {'enabled': false});
    }, timeout: timeout);

    test('a rejected acquire is nonfatal and does not prevent a later release',
        () async {
      messenger.setMockMethodCallHandler(wifiChannel, (call) async {
        wifiCalls.add(call);
        if ((call.arguments as Map)['enabled'] == true) {
          throw PlatformException(code: 'synthetic_wifi_unavailable');
        }
        return null;
      });

      await expectLater(service.setTcpWifiLock(true), completes);
      await expectLater(service.setTcpWifiLock(false), completes);

      expect(wifiCalls.map((call) => call.arguments), [
        {'enabled': true},
        {'enabled': false},
      ]);
    }, timeout: timeout);

    test('an unavailable adapter is nonfatal for both commands', () async {
      // Явный ответ: отсутствие mock могло бы отправить вызов в test host.
      messenger.setMockMethodCallHandler(wifiChannel, (call) async {
        wifiCalls.add(call);
        throw MissingPluginException('Synthetic Wi-Fi adapter unavailable');
      });

      await expectLater(service.setTcpWifiLock(true), completes);
      await expectLater(service.setTcpWifiLock(false), completes);
      expect(wifiCalls, hasLength(2));
    }, timeout: timeout);

    test('the returned Future waits for the native reply', () async {
      final entered = Completer<void>();
      final reply = Completer<void>();
      messenger.setMockMethodCallHandler(wifiChannel, (call) async {
        wifiCalls.add(call);
        entered.complete();
        await reply.future;
        return null;
      });
      var completed = false;
      final pending = service.setTcpWifiLock(true).then((_) {
        completed = true;
      });
      try {
        await entered.future;
        expect(completed, isFalse);
        expect(wifiCalls.single.arguments, {'enabled': true});
        reply.complete();
        await pending;
        expect(completed, isTrue);
      } finally {
        if (!reply.isCompleted) {
          reply.complete();
        }
        await pending;
      }
    }, timeout: timeout);

    test('non-Android does not invoke a Wi-Fi or lifecycle adapter', () async {
      final otherPlatform = BackgroundService.forTest(isAndroid: false);

      await otherPlatform.setTcpWifiLock(true);
      await otherPlatform.setTcpWifiLock(false);

      expect(wifiCalls, isEmpty);
    }, timeout: timeout);
  });
}
