import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/flutter_foreground_task_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Предварительные контракты соседних механизмов. Длительный suspend и скачки
// часов будут отдельными регрессиями для опции сна, не требованиями legacy.
class _WorkerBackend extends FlutterForegroundTaskPlatform {
  final notifications = <String?>[];

  @override
  Future<bool> get isRunningService async => true;

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
}

class _WorkerClock {
  DateTime now = DateTime.utc(2026, 1, 1);
  late final TaskHandler handler = BackgroundService.taskHandlerForTest(
    now: () => now,
  );

  Future<void> start({bool persistedMonitor = false}) async {
    if (persistedMonitor) {
      for (final entry in <String, Object>{
        'connectionMonitorEnabled': true,
        'connectionNotificationTitle': 'Synthetic connection',
        'connectionConnectedText': 'connected',
        'connectionReconnectingText': 'reconnecting',
        'connectionBrokenText': 'broken',
      }.entries) {
        await FlutterForegroundTask.saveData(key: entry.key, value: entry.value);
      }
    }
    await handler.onStart(now, TaskStarter.developer);
  }

  void heartbeat({bool monitor = true, String state = 'connected'}) {
    handler.onReceiveData(<String, Object>{
      'type': 'connectionHeartbeat',
      'monitor': monitor,
      'state': state,
      'title': 'Synthetic connection',
      'connectedText': 'connected',
      'reconnectingText': 'reconnecting',
      'brokenText': 'broken',
      'timestampMs': now.millisecondsSinceEpoch,
    });
  }

  Future<void> tick(
    WidgetTester tester, {
    Duration elapsed = const Duration(seconds: 5),
  }) async {
    now = now.add(elapsed);
    handler.onRepeatEvent(now);
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const cpuChannel = MethodChannel('mco_advanced/cpu_policy');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FlutterForegroundTaskPlatform previous;
  late _WorkerBackend backend;
  late _WorkerClock worker;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterForegroundTask.resetStatic();
    previous = FlutterForegroundTaskPlatform.instance;
    backend = _WorkerBackend();
    FlutterForegroundTaskPlatform.instance = backend;
    worker = _WorkerClock();
    // Legacy worker без native CPU adapter, полностью внутри fake async среды.
    messenger.setMockMethodCallHandler(cpuChannel, (call) async {
      throw MissingPluginException('Synthetic CPU adapter unavailable');
    });
  });

  tearDown(() {
    FlutterForegroundTask.resetStatic();
    FlutterForegroundTaskPlatform.instance = previous;
    messenger.setMockMethodCallHandler(cpuChannel, null);
  });

  for (final heartbeatFirst in [false, true]) {
    testWidgets('regular healthy worker, heartbeat first=$heartbeatFirst',
        (tester) async {
      await worker.start();
      worker.heartbeat();
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        worker.now = worker.now.add(const Duration(seconds: 5));
        if (heartbeatFirst) worker.heartbeat();
        worker.handler.onRepeatEvent(worker.now);
        if (!heartbeatFirst) worker.heartbeat();
        await tester.pump();
        expect(backend.notifications, ['connected']);
      }
    });
  }

  testWidgets('regular worker detects real silence at twenty seconds once',
      (tester) async {
    await worker.start();
    worker.heartbeat();
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await worker.tick(tester);
      expect(backend.notifications, ['connected']);
    }
    await worker.tick(tester, elapsed: const Duration(seconds: 4));
    expect(backend.notifications, ['connected']);
    await worker.tick(tester, elapsed: const Duration(seconds: 1));
    expect(backend.notifications, ['connected', 'broken']);
    await worker.tick(tester);
    await worker.tick(tester);
    expect(backend.notifications, ['connected', 'broken']);
    worker.heartbeat();
    await tester.pump();
    expect(backend.notifications, ['connected', 'broken', 'connected']);
  });

  testWidgets('reconnecting reports and recovery remain independent of silence',
      (tester) async {
    await worker.start();
    worker.heartbeat(state: 'reconnecting');
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      worker.now = worker.now.add(const Duration(seconds: 5));
      worker.heartbeat(state: 'reconnecting');
      worker.handler.onRepeatEvent(worker.now);
      await tester.pump();
    }
    expect(backend.notifications, ['reconnecting']);
    worker.heartbeat();
    await tester.pump();
    expect(backend.notifications, ['reconnecting', 'connected']);
  });

  testWidgets('disabled monitor stays quiet and reenable gets a fresh heartbeat',
      (tester) async {
    await worker.start();
    worker.heartbeat();
    await tester.pump();
    worker.heartbeat(monitor: false);
    await worker.tick(tester, elapsed: const Duration(hours: 2));
    expect(backend.notifications, ['connected']);
    worker.heartbeat(state: 'reconnecting');
    await tester.pump();
    await worker.tick(tester);
    expect(backend.notifications, ['connected', 'reconnecting']);
  });

  testWidgets('persisted monitor has initial grace and recovers on fresh data',
      (tester) async {
    await worker.start(persistedMonitor: true);
    for (var i = 0; i < 3; i++) {
      await worker.tick(tester);
      expect(backend.notifications, isEmpty);
    }
    await worker.tick(tester);
    expect(backend.notifications, ['broken']);
    worker.heartbeat();
    await tester.pump();
    await worker.tick(tester);
    expect(backend.notifications, ['broken', 'connected']);
  });

  testWidgets('heartbeat receipt without timestamp refreshes liveness',
      (tester) async {
    await worker.start();
    worker.heartbeat();
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await worker.tick(tester);
    }
    worker.handler.onReceiveData(<String, Object>{
      'type': 'connectionHeartbeat',
      'monitor': true,
      'state': 'connected',
    });
    await worker.tick(tester);
    expect(backend.notifications, ['connected']);
    for (var i = 0; i < 3; i++) {
      await worker.tick(tester);
    }
    expect(backend.notifications, ['connected', 'broken']);
  });
}
