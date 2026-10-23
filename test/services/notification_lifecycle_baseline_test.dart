import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
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
  _Harness(this.tester, this.plugin, this.service);
  final WidgetTester tester;
  final _Plugin plugin;
  final NotificationService service;

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
  service.setSelfName(null);
  service.setRateLimitClockForTest(tester.binding.clock.now);
  try {
    // portable identity могла бы запустить настоящий registry cleanup.
    expect(DataRoot.mode, DataRootMode.system);
    final initialization = _Result(service.initialize());
    await tester.pump();
    expect(initialization.completed, isTrue);
    expect(initialization.error, isNull);
    await check(_Harness(tester, plugin, service));
  } finally {
    for (final gate in plugin.gates) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
    await tester.pump(const Duration(seconds: 5));
    service.releaseReplyPort();
    service.resetForTest();
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

  group('notification lifecycle baseline', () {
    testWidgets('suppression skips every show entrypoint', (tester) async {
      await _withNotification(tester, (h) async {
        h.service.suppressNotifications(true);
        final results = [for (final type in ['direct', 'channel', 'advert', 'summary']) _Result(h.emit(type))];
        await tester.pump();
        expect(results.every((r) => r.completed && r.error == null), isTrue);
        expect(h.plugin.shown, isEmpty);
      });
    }, timeout: timeout);

    for (final type in ['direct', 'channel']) {
      testWidgets('$type public Future returns before native show completes', (tester) async {
        await _withNotification(tester, (h) async {
          final gate = h.plugin.hold('show');
          final result = _Result(h.emit(type));
          await tester.pump();
          expect(result.completed, isTrue);
          expect(result.error, isNull);
          expect(h.plugin.shown, hasLength(1));
          expect(h.plugin.finishedShows, 0);
          gate.complete();
          await tester.pump();
          expect(h.plugin.finishedShows, 1);
        });
      }, timeout: timeout);
    }

    for (final type in ['advert', 'summary']) {
      testWidgets('$type public Future waits for its immediate native show', (tester) async {
        await _withNotification(tester, (h) async {
          final gate = h.plugin.hold('show');
          final result = _Result(h.emit(type));
          await tester.pump();
          expect(result.completed, isFalse);
          expect(h.plugin.shown, hasLength(1));
          expect(h.plugin.finishedShows, 0);
          gate.complete();
          await tester.pump();
          expect(result.completed, isTrue);
          expect(result.error, isNull);
        });
      }, timeout: timeout);
    }

    testWidgets('message burst keeps notifications and silences only later updates', (tester) async {
      await _withNotification(tester, (h) async {
        final first = _Result(h.emit('direct'));
        await tester.pump();
        final second = _Result(h.emit('channel'));
        await tester.pump();
        expect(first.completed && second.completed, isTrue);
        expect(h.plugin.shown, hasLength(2));
        expect(h.plugin.android(h.plugin.shown[0])['silent'], isFalse);
        expect(h.plugin.android(h.plugin.shown[1])['silent'], isTrue);
        expect(h.plugin.args(h.plugin.shown[0])['payload'], 'message:synthetic-contact');
        expect(h.plugin.args(h.plugin.shown[1])['payload'], 'channel:2');
      });
    }, timeout: timeout);

    testWidgets('one advert in a burst waits for the five-second batch boundary', (tester) async {
      await _withNotification(tester, (h) async {
        await h.seed();
        final result = _Result(h.emit('advert'));
        await tester.pump();
        expect(result.completed, isTrue);
        expect(h.plugin.shown, isEmpty);
        await tester.pump(const Duration(milliseconds: 4999));
        expect(h.plugin.shown, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        expect(h.plugin.shown, hasLength(1));
        expect(h.plugin.args(h.plugin.shown.single)['payload'], 'advert:synthetic-advert');
      });
    }, timeout: timeout);

    testWidgets('two batched adverts become one activity summary', (tester) async {
      await _withNotification(tester, (h) async {
        await h.seed();
        final first = _Result(h.emit('advert'));
        final second = _Result(h.emit('advert'));
        await tester.pump();
        expect(first.completed && second.completed, isTrue);
        expect(h.plugin.shown, isEmpty);
        await tester.pump(const Duration(seconds: 5));
        expect(h.plugin.shown, hasLength(1));
        expect(h.plugin.args(h.plugin.shown.single)['payload'], 'batch');
      });
    }, timeout: timeout);

    testWidgets('suppression clears the pending batch without cancelling its old timer', (tester) async {
      await _withNotification(tester, (h) async {
        await h.seed();
        final result = _Result(h.emit('advert'));
        await tester.pump();
        expect(result.completed, isTrue);
        h.service.suppressNotifications(true);
        await tester.pump(const Duration(seconds: 5));
        expect(h.plugin.shown, isEmpty);
        h.service.suppressNotifications(false);
        await tester.pump();
        expect(h.plugin.shown, isEmpty);
      });
    }, timeout: timeout);

    testWidgets('cancelAll leaves an already pending advert batch for its timer', (tester) async {
      await _withNotification(tester, (h) async {
        await h.seed();
        final queued = _Result(h.emit('advert'));
        await tester.pump();
        final cancelled = _Result(h.service.cancelAll());
        await tester.pump();
        expect(queued.completed && cancelled.completed, isTrue);
        expect(h.plugin.shown, isEmpty);
        await tester.pump(const Duration(seconds: 5));
        expect(h.plugin.shown, hasLength(1));
      });
    }, timeout: timeout);

    testWidgets('an advert exactly three seconds later shows immediately', (tester) async {
      await _withNotification(tester, (h) async {
        await h.seed();
        await tester.pump(const Duration(seconds: 3));
        final gate = h.plugin.hold('show');
        final result = _Result(h.emit('advert'));
        await tester.pump();
        expect(h.plugin.shown, hasLength(1));
        expect(result.completed, isFalse);
        gate.complete();
        await tester.pump();
        expect(result.completed, isTrue);
      });
    }, timeout: timeout);

    for (final type in ['direct', 'channel', 'advert', 'summary']) {
      testWidgets('$type native show error keeps the existing caught-error behavior', (tester) async {
        await _withNotification(tester, (h) async {
          h.plugin.action = (call) async {
            if (call.method == 'show') {
              throw PlatformException(code: 'synthetic-show-error');
            }
          };
          final result = _Result(h.emit(type));
          await tester.pump();
          expect(result.completed, isTrue);
          expect(result.error, isNull);
          expect(h.plugin.shown, hasLength(1));
          expect(h.plugin.finishedShows, 1);
        });
      }, timeout: timeout);
    }

    testWidgets('denied permission makes every show return without native show', (tester) async {
      await _withNotification(tester, (h) async {
        h.plugin.allowed = false;
        for (final type in ['direct', 'channel', 'advert', 'summary']) {
          final result = _Result(h.emit(type));
          await tester.pump();
          expect(result.completed, isTrue);
          expect(result.error, isNull);
        }
        await tester.pump(const Duration(seconds: 5));
        expect(h.plugin.shown, isEmpty);
      });
    }, timeout: timeout);

    for (final type in ['one', 'all', 'contact', 'channel']) {
      testWidgets('$type cancel Future waits for native cancellation', (tester) async {
        await _withNotification(tester, (h) async {
          final gate = h.plugin.hold(type == 'all' ? 'cancelAll' : 'cancel');
          final operation = switch (type) {
            'one' => h.service.cancel(17),
            'all' => h.service.cancelAll(),
            'contact' => h.service.clearContactNotification('synthetic-contact', 0),
            _ => h.service.clearChannelNotification(2, 0),
          };
          final result = _Result(operation);
          await tester.pump();
          expect(result.completed, isFalse);
          expect(h.plugin.calls, hasLength(1));
          gate.complete();
          await tester.pump();
          expect(result.completed, isTrue);
          expect(result.error, isNull);
        });
      }, timeout: timeout);
    }

    testWidgets('own reply waits for the conversation repost', (tester) async {
      await _withNotification(tester, (h) async {
        await h.seed();
        final gate = h.plugin.hold('show');
        final result = _Result(h.service.showOwnReply(h.reply, 'synthetic reply'));
        await tester.pump();
        expect(h.plugin.shown, hasLength(1));
        expect(result.completed, isFalse);
        gate.complete();
        await tester.pump();
        expect(result.completed, isTrue);
        expect(result.error, isNull);
      });
    }, timeout: timeout);

    testWidgets('failed reply cancels a missing conversation then awaits its notice', (tester) async {
      await _withNotification(tester, (h) async {
        final gate = h.plugin.hold('show');
        final result = _Result(h.service.showReplyFailed(h.reply, NotificationReplyFailure.notConnected));
        await tester.pump();
        expect(h.plugin.calls.map((call) => call.method), ['cancel', 'show']);
        expect(result.completed, isFalse);
        gate.complete();
        await tester.pump();
        expect(result.completed, isTrue);
        expect(result.error, isNull);
      });
    }, timeout: timeout);
  }, skip: _linuxWithoutSession()
      ? 'NotificationService skips initialization without a Linux D-Bus session'
      : null);
}
