import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/flutter_foreground_task_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/background_task_options.dart';
import 'package:meshcore_open/services/background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DiagnosticBackend extends FlutterForegroundTaskPlatform {
  bool running = false;
  final starts = <ForegroundTaskOptions>[];
  final messages = <Map<String, Object?>>[];
  int stops = 0;

  @override
  Future<bool> get isRunningService async => running;

  @override
  Future<void> startService({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
    int? serviceId,
    List<ForegroundServiceTypes>? serviceTypes,
    required String notificationTitle,
    required String notificationText,
    NotificationIcon? notificationIcon,
    List<NotificationButton>? notificationButtons,
    String? notificationInitialRoute,
    Function? callback,
  }) async {
    starts.add(foregroundTaskOptions);
    running = true;
  }

  @override
  Future<void> stopService() async {
    stops++;
    running = false;
  }

  @override
  void sendDataToTask(Object data) {
    messages.add(Map<String, Object?>.from(data as Map));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('diagnostic options change only allowWakeLock', () {
    final control = backgroundTaskOptions(diagnosticCpuOff: false).toJson();
    final cpuOff = backgroundTaskOptions(diagnosticCpuOff: true).toJson();
    expect(control['allowWakeLock'], isTrue);
    expect(cpuOff['allowWakeLock'], isFalse);
    control.remove('allowWakeLock');
    cpuOff.remove('allowWakeLock');
    expect(cpuOff, control);
  });

  test('default options honor the compile-time experiment switch', () {
    const cpuOff = bool.fromEnvironment('MCO_DIAGNOSTIC_CPU_OFF');
    expect(backgroundTaskOptions().allowWakeLock, !cpuOff);
    expect(kDiagnosticCpuOff, cpuOff);
  });

  testWidgets('service applies compiled options and preserves owners and cadence', (
    tester,
  ) async {
    const engineChannel = MethodChannel('mco_advanced/engine_lifecycle');
    const wifiChannel = MethodChannel('mco_advanced/tcp_wifi_lock');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final originalPlatform = FlutterForegroundTaskPlatform.instance;
    final backend = _DiagnosticBackend();
    final retention = <bool>[];
    final wifiCalls = <bool>[];
    SharedPreferences.setMockInitialValues({});
    FlutterForegroundTask.resetStatic();
    FlutterForegroundTaskPlatform.instance = backend;
    messenger.setMockMethodCallHandler(engineChannel, (call) async {
      retention.add((call.arguments as Map)['retain'] as bool);
      return null;
    });
    messenger.setMockMethodCallHandler(wifiChannel, (call) async {
      wifiCalls.add((call.arguments as Map)['enabled'] as bool);
      return null;
    });
    final service = BackgroundService.forTest(isAndroid: true);
    service.setLanguageOverrideProvider(() => 'en');
    try {
      await service.start();
      expect(backend.starts, hasLength(1));
      final options = backend.starts.single;
      expect(options.allowWakeLock, !kDiagnosticCpuOff);
      expect(options.allowWifiLock, isFalse);
      expect(options.eventAction.interval, 5000);
      expect(options.autoRunOnBoot, isFalse);
      expect(retention.last, isTrue);
      expect(backend.messages.single['monitor'], isTrue);

      await tester.pump(const Duration(seconds: 5));
      expect(backend.messages, hasLength(2));
      await service.start(reason: 'proxy');
      expect(backend.starts, hasLength(1));
      await service.stop();
      expect(backend.running, isTrue);
      expect(backend.stops, 0);
      expect(backend.messages.last['monitor'], isFalse);
      final messageCount = backend.messages.length;
      await tester.pump(const Duration(seconds: 10));
      expect(backend.messages, hasLength(messageCount));
      await service.stop(reason: 'proxy');
      expect(backend.stops, 1);
      expect(retention.last, isFalse);
      expect(wifiCalls, isEmpty);

      await service.start();
      expect(backend.starts, hasLength(2));
      expect(backend.starts.last.toJson(), options.toJson());

      final beforeOtherPlatform = backend.messages.length;
      final otherPlatform = BackgroundService.forTest(isAndroid: false);
      await otherPlatform.initialize();
      await otherPlatform.start();
      await otherPlatform.stop();
      expect(backend.starts, hasLength(2));
      expect(backend.messages, hasLength(beforeOtherPlatform));
    } finally {
      await service.stop();
      await service.stop(reason: 'proxy');
      await tester.pump();
      FlutterForegroundTask.resetStatic();
      FlutterForegroundTaskPlatform.instance = originalPlatform;
      messenger.setMockMethodCallHandler(engineChannel, null);
      messenger.setMockMethodCallHandler(wifiChannel, null);
    }
  });
}
