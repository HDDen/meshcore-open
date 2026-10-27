import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/flutter_foreground_task_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Реальные BackgroundService/TaskHandler, синтетический plugin backend.
// Fake time проверяет Dart-таймер, не Android wakelock, Doze или живые изоляты.
class _TaskBackend extends FlutterForegroundTaskPlatform {
  bool running = false;
  int starts = 0;
  int stops = 0;
  ForegroundTaskOptions? startedOptions;
  final messages = <Map<String, Object?>>[];
  final notifications = <String?>[];

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
    starts++;
    startedOptions = foregroundTaskOptions;
    running = true;
  }

  @override
  Future<void> stopService() async {
    stops++;
    running = false;
  }

  @override
  Future<void> updateService({
    ForegroundTaskOptions? foregroundTaskOptions,
    String? notificationTitle,
    String? notificationText,
    NotificationIcon? notificationIcon,
    List<NotificationButton>? notificationButtons,
    String? notificationInitialRoute,
    Function? callback,
  }) async {
    notifications.add(notificationText);
  }

  @override
  void sendDataToTask(Object data) {
    messages.add(Map<String, Object?>.from(data as Map));
  }
}

Future<void> _withService(
  WidgetTester tester,
  Future<void> Function(BackgroundService service) check, {
  bool isAndroid = true,
}) async {
  final service = BackgroundService.forTest(isAndroid: isAndroid);
  service.setLanguageOverrideProvider(() => 'en');
  try {
    await check(service);
  } finally {
    // Снимаем все синтетические owners до проверки оставшихся таймеров binding.
    for (final reason in ['connection', 'tcp-connection', 'wardrive', 'proxy']) {
      await service.stop(reason: reason);
    }
    await tester.pump();
  }
}

