import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/flutter_foreground_task_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/android_cpu_runtime.dart';
import 'package:meshcore_open/services/background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Backend extends FlutterForegroundTaskPlatform {
  bool running = false;
  bool failRestart = false;
  int starts = 0;
  int restarts = 0;
  int stops = 0;
  ForegroundTaskOptions? options;
  final events = <String>[];
  final messages = <Map>[];
  final notifications = <String?>[];

  @override
  Future<bool> get isRunningService async => running;

  @override
  Future<void> startService({required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions, int? serviceId,
    List<ForegroundServiceTypes>? serviceTypes, required String notificationTitle,
    required String notificationText, NotificationIcon? notificationIcon,
    List<NotificationButton>? notificationButtons, String? notificationInitialRoute,
    Function? callback}) async {
    running = true;
    starts++;
    options = foregroundTaskOptions;
  }

  @override
  Future<void> updateService({ForegroundTaskOptions? foregroundTaskOptions,
    String? notificationTitle, String? notificationText, NotificationIcon? notificationIcon,
    List<NotificationButton>? notificationButtons, String? notificationInitialRoute,
    Function? callback}) async {
    if (foregroundTaskOptions != null) {
      events.add('options'); options = foregroundTaskOptions;
    }
    if (notificationText != null) notifications.add(notificationText);
  }

  @override
  Future<void> restartService() async {
    events.add('restart');
    if (failRestart) throw StateError('synthetic restart failure');
    restarts++;
  }

  @override
  Future<void> stopService() async { running = false; stops++; }

  @override
  void sendDataToTask(Object data) { messages.add(data as Map); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const engine = MethodChannel('mco_advanced/engine_lifecycle');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FlutterForegroundTaskPlatform previous;
  late _Backend backend;
  late BackgroundService service;
  late bool managed;
  late bool hold;
  late bool work;
  late bool unconditional;
  late bool supportsUnconditional;
  late List<Map<String, Object?>> nativeRequests;
  late int uptime;
  late int generation;
  late int session;
  late int tickAcks;
  late List<bool> retention;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterForegroundTask.resetStatic();
    previous = FlutterForegroundTaskPlatform.instance;
    backend = _Backend();
    FlutterForegroundTaskPlatform.instance = backend;
    managed = false; hold = true; work = false; uptime = 1000; generation = 1; session = 0;
    tickAcks = 0; retention = [];
    unconditional = false; supportsUnconditional = true; nativeRequests = [];
    messenger.setMockMethodCallHandler(engine, (call) async {
      retention.add((call.arguments as Map)['retain'] as bool);
      return null;
    });
    messenger.setMockMethodCallHandler(AndroidCpuRuntime.channel, (call) async {
      switch (call.method) {
        case 'configure':
          final args = call.arguments as Map;
          nativeRequests.add(Map<String, Object?>.from(args));
          managed = true; hold = args['hold'] == true; work = args['work'] == true;
          unconditional = args['unconditional'] == true;
          backend.events.add(args['migrate'] == true ? 'guard' : 'hold:$hold');
          return true;
        case 'mainSession': session++; return null;
        case 'serviceStopped': backend.events.add('released'); return null;
        case 'tickDone': tickAcks++; return null;
        case 'diagnostic': return null;
      }
      return {'schema': 1, 'uptimeMs': uptime, 'generation': generation,
        'session': session, 'managed': managed,
        if (supportsUnconditional) 'unconditional': unconditional,
        if (supportsUnconditional) 'supportsUnconditional': true};
    });
  });

  tearDown(() {
    FlutterForegroundTask.resetStatic();
    FlutterForegroundTaskPlatform.instance = previous;
    messenger.setMockMethodCallHandler(engine, null);
    messenger.setMockMethodCallHandler(AndroidCpuRuntime.channel, null);
  });

  void cpuPolicyTest(String description, WidgetTesterCallback check) {
    testWidgets(description, (tester) async {
      // Очередь Future создаётся в той же FakeAsync zone, где её ожидают.
      service = BackgroundService.forTest(isAndroid: true);
      service.setLanguageOverrideProvider(() => 'en');
      try {
        await check(tester);
      } finally {
        // Снимаем heartbeat до проверки pending timers, не во внешнем tearDown.
        await service.stop();
        await service.stop(reason: 'proxy');
        await tester.pump();
      }
    });
  }

  cpuPolicyTest('handoff guards before options and worker restart, without transport stop',
      (tester) async {
    await service.start();
    expect(backend.options!.allowWakeLock, isTrue);
    await service.configureCpuSleep(requested: true, allowSleep: true, protectedWork: false);
    await tester.pump();
    expect(backend.events, ['guard', 'options', 'restart', 'hold:false']);
    expect(backend.starts, 1);
    expect(backend.stops, 0);
    expect(backend.restarts, 1);
    expect(retention, everyElement(isTrue));
    expect(backend.options!.allowWakeLock, isFalse);
    expect(backend.messages.last['uptimeMs'], uptime);
    expect(backend.messages.last['generation'], generation);
  });

  cpuPolicyTest('protected work and switching Off hold CPU without another restart',
      (tester) async {
    await service.start();
    await service.configureCpuSleep(requested: true, allowSleep: true, protectedWork: false);
    await tester.pump();
    final heartbeatCount = backend.messages.length;
    await service.configureCpuSleep(requested: true, allowSleep: true, protectedWork: true);
    await tester.pump();
    expect(backend.events.last, 'hold:false');
    expect(work, isTrue);
    expect(backend.messages.length, heartbeatCount);
    await service.configureCpuSleep(requested: false, allowSleep: false, protectedWork: false);
    expect(hold, isTrue);
    expect(work, isFalse);
    expect(backend.restarts, 1);
    expect(backend.running, isTrue);
    // The native work bit is independent of the continuous policy hold bit.
  });

  cpuPolicyTest('failed handoff retains a guard and can be retried', (tester) async {
    await service.start();
    backend.failRestart = true;
    await service.configureCpuSleep(requested: true, allowSleep: true, protectedWork: false);
    expect(hold, isTrue);
    expect(backend.running, isTrue);
    backend.failRestart = false;
    await service.configureCpuSleep(requested: true, allowSleep: false, protectedWork: false);
    expect(backend.restarts, 1);
    expect(hold, isTrue);
  });

  cpuPolicyTest('proxy owner survives connection release, last owner releases native',
      (tester) async {
    await service.start();
    await service.start(reason: 'proxy');
    await service.configureCpuSleep(requested: true, allowSleep: true, protectedWork: false);
    await service.stop();
    expect(backend.running, isTrue);
    await service.stop(reason: 'proxy');
    expect(backend.running, isFalse);
    expect(backend.events.last, 'released');
  });

  cpuPolicyTest('baseline: policy and protected work never start a service without owners',
      (tester) async {
    await service.configureCpuSleep(requested: true, allowSleep: true, protectedWork: false);
    expect(hold, isFalse);
    expect(work, isFalse);
    await service.configureCpuSleep(requested: true, allowSleep: true, protectedWork: true);
    expect(work, isTrue);
    await service.configureCpuSleep(requested: true, allowSleep: true, protectedWork: false);
    expect(work, isFalse);
    await service.configureCpuSleep(requested: false, allowSleep: false, protectedWork: false);
    expect(hold, isTrue);
    expect(backend.running, isFalse);
    expect(backend.starts, 0);
    expect(backend.restarts, 0);
    expect(retention, isEmpty);
    expect(backend.messages, isEmpty);
  });

  cpuPolicyTest('persisted native management starts a new main session and keeps Off held',
      (tester) async {
    managed = true;
    await service.start();
    await tester.pump();
    expect(session, 1);
    expect(hold, isTrue);
    expect(backend.options!.allowWakeLock, isFalse);
    expect(backend.messages.last['session'], 1);
    await service.configureCpuSleep(requested: true, allowSleep: true, protectedWork: false);
    expect(backend.restarts, 1);
    expect(hold, isFalse);
  });

  cpuPolicyTest('missing native adapter never disables the original plugin lock',
      (tester) async {
    messenger.setMockMethodCallHandler(AndroidCpuRuntime.channel, (call) async {
      throw MissingPluginException('Synthetic CPU adapter unavailable');
    });
    await service.start();
    await service.configureCpuSleep(requested: true, allowSleep: true, protectedWork: false);
    expect(backend.options!.allowWakeLock, isTrue);
    expect(backend.restarts, 0);
    expect(backend.running, isTrue);
  });

  Map<String, Object> beat(int sequence) => {'type': 'connectionHeartbeat',
    'monitor': true, 'state': 'connected', 'title': 'synthetic',
    'connectedText': 'connected', 'brokenText': 'broken',
    'generation': generation, 'session': session, 'uptimeMs': uptime,
    'sequence': sequence};

  cpuPolicyTest('real worker ignores hours of sleep but detects twenty awake seconds',
      (tester) async {
    managed = true;
    backend.running = true;
    var wall = DateTime.utc(2026);
    final worker = BackgroundService.taskHandlerForTest(now: () => wall);
    await worker.onStart(wall, TaskStarter.developer);
    worker.onReceiveData(beat(1));
    await tester.pump();
    wall = wall.add(const Duration(hours: 3));
    uptime += 1;
    worker.onRepeatEvent(wall);
    await tester.pump();
    expect(backend.notifications, ['connected']);
    expect(tickAcks, 1);
    uptime += 19999;
    worker.onRepeatEvent(wall);
    await tester.pump();
    expect(backend.notifications, ['connected', 'broken']);
    worker.onReceiveData(beat(2));
    await tester.pump();
    expect(backend.notifications, ['connected', 'broken', 'connected']);
    await worker.onDestroy(wall, false);
    worker.onReceiveData(beat(3));
    worker.onRepeatEvent(wall);
    await tester.pump();
    expect(backend.notifications, ['connected', 'broken', 'connected']);
  });

  cpuPolicyTest('native clock validation and non-Android are inert on failures',
      (tester) async {
    expect(CpuRuntimeClock.parse({'schema': 1, 'uptimeMs': -1}), isNull);
    final other = BackgroundService.forTest(isAndroid: false);
    await other.configureCpuSleep(requested: true, allowSleep: true, protectedWork: false);
    expect(backend.events, isEmpty);
    expect(managed, isFalse);
  });

  cpuPolicyTest('unconditional handoff never requests a guard or operation hold',
      (tester) async {
    await service.start();
    await service.configureCpuSleep(requested: true, allowSleep: false,
      protectedWork: true, unconditional: true);
    expect(unconditional, isTrue);
    expect(hold, isFalse);
    expect(work, isFalse);
    expect(backend.options!.allowWakeLock, isFalse);
    expect(backend.restarts, 1);
    expect(nativeRequests, isNotEmpty);
    for (final request in nativeRequests) {
      expect(request['unconditional'], isTrue);
      expect(request['hold'], isFalse);
      expect(request['work'], isFalse);
    }
    final count = nativeRequests.length;
    await service.configureCpuSleep(requested: true, allowSleep: true,
      protectedWork: true, unconditional: true);
    expect(nativeRequests.length, count, reason: 'work changes must not create CPU guards');

    await service.configureCpuSleep(requested: true, allowSleep: true, protectedWork: true);
    expect(unconditional, isFalse);
    expect(work, isTrue);
    expect(backend.restarts, 1);
    await service.configureCpuSleep(requested: false, allowSleep: false, protectedWork: false);
    expect(hold, isTrue);
    expect(work, isFalse);
  });

  cpuPolicyTest('unconditional failure does not restore an exception hold and retries same request',
      (tester) async {
    await service.start();
    backend.failRestart = true;
    await service.configureCpuSleep(requested: true, allowSleep: true,
      protectedWork: false, unconditional: true);
    expect(unconditional, isTrue);
    for (final request in nativeRequests) {
      expect(request['hold'], isFalse);
      expect(request['work'], isFalse);
      expect(request['unconditional'], isTrue);
    }
    backend.failRestart = false;
    await service.configureCpuSleep(requested: true, allowSleep: true,
      protectedWork: false, unconditional: true);
    expect(backend.restarts, 1);
    expect(hold || work, isFalse);
  });

  cpuPolicyTest('initial Off reconciles a restored unconditional native choice',
      (tester) async {
    managed = true;
    unconditional = true;
    await service.configureCpuSleep(requested: false, allowSleep: false, protectedWork: false);
    expect(session, 1);
    expect(unconditional, isFalse);
    expect(hold, isTrue);
    expect(work, isFalse);
    expect(backend.starts, 0);
    expect(backend.restarts, 0);
  });

  cpuPolicyTest('older native adapter cannot silently accept unconditional mode',
      (tester) async {
    supportsUnconditional = false;
    await service.start();
    await service.configureCpuSleep(requested: true, allowSleep: true,
      protectedWork: false, unconditional: true);
    expect(nativeRequests, isEmpty);
    expect(backend.restarts, 0);
    expect(backend.options!.allowWakeLock, isTrue);
    expect(unconditional, isFalse);
  });
}
