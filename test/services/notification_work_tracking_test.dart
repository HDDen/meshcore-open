import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/services/notification_reply.dart';
import 'package:meshcore_open/services/notification_service.dart';
import 'package:meshcore_open/storage/data_root.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic preferences without a directory');
  }
}

// Настоящий NotificationService, Android plugin через mock MethodChannel.
// Без изображений/URL, файлов, сети, реальных разрешений и OS notification UI.
class _Plugin {
  static const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  static const badge = MethodChannel('meshcore_open/app_badge');
  bool allowed = true;
  final calls = <MethodCall>[];
  final finished = <MethodCall>[];
  final gates = <Completer<void>>[];
  Future<void> Function(MethodCall)? action;

  List<MethodCall> get shown => calls.where((c) => c.method == 'show').toList();
  int get finishedShows => finished.where((c) => c.method == 'show').length;
  Map<Object?, Object?> args(MethodCall call) => call.arguments as Map<Object?, Object?>;
  Map<Object?, Object?> android(MethodCall call) => args(call)['platformSpecifics'] as Map<Object?, Object?>;

  Completer<void> hold(String method) {
    final gate = Completer<void>();
    gates.add(gate);
    action = (call) => call.method == method ? gate.future : Future<void>.value();
    return gate;
  }

  void install() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') {
        return true;
      }
      if (call.method == 'areNotificationsEnabled') {
        await action?.call(call);
        return allowed;
      }
      if (call.method == 'show' || call.method == 'cancel' || call.method == 'cancelAll') {
        calls.add(call);
        try {
          await action?.call(call);
        } finally {
          finished.add(call);
        }
      }
      return null;
    });
    messenger.setMockMethodCallHandler(badge, (_) async => null);
  }

  void remove() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(badge, null);
  }

  void clear() {
    calls.clear();
    finished.clear();
  }
}

class _Result {
  _Result(Future<void> operation) {
    unawaited(operation.then<void>((_) {
      completed = true;
    }, onError: (Object failure, StackTrace stack) {
      error = failure;
      completed = true;
    }));
  }
  bool completed = false;
  Object? error;
}

class _Harness {
  _Harness(this.tester, this.plugin, this.service, this.tracker);
  final WidgetTester tester;
  final _Plugin plugin;
  final NotificationService service;
  final BackgroundWorkTracker tracker;
  final connectors = <MeshCoreConnector>[];

  MeshCoreConnector connector() {
    final connector = MeshCoreConnector();
    connectors.add(connector);
    return connector;
  }

  void expectCount(int count, {BackgroundWorkSnapshot? snapshot}) {
    final state = snapshot ?? tracker.snapshot;
    expect(state.countFor(BackgroundWorkKind.notification), count);
    expect(state.activeCount, count);
    expect(state.isBusy, count > 0);
  }

  Future<void> emit(String type) => switch (type) {
    'direct' => service.showMessageNotification(
      contactName: 'synthetic sender', contactId: 'synthetic-contact',
      message: 'synthetic text', urlImagesEnabled: false,
    ),
    'channel' => service.showChannelMessageNotification(
      channelName: 'synthetic channel', channelIndex: 2, senderName: 'synthetic sender',
      message: 'synthetic text', urlImagesEnabled: false,
    ),
    'advert' => service.showAdvertNotification(
      contactName: 'synthetic repeater', contactType: 'Repeater', contactId: 'synthetic-advert',
    ),
    'summary' => service.showSyncSummaryNotification(messagesCount: 1, channelMessagesCount: 2),
    _ => throw ArgumentError.value(type),
  };

  Future<void> seed() async {
    final result = _Result(emit('direct'));
    await tester.pump();
    expect(result.completed, isTrue);
    expect(result.error, isNull);
    expect(plugin.finishedShows, 1);
    plugin.clear();
  }

  NotificationReply get reply => NotificationReply.parse(
    actionId: notificationReplyActionId,
    payload: 'message:synthetic-contact', input: 'synthetic reply',
  )!;
}

Future<void> _withNotification(WidgetTester tester,
    Future<void> Function(_Harness h) check) async {
  final plugin = _Plugin()..install();
  final service = NotificationService();
  service.resetForTest();
  final tracker = BackgroundWorkTracker();
  service.attachBackgroundWorkTracker(tracker);
  final harness = _Harness(tester, plugin, service, tracker);
  service.setSelfName(null);
  service.setRateLimitClockForTest(tester.binding.clock.now);
  try {
    // portable identity могла бы запустить настоящий registry cleanup.
    expect(DataRoot.mode, DataRootMode.system);
    final initialization = _Result(service.initialize());
    await tester.pump();
    expect(initialization.completed, isTrue);
    expect(initialization.error, isNull);
    await check(harness);
  } finally {
    for (final gate in plugin.gates) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
    await tester.pump(const Duration(seconds: 5));
    for (final connector in harness.connectors) {
      if (!connector.backgroundWorkSnapshot.isClosed) {
        connector.dispose();
      }
    }
    service.releaseReplyPort();
    service.resetForTest();
    tracker.close();
    plugin.remove();
  }
}