Map<String, Object> _heartbeat({
  bool monitor = true,
  String state = 'connected',
  int? timestampMs,
}) => {
  'type': 'connectionHeartbeat',
  'monitor': monitor,
  'state': state,
  'title': 'Synthetic connection',
  'connectedText': 'connected',
  'reconnectingText': 'reconnecting',
  'brokenText': 'broken',
  'timestampMs': timestampMs ?? DateTime.now().millisecondsSinceEpoch,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const engineChannel = MethodChannel('mco_advanced/engine_lifecycle');
  const wifiChannel = MethodChannel('mco_advanced/tcp_wifi_lock');
  const cpuChannel = MethodChannel('mco_advanced/cpu_policy');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FlutterForegroundTaskPlatform originalPlatform;
  late _TaskBackend backend;
  late List<bool> retention;
  late List<bool> wifiLocks;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterForegroundTask.resetStatic();
    originalPlatform = FlutterForegroundTaskPlatform.instance;
    backend = _TaskBackend();
    FlutterForegroundTaskPlatform.instance = backend;
    retention = [];
    wifiLocks = [];
    // Новый native-канал отсутствует в legacy fixture; не отправляем вызов в host.
    messenger.setMockMethodCallHandler(cpuChannel, (call) async {
      throw MissingPluginException('Synthetic CPU adapter unavailable');
    });
    messenger.setMockMethodCallHandler(engineChannel, (call) async {
      expect(call.method, 'setRetainEngine');
      retention.add((call.arguments as Map)['retain'] as bool);
      return null;
    });
    messenger.setMockMethodCallHandler(wifiChannel, (call) async {
      expect(call.method, 'setEnabled');
      wifiLocks.add((call.arguments as Map)['enabled'] as bool);
      return null;
    });
  });

  tearDown(() {
    FlutterForegroundTask.resetStatic();
    FlutterForegroundTaskPlatform.instance = originalPlatform;
    messenger.setMockMethodCallHandler(engineChannel, null);
    messenger.setMockMethodCallHandler(wifiChannel, null);
    messenger.setMockMethodCallHandler(cpuChannel, null);
  });

  testWidgets('baseline: service keeps current locks and a single five-second heartbeat',
      (tester) async {
    await _withService(tester, (service) async {
      await service.start();
      final options = backend.startedOptions!;
      expect(options.eventAction.interval, 5000);
      expect(options.allowWakeLock, isTrue);
      expect(options.allowWifiLock, isFalse);
      expect(options.autoRunOnBoot, isFalse);
      expect(backend.starts, 1);
      expect(retention, [true]);
      expect(backend.messages.single['monitor'], isTrue);
      expect(backend.messages.single['state'], 'connected');
      expect(backend.messages.single['timestampMs'], isA<int>());
      await tester.pump(const Duration(seconds: 4));
      expect(backend.messages, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(backend.messages, hasLength(2));
      await tester.pump(const Duration(seconds: 5));
      expect(backend.messages, hasLength(3));
      await service.stop();
      expect(backend.messages.last['monitor'], isFalse);
      final afterStop = backend.messages.length;
      await tester.pump(const Duration(seconds: 15));
      expect(backend.messages, hasLength(afterStop));
      expect(backend.stops, 1);
      expect(retention.last, isFalse);
    });
  });

  testWidgets('baseline: repeated reason is idempotent and another owner keeps service alive',
      (tester) async {
    await _withService(tester, (service) async {
      await service.start();
      await service.start();
      await service.start(reason: 'wardrive');
      expect(backend.starts, 1);
      final beforeTick = backend.messages.length;
      await tester.pump(const Duration(seconds: 5));
      expect(backend.messages, hasLength(beforeTick + 1));
      await service.stop();
      expect(backend.running, isTrue);
      expect(backend.stops, 0);
      expect(retention.last, isTrue);
      expect(backend.messages.last['monitor'], isFalse);
      final afterConnection = backend.messages.length;
      await tester.pump(const Duration(seconds: 15));
      expect(backend.messages, hasLength(afterConnection));
      await service.stop(reason: 'wardrive');
      expect(backend.running, isFalse);
      expect(backend.stops, 1);
      expect(retention.last, isFalse);
    });
  });

  testWidgets('baseline: TCP and connection owners independently retain monitoring',
      (tester) async {
    await _withService(tester, (service) async {
      await service.start(reason: 'proxy');
      expect(backend.messages.last['monitor'], isFalse);
      await service.start();
      await service.start(reason: 'tcp-connection');
      await service.stop();
      expect(backend.messages.last['monitor'], isTrue);
      final beforeTick = backend.messages.length;
      await tester.pump(const Duration(seconds: 5));
      expect(backend.messages, hasLength(beforeTick + 1));
      await service.stop(reason: 'tcp-connection');
      expect(backend.messages.last['monitor'], isFalse);
      expect(backend.running, isTrue);
      expect(backend.stops, 0);
      await service.stop(reason: 'proxy');
      expect(backend.running, isFalse);
      expect(wifiLocks, isEmpty, reason: 'Wi-Fi lock has an independent channel');
    });
  });

  testWidgets('baseline: outage announcement is deduplicated until recovery',
      (tester) async {
    await _withService(tester, (service) async {
      await service.start();
      await service.setConnectionLost(true);
      expect(backend.notifications, hasLength(1));
      expect(backend.messages.last['state'], 'reconnecting');
      await service.setConnectionLost(true);
      expect(backend.notifications, hasLength(1));
      await tester.pump(const Duration(seconds: 5));
      expect(backend.messages.last['state'], 'reconnecting');
      await service.setConnectionLost(false);
      expect(backend.notifications, hasLength(2));
      expect(backend.messages.last['state'], 'connected');
      await service.setConnectionLost(true);
      expect(backend.notifications, hasLength(3));
    });
  });

  testWidgets('baseline: Wi-Fi lock does not start service and other platforms are inert',
      (tester) async {
    await _withService(tester, (service) async {
      await service.setTcpWifiLock(true);
      await service.setTcpWifiLock(false);
      expect(wifiLocks, [true, false]);
      expect(backend.starts, 0);
      expect(retention, isEmpty);
    });
    retention.clear();
    wifiLocks.clear();
    backend.messages.clear();
    await _withService(tester, (service) async {
      await service.initialize();
      await service.start();
      await service.setConnectionLost(true);
      await service.setTcpWifiLock(true);
      await service.stop();
      expect(backend.starts, 0);
      expect(backend.messages, isEmpty);
      expect(wifiLocks, isEmpty);
      expect(retention, isEmpty);
    }, isAndroid: false);
  });

  testWidgets('baseline: worker uses a twenty-second wall-clock heartbeat and deduplicates broken',
      (tester) async {
    backend.running = true;
    var now = DateTime.utc(2026, 1, 1);
    final handler = BackgroundService.taskHandlerForTest(now: () => now);
    await handler.onStart(now, TaskStarter.developer);
    handler.onReceiveData(_heartbeat(timestampMs: now.millisecondsSinceEpoch));
    await tester.pump();
    expect(backend.notifications, ['connected']);
    now = now.add(const Duration(seconds: 19));
    handler.onRepeatEvent(DateTime.utc(2100));
    await tester.pump();
    expect(backend.notifications, ['connected']);
    now = now.add(const Duration(seconds: 1));
    handler.onRepeatEvent(DateTime.utc(2000));
    await tester.pump();
    expect(backend.notifications, ['connected', 'broken']);
    handler.onRepeatEvent(now);
    await tester.pump();
    expect(backend.notifications, ['connected', 'broken']);
    handler.onReceiveData(_heartbeat(timestampMs: now.millisecondsSinceEpoch));
    await tester.pump();
    handler.onRepeatEvent(now);
    await tester.pump();
    expect(backend.notifications, ['connected', 'broken', 'connected']);
    await handler.onDestroy(now, false);
  });

  testWidgets('baseline: worker restores persisted monitoring and respects disable messages',
      (tester) async {
    backend.running = true;
    for (final entry in {
      'connectionMonitorEnabled': true,
      'connectionNotificationTitle': 'Synthetic title',
      'connectionConnectedText': 'connected',
      'connectionReconnectingText': 'reconnecting',
      'connectionBrokenText': 'broken',
    }.entries) {
      await FlutterForegroundTask.saveData(key: entry.key, value: entry.value);
    }
    var now = DateTime.utc(2026, 1, 1);
    final handler = BackgroundService.taskHandlerForTest(now: () => now);
    await handler.onStart(now, TaskStarter.system);
    handler.onRepeatEvent(now);
    await tester.pump();
    expect(backend.notifications, isEmpty);
    now = now.add(const Duration(seconds: 20));
    handler.onRepeatEvent(now);
    await tester.pump();
    expect(backend.notifications, ['broken']);
    handler.onReceiveData(_heartbeat(timestampMs: now.millisecondsSinceEpoch));
    await tester.pump();
    handler.onReceiveData(_heartbeat(monitor: false));
    handler.onReceiveData({'type': 'unrelated'});
    now = now.add(const Duration(minutes: 10));
    handler.onRepeatEvent(now);
    await tester.pump();
    expect(backend.notifications, ['broken', 'connected']);
    handler.onReceiveData(_heartbeat(
      state: 'reconnecting', timestampMs: now.millisecondsSinceEpoch));
    await tester.pump();
    expect(backend.notifications, ['broken', 'connected', 'reconnecting']);
    await handler.onDestroy(now, false);
  });
}
