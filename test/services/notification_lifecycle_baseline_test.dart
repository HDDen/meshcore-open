import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshcore_open/helpers/message_url_image_helper.dart';
import 'package:meshcore_open/helpers/notification_conversation_work.dart';
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
  _Plugin({this.launchPayload});

  static const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  static const badge = MethodChannel('meshcore_open/app_badge');
  final String? launchPayload;
  List<Map<String, Object>> activeNotifications = [];
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
      if (call.method == 'getActiveNotifications') return activeNotifications;
      final launch = launchPayload;
      if (call.method == 'getNotificationAppLaunchDetails' && launch != null) {
        return {
          'notificationLaunchedApp': true,
          'notificationResponse': _tapResponse(launch),
        };
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

  static Map<String, Object> _tapResponse(String payload) => {
    'notificationId': 1,
    'notificationResponseType': NotificationResponseType.selectedNotification.index,
    'payload': payload,
  };

  Future<void> tap(String payload) => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          MethodCall('didReceiveNotificationResponse', _tapResponse(payload)),
        ),
        null,
      );
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

  Future<void> emit(String type, {NotificationQueueAlert? queueAlert}) => switch (type) {
    'direct' => service.showMessageNotification(
      contactName: 'synthetic sender', contactId: 'synthetic-contact',
      message: 'synthetic text', urlImagesEnabled: false,
      queueAlert: queueAlert,
    ),
    'channel' => service.showChannelMessageNotification(
      channelName: 'synthetic channel', channelIndex: 2, senderName: 'synthetic sender',
      message: 'synthetic text', urlImagesEnabled: false,
      queueAlert: queueAlert,
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

Future<void> _withNotification(
  WidgetTester tester,
  Future<void> Function(_Harness h) check, {
  String? launchPayload,
}) async {
  final plugin = _Plugin(launchPayload: launchPayload)..install();
  final service = NotificationService();
  service.resetForTest();
  service.setSelfName(null);
  service.setLocale(const Locale('en'));
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
    testWidgets('U34 baseline: cold and warm native taps reach the handler once', (
      tester,
    ) async {
      const cold = 'message:synthetic-contact';
      const warm = 'channel:2';
      await _withNotification(tester, (h) async {
        final received = <String>[];
        h.service.setTapHandler(received.add);
        await tester.pump();
        expect(received, [cold]);

        h.service.setTapHandler(received.add);
        await tester.pump();
        expect(received, [cold]);

        await h.plugin.tap(warm);
        await tester.pump();
        expect(received, [cold, warm]);
        expect(h.plugin.shown, isEmpty);
      }, launchPayload: cold);
    }, timeout: timeout);

    for (final language in ['en', 'ru']) {
      for (final type in ['direct', 'channel']) {
        testWidgets('U06c1: $type posts localized summaries ($language)', (
          tester,
        ) async {
          await _withNotification(tester, (h) async {
            h.service.setLocale(Locale(language));
            final cases = language == 'ru'
                ? const [
                    ('m:45.5,-122.6|Лагерь|poi', 'Отправлена геопозиция: Лагерь'),
                    ('m:45.5,-122.6||poi', 'Отправлена геопозиция'),
                    ('👍\nabcd2345', 'Реакция 👍'),
                    ('g:xT9IgG50Fb7Mi0prBC', 'Отправлен GIF'),
                    (
                      'https://media.giphy.com/media/xT9IgG50Fb7Mi0prBC/giphy.gif',
                      'Отправлен GIF',
                    ),
                    ('aeic:1:0a1b2c3d4e5f60', 'Отправлено изображение'),
                  ]
                : const [
                    ('m:45.5,-122.6|Лагерь|poi', 'Shared a location: Лагерь'),
                    ('m:45.5,-122.6||poi', 'Shared a location'),
                    ('👍\nabcd2345', 'Reacted 👍'),
                    ('g:xT9IgG50Fb7Mi0prBC', 'Sent a GIF'),
                    (
                      'https://media.giphy.com/media/xT9IgG50Fb7Mi0prBC/giphy.gif',
                      'Sent a GIF',
                    ),
                    ('aeic:1:0a1b2c3d4e5f60', 'Sent an image'),
                  ];
            for (final (index, (input, expected)) in cases.indexed) {
              final operation = type == 'channel'
                  ? h.service.showChannelMessageNotification(
                      channelName: 'synthetic channel',
                      channelIndex: 2,
                      senderName: 'Alice',
                      message: input,
                      urlImagesEnabled: false,
                    )
                  : h.service.showMessageNotification(
                      contactName: 'Alice',
                      contactId: 'synthetic-contact',
                      message: input,
                      urlImagesEnabled: false,
                    );
              final result = _Result(operation);
              await tester.pump();
              expect(result.completed, isTrue);
              expect(result.error, isNull);
              if (index != 0) {
                // This is another update of the same conversation. Advance
                // through the batch window before inspecting the native card.
                await tester.pump(const Duration(milliseconds: 800));
              }
              expect(h.plugin.shown, hasLength(1));
              final call = h.plugin.shown.single;
              final args = h.plugin.args(call);
              expect(args['body'], type == 'channel' ? 'Alice: $expected' : expected);
              expect(args['payload'], type == 'channel' ? 'channel:2' : 'message:synthetic-contact');
              final style = h.plugin.android(call)['styleInformation'] as Map<Object?, Object?>;
              final messages = style['messages'] as List<Object?>;
              expect((messages.last as Map<Object?, Object?>)['text'], expected);
              h.plugin.clear();
            }
          });
        }, timeout: timeout);
      }
    }

    testWidgets('master off keeps text notifications without link-image requests', (tester) async {
      await _withNotification(tester, (h) async {
        var requests = 0;
        var verifications = 0;
        final client = MockClient((_) async {
          requests++;
          return http.Response('', 503);
        });
        final oldPolicy = MessageUrlImageHelper.loadLinkImages.value;
        final oldClient = MessageUrlImageHelper.httpClient;
        final oldVerifier = MessageUrlImageHelper.verifyImageForTest;
        MessageUrlImageHelper.httpClient = client;
        MessageUrlImageHelper.verifyImageForTest = (_) async {
          verifications++;
          return true;
        };
        MessageUrlImageHelper.loadLinkImages.value = false;
        try {
          final result = _Result(h.service.showMessageNotification(
            contactName: 'synthetic sender', contactId: 'synthetic-contact',
            message: 'https://ibb.co/example', urlImagesEnabled: true,
          ));
          await tester.pump();
          expect(result.completed, isTrue);
          expect(result.error, isNull);
          expect(h.plugin.shown, hasLength(1));
          expect(requests, 0);
          expect(verifications, 0);
        } finally {
          MessageUrlImageHelper.httpClient = oldClient;
          MessageUrlImageHelper.verifyImageForTest = oldVerifier;
          MessageUrlImageHelper.loadLinkImages.value = oldPolicy;
          client.close();
        }
      });
    }, timeout: timeout);

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
      testWidgets(
        '$type keeps the Android Auto and watch notification contract',
        (tester) async {
          await _withNotification(tester, (h) async {
            h.service.setSelfName('local radio');
            final result = _Result(h.emit(type));
            await tester.pump();
            expect(result.completed, isTrue);
            expect(result.error, isNull);
            expect(h.plugin.shown, hasLength(1));

            final details = h.plugin.android(h.plugin.shown.single);
            expect(details['category'], 'msg');
            expect(details['style'], AndroidNotificationStyle.messaging.index);
            final style = details['styleInformation'] as Map<Object?, Object?>;
            expect(style['groupConversation'], type == 'channel');
            expect(
              style['conversationTitle'],
              type == 'channel' ? 'synthetic channel' : null,
            );
            final person = style['person'] as Map<Object?, Object?>;
            expect(person['name'], 'local radio');
            final messages = style['messages'] as List<Object?>;
            expect(messages, hasLength(1));
            final message = messages.single as Map<Object?, Object?>;
            expect(message['text'], 'synthetic text');
            final sender = message['person'] as Map<Object?, Object?>;
            expect(sender['name'], 'synthetic sender');

            final actions = (details['actions'] as List<Object?>)
                .cast<Map<Object?, Object?>>();
            expect(actions.map((action) => action['id']), [
              notificationReplyActionId,
              notificationMarkReadActionId,
              if (type == 'channel') notificationMuteActionId,
            ]);
            final reply = actions.first;
            expect(reply['semanticAction'], SemanticAction.reply.value);
            expect(reply['allowGeneratedReplies'], isTrue);
            expect(reply['showsUserInterface'], isFalse);
            expect(reply['cancelNotification'], isFalse);
            final inputs = reply['inputs'] as List<Object?>;
            expect(inputs, hasLength(1));
            final input = inputs.single as Map<Object?, Object?>;
            expect(input['allowFreeFormInput'], isTrue);
            expect(actions[1]['semanticAction'], SemanticAction.markAsRead.value);
            expect(actions[1]['invisible'], isTrue);
            if (type == 'channel') {
              expect(actions[2]['semanticAction'], SemanticAction.mute.value);
            }
          });
        },
        timeout: timeout,
      );

      testWidgets(
        '$type voice reply retains the conversation and remote reply action',
        (tester) async {
          await _withNotification(tester, (h) async {
            final initial = _Result(h.emit(type));
            await tester.pump();
            expect(initial.completed, isTrue);
            expect(initial.error, isNull);
            final payload = type == 'channel'
                ? 'channel:2'
                : 'message:synthetic-contact';
            final reply = NotificationReply.parse(
              actionId: notificationReplyActionId,
              payload: payload,
              input: 'voice reply',
            )!;
            final repost = _Result(h.service.showOwnReply(reply, reply.text));
            await tester.pump();
            expect(repost.completed, isTrue);
            expect(repost.error, isNull);
            expect(h.plugin.shown, hasLength(2));
            final call = h.plugin.shown.last;
            expect(h.plugin.args(call)['payload'], payload);
            final details = h.plugin.android(call);
            expect(details['style'], AndroidNotificationStyle.messaging.index);
            final style = details['styleInformation'] as Map<Object?, Object?>;
            final messages = style['messages'] as List<Object?>;
            expect(
              messages.map((item) => (item as Map<Object?, Object?>)['text']),
              ['synthetic text', 'voice reply'],
            );
            final actions = (details['actions'] as List<Object?>)
                .cast<Map<Object?, Object?>>();
            expect(actions.first['id'], notificationReplyActionId);
            expect(actions.first['semanticAction'], SemanticAction.reply.value);
          });
        },
        timeout: timeout,
      );

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

    testWidgets('U34 baseline: channel bursts retain the latest six Android Auto messages', (
      tester,
    ) async {
      await _withNotification(tester, (h) async {
        Future<void> post(String text, int unread) => h.service.showChannelMessageNotification(
          channelName: 'Synthetic channel',
          channelIndex: 2,
          senderName: 'Alice',
          message: text,
          urlImagesEnabled: false,
          badgeCount: unread,
        );

        List<Object?> shownTexts(MethodCall call) {
          final details = h.plugin.android(call);
          expect(details['style'], AndroidNotificationStyle.messaging.index);
          final style = details['styleInformation'] as Map<Object?, Object?>;
          final messages = (style['messages'] as List<Object?>)
              .cast<Map<Object?, Object?>>();
          return messages.map((message) => message['text']).toList();
        }

        for (var i = 1; i <= 8; i++) {
          final result = _Result(post('post $i', i));
          await tester.pump();
          expect(result.completed, isTrue);
          expect(result.error, isNull);
        }
        await tester.pump(const Duration(seconds: 5));

        final last = h.plugin.shown.last;
        expect(h.plugin.args(last)['payload'], 'channel:2');
        expect(h.plugin.android(last)['number'], 8);
        expect(shownTexts(last), [for (var i = 3; i <= 8; i++) 'post $i']);

        final clear = _Result(h.service.clearChannelNotification(2, 0));
        await tester.pump();
        expect(clear.completed, isTrue);
        expect(clear.error, isNull);
        final fresh = _Result(post('fresh post', 1));
        await tester.pump();
        expect(fresh.completed, isTrue);
        expect(fresh.error, isNull);
        await tester.pump(const Duration(seconds: 5));
        expect(shownTexts(h.plugin.shown.last), ['fresh post']);
      });
    }, timeout: timeout);

    testWidgets('U34: a burst posts immediately, then merges updates with the current badge', (
      tester,
    ) async {
      await _withNotification(tester, (h) async {
        var unread = 1;
        for (var i = 1; i <= 3; i++) {
          final result = _Result(h.service.showChannelMessageNotification(
            channelName: 'Test',
            channelIndex: 2,
            senderName: 'Alice',
            message: 'post $i',
            urlImagesEnabled: false,
            badgeCount: 1,
            currentUnreadTotal: () => unread,
          ));
          await tester.pump();
          expect(result.completed, isTrue);
          expect(result.error, isNull);
        }
        expect(h.plugin.shown, hasLength(1));
        expect(h.plugin.args(h.plugin.shown.single)['body'], 'Alice: post 1');
        unread = 9;
        await tester.pump(const Duration(milliseconds: 799));
        expect(h.plugin.shown, hasLength(1));
        await tester.pump(const Duration(milliseconds: 1));
        expect(h.plugin.shown, hasLength(2));
        final details = h.plugin.android(h.plugin.shown.last);
        final style = details['styleInformation'] as Map<Object?, Object?>;
        final messages = (style['messages'] as List<Object?>)
            .cast<Map<Object?, Object?>>();
        expect(messages.map((message) => message['text']), ['post 1', 'post 2', 'post 3']);
        expect(details['number'], 9);
        expect(details['silent'], isTrue);
      });
    }, timeout: timeout);

    testWidgets('U34: a queue drain alerts once across different conversations', (tester) async {
      await _withNotification(tester, (h) async {
        final drain = NotificationQueueAlert();
        await h.emit('direct', queueAlert: drain);
        await tester.pump(const Duration(seconds: 4));
        await h.emit('channel', queueAlert: drain);
        await tester.pump(const Duration(seconds: 4));
        await h.emit('channel', queueAlert: NotificationQueueAlert());
        await tester.pump();
        expect(h.plugin.shown.map((call) => h.plugin.android(call)['silent']),
            [false, true, false]);
      });
    }, timeout: timeout);

    testWidgets('U34: a slot clear drops its batch and follows a pending native show', (
      tester,
    ) async {
      await _withNotification(tester, (h) async {
        final gate = h.plugin.hold('show');
        await h.emit('channel');
        await tester.pump();
        await h.emit('channel');
        final clear = _Result(h.service.clearChannelNotification(2, 0));
        final fresh = _Result(h.service.showChannelMessageNotification(
          channelName: 'Replacement',
          channelIndex: 2,
          senderName: 'Alice',
          message: 'fresh',
          urlImagesEnabled: false,
        ));
        await tester.pump(const Duration(seconds: 1));
        expect(clear.completed, isFalse);
        expect(fresh.completed, isTrue);
        expect(h.plugin.calls.map((call) => call.method), ['show']);

        gate.complete();
        await tester.pump();
        expect(clear.completed, isTrue);
        expect(clear.error, isNull);
        expect(h.plugin.calls.map((call) => call.method), ['show', 'cancel', 'show']);
        expect(h.plugin.args(h.plugin.shown.last)['title'], 'Replacement');
        final style = h.plugin.android(h.plugin.shown.last)['styleInformation']
            as Map<Object?, Object?>;
        final messages = (style['messages'] as List<Object?>)
            .cast<Map<Object?, Object?>>();
        expect(messages.single['text'], 'fresh');
      });
    }, timeout: timeout);

    testWidgets('U34: another radio clears stale cards from a previous launch', (tester) async {
      await _withNotification(tester, (h) async {
        final saved = _Result(PrefsManager.instance
            .setString('notifications_radio_key', 'previous-radio')
            .then<void>((_) {}));
        await tester.pump();
        expect(saved.completed, isTrue);
        expect(saved.error, isNull);
        h.plugin.activeNotifications = [
          {'id': 14, 'channelId': 'channel_messages'},
          {'id': 15, 'payload': 'message:old-contact'},
          {'id': 16, 'channelId': 'license_expiry'},
        ];
        final switched = _Result(h.service.bindRadio('next-radio'));
        await tester.pump();
        expect(switched.completed, isTrue);
        expect(switched.error, isNull);
        expect(h.plugin.calls.map((call) => call.method), ['cancel', 'cancel']);
        expect(h.plugin.calls.map((call) => h.plugin.args(call)['id']), [14, 15]);
        final sameRadio = _Result(h.service.bindRadio('next-radio'));
        await tester.pump();
        expect(sameRadio.completed, isTrue);
        expect(h.plugin.calls, hasLength(2));
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