bool _linuxWithoutSession() {
  if (!Platform.isLinux) {
    return false;
  }
  if ((Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isNotEmpty) {
    return false;
  }
  final uid = Platform.environment['UID'] ?? Platform.environment['EUID'] ?? '1000';
  return !File('/run/user/$uid/bus').existsSync();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(seconds: 30));
  late PathProviderPlatform savedPaths;
  setUpAll(() {
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });
  tearDownAll(() {
    PathProviderPlatform.instance = savedPaths;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  group('notification work tracking', () {
    for (final type in ['direct', 'channel', 'advert', 'summary']) {
      testWidgets('$type tracks native show beyond the existing public boundary', (tester) async {
        await _withNotification(tester, (h) async {
          final gate = h.plugin.hold('show');
          final result = _Result(h.emit(type));
          await tester.pump();
          expect(result.completed, type == 'direct' || type == 'channel');
          expect(h.plugin.shown, hasLength(1));
          expect(h.plugin.finishedShows, 0);
          h.expectCount(1);
          gate.complete();
          await tester.pump();
          expect(result.completed, isTrue);
          expect(result.error, isNull);
          expect(h.plugin.finishedShows, 1);
          h.expectCount(0);
        });
      }, timeout: timeout);

      testWidgets('$type caught native error releases actual work', (tester) async {
        await _withNotification(tester, (h) async {
          final gate = h.plugin.hold('show');
          h.plugin.action = (call) async {
            if (call.method == 'show') {
              await gate.future;
              throw PlatformException(code: 'synthetic-show-error');
            }
          };
          final result = _Result(h.emit(type));
          await tester.pump();
          h.expectCount(1);
          gate.complete();
          await tester.pump();
          expect(result.completed, isTrue);
          expect(result.error, isNull);
          expect(h.plugin.finishedShows, 1);
          h.expectCount(0);
        });
      }, timeout: timeout);
    }

    testWidgets('permission preparation is held before native show begins', (tester) async {
      await _withNotification(tester, (h) async {
        final permission = h.plugin.hold('areNotificationsEnabled');
        final show = Completer<void>();
        h.plugin.gates.add(show);
        h.plugin.action = (call) => switch (call.method) {
          'areNotificationsEnabled' => permission.future,
          'show' => show.future,
          _ => Future<void>.value(),
        };
        final result = _Result(h.emit('direct'));
        await tester.pump();
        expect(result.completed, isTrue);
        expect(h.plugin.shown, isEmpty);
        h.expectCount(1);
        permission.complete();
        await tester.pump();
        expect(h.plugin.shown, hasLength(1));
        h.expectCount(1);
        show.complete();
        await tester.pump();
        h.expectCount(0);
      });
    }, timeout: timeout);

    for (final number in [1, 2]) {
      testWidgets('$number batched adverts hold only their actual show', (tester) async {
        await _withNotification(tester, (h) async {
          await h.seed();
          final gate = h.plugin.hold('show');
          final queued = [for (var i = 0; i < number; i++) _Result(h.emit('advert'))];
          await tester.pump();
          expect(queued.every((r) => r.completed && r.error == null), isTrue);
          h.expectCount(0);
          await tester.pump(const Duration(milliseconds: 4999));
          h.expectCount(0);
          expect(h.plugin.shown, isEmpty);
          await tester.pump(const Duration(milliseconds: 1));
          h.expectCount(1);
          expect(h.plugin.shown, hasLength(1));
          expect(h.plugin.args(h.plugin.shown.single)['payload'],
              number == 1 ? 'advert:synthetic-advert' : 'batch');
          gate.complete();
          await tester.pump();
          h.expectCount(0);
        });
      }, timeout: timeout);
    }

    testWidgets('suppression clears passive batch without leaving work', (tester) async {
      await _withNotification(tester, (h) async {
        await h.seed();
        final queued = _Result(h.emit('advert'));
        await tester.pump();
        expect(queued.completed, isTrue);
        h.service.suppressNotifications(true);
        h.expectCount(0);
        final revision = h.tracker.revision;
        for (final type in ['direct', 'channel', 'advert', 'summary']) {
          final suppressed = _Result(h.emit(type));
          await tester.pump();
          expect(suppressed.completed, isTrue);
          expect(suppressed.error, isNull);
        }
        await tester.pump(const Duration(seconds: 5));
        expect(h.plugin.shown, isEmpty);
        expect(h.tracker.revision, revision);
        h.expectCount(0);
      });
    }, timeout: timeout);

    testWidgets('cancelAll keeps the old passive batch then tracks its show', (tester) async {
      await _withNotification(tester, (h) async {
        await h.seed();
        final queued = _Result(h.emit('advert'));
        await tester.pump();
        expect(queued.completed, isTrue);
        final cancelledGate = h.plugin.hold('cancelAll');
        final cancelled = _Result(h.service.cancelAll());
        await tester.pump();
        h.expectCount(1);
        expect(cancelled.completed, isFalse);
        cancelledGate.complete();
        await tester.pump();
        expect(cancelled.completed, isTrue);
        expect(cancelled.error, isNull);
        h.expectCount(0);
        final showGate = h.plugin.hold('show');
        await tester.pump(const Duration(seconds: 5));
        expect(h.plugin.shown, hasLength(1));
        h.expectCount(1);
        showGate.complete();
        await tester.pump();
        h.expectCount(0);
      });
    }, timeout: timeout);

    testWidgets('parallel native shows release independent operations', (tester) async {
      await _withNotification(tester, (h) async {
        final first = h.plugin.hold('show');
        final second = Completer<void>();
        h.plugin.gates.add(second);
        var shows = 0;
        h.plugin.action = (call) {
          if (call.method != 'show') return Future<void>.value();
          return ++shows == 1 ? first.future : second.future;
        };
        final a = _Result(h.emit('direct'));
        await tester.pump();
        final b = _Result(h.emit('channel'));
        await tester.pump();
        expect(a.completed && b.completed, isTrue);
        expect(h.plugin.shown, hasLength(2));
        h.expectCount(2);
        first.complete();
        await tester.pump();
        h.expectCount(1);
        second.complete();
        await tester.pump();
        h.expectCount(0);
      });
    }, timeout: timeout);

    testWidgets('a late connector adopts native work started without an observer', (tester) async {
      await _withNotification(tester, (h) async {
        h.service.detachBackgroundWorkTracker(h.tracker);
        final gate = h.plugin.hold('show');
        final result = _Result(h.emit('direct'));
        await tester.pump();
        expect(result.completed, isTrue);
        h.expectCount(0);
        final connector = h.connector();
        h.expectCount(1, snapshot: connector.backgroundWorkSnapshot);
        h.service.attachBackgroundWorkTracker(h.tracker);
        h.expectCount(1);
        final revision = h.tracker.revision;
        h.service.attachBackgroundWorkTracker(h.tracker);
        expect(h.tracker.revision, revision);
        gate.complete();
        await tester.pump();
        h.expectCount(0);
        h.expectCount(0, snapshot: connector.backgroundWorkSnapshot);
      });
    }, timeout: timeout);

    testWidgets('dispose retains actual show and replacement adopts it', (tester) async {
      await _withNotification(tester, (h) async {
        final old = h.connector();
        final gate = h.plugin.hold('show');
        final result = _Result(h.emit('direct'));
        await tester.pump();
        expect(result.completed, isTrue);
        h.expectCount(1, snapshot: old.backgroundWorkSnapshot);
        old.dispose();
        expect(old.backgroundWorkSnapshot.isClosed, isTrue);
        h.expectCount(1, snapshot: old.backgroundWorkSnapshot);
        final current = h.connector();
        h.expectCount(1, snapshot: current.backgroundWorkSnapshot);
        final revision = old.backgroundWorkSnapshot.revision;
        final cancelled = _Result(h.service.cancel(17));
        await tester.pump();
        expect(cancelled.completed, isTrue);
        expect(cancelled.error, isNull);
        expect(old.backgroundWorkSnapshot.revision, revision);
        h.expectCount(1, snapshot: current.backgroundWorkSnapshot);
        gate.complete();
        await tester.pump();
        h.expectCount(0);
        h.expectCount(0, snapshot: old.backgroundWorkSnapshot);
        h.expectCount(0, snapshot: current.backgroundWorkSnapshot);
      });
    }, timeout: timeout);

    for (final type in ['one', 'all', 'contact', 'channel', 'adverts']) {
      testWidgets('$type cancellation retains work until native completion', (tester) async {
        await _withNotification(tester, (h) async {
          final gate = h.plugin.hold(type == 'all' ? 'cancelAll' : 'cancel');
          final operation = switch (type) {
            'one' => h.service.cancel(17),
            'all' => h.service.cancelAll(),
            'contact' => h.service.clearContactNotification('synthetic-contact', 0),
            'channel' => h.service.clearChannelNotification(2, 0),
            _ => h.service.clearAdvertNotifications(['synthetic-advert', 'synthetic-second']),
          };
          final result = _Result(operation);
          await tester.pump();
          h.expectCount(1);
          expect(result.completed, isFalse);
          expect(h.plugin.calls, hasLength(1));
          gate.complete();
          await tester.pump();
          expect(result.completed, isTrue);
          expect(result.error, isNull);
          expect(h.plugin.calls, hasLength(type == 'adverts' ? 2 : 1));
          h.expectCount(0);
        });
      }, timeout: timeout);
    }

    testWidgets('uncaught native cancel error keeps its API and releases work', (tester) async {
      await _withNotification(tester, (h) async {
        final gate = h.plugin.hold('cancel');
        h.plugin.action = (call) async {
          if (call.method == 'cancel') {
            await gate.future;
            throw PlatformException(code: 'synthetic-cancel-error');
          }
        };
        final result = _Result(h.service.cancel(17));
        await tester.pump();
        h.expectCount(1);
        gate.complete();
        await tester.pump();
        expect(result.completed, isTrue);
        expect(result.error, isA<PlatformException>());
        h.expectCount(0);
      });
    }, timeout: timeout);

    testWidgets('own reply holds its conversation repost', (tester) async {
      await _withNotification(tester, (h) async {
        await h.seed();
        final gate = h.plugin.hold('show');
        final result = _Result(h.service.showOwnReply(h.reply, 'synthetic reply'));
        await tester.pump();
        h.expectCount(1);
        expect(result.completed, isFalse);
        gate.complete();
        await tester.pump();
        expect(result.completed, isTrue);
        expect(result.error, isNull);
        h.expectCount(0);
      });
    }, timeout: timeout);

    testWidgets('failed reply stays held across cancel and its failure notice', (tester) async {
      await _withNotification(tester, (h) async {
        final cancelled = h.plugin.hold('cancel');
        final show = Completer<void>();
        h.plugin.gates.add(show);
        h.plugin.action = (call) => call.method == 'cancel' ? cancelled.future : show.future;
        final result = _Result(h.service.showReplyFailed(h.reply, NotificationReplyFailure.sendFailed));
        await tester.pump();
        h.expectCount(1);
        expect(h.plugin.shown, isEmpty);
        cancelled.complete();
        await tester.pump();
        expect(h.plugin.shown, hasLength(1));
        expect(result.completed, isFalse);
        h.expectCount(1);
        show.complete();
        await tester.pump();
        expect(result.completed, isTrue);
        expect(result.error, isNull);
        h.expectCount(0);
      });
    }, timeout: timeout);

    testWidgets('caller timeout does not release an unfinished native show', (tester) async {
      await _withNotification(tester, (h) async {
        final gate = h.plugin.hold('show');
        final result = _Result(h.emit('advert').timeout(const Duration(milliseconds: 1)));
        await tester.pump();
        h.expectCount(1);
        await tester.pump(const Duration(milliseconds: 1));
        expect(result.completed, isTrue);
        expect(result.error, isA<TimeoutException>());
        h.expectCount(1);
        gate.complete();
        await tester.pump();
        h.expectCount(0);
      });
    }, timeout: timeout);

    testWidgets('test reset detaches bindings without releasing native work', (tester) async {
      await _withNotification(tester, (h) async {
        final gate = h.plugin.hold('show');
        final result = _Result(h.emit('direct'));
        await tester.pump();
        expect(result.completed, isTrue);
        h.service.resetForTest();
        h.expectCount(1);
        gate.complete();
        await tester.pump();
        h.expectCount(0);
      });
    }, timeout: timeout);

    testWidgets('denied permission drains preparation without native show', (tester) async {
      await _withNotification(tester, (h) async {
        h.plugin.allowed = false;
        for (final type in ['direct', 'channel', 'advert', 'summary']) {
          final result = _Result(h.emit(type));
          await tester.pump();
          expect(result.completed, isTrue);
          expect(result.error, isNull);
          h.expectCount(0);
        }
        await tester.pump(const Duration(seconds: 5));
        expect(h.plugin.shown, isEmpty);
        h.expectCount(0);
      });
    }, timeout: timeout);
  }, skip: _linuxWithoutSession() ? 'NotificationService requires a Linux D-Bus session' : false);
}

