import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic preferences without a directory');
  }
}

final _channel = Channel(index: 0, name: 'synthetic', psk: Uint8List(16));
final _contact = Contact(
  publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
  name: 'synthetic contact',
  type: advTypeChat,
  pathLength: -1,
  path: Uint8List(0),
  lastSeen: DateTime.fromMillisecondsSinceEpoch(1700000000000),
);

// Настоящие pending/commit/flush и hop-loop. Нода не привязана, БД не открыта.
// Готовность/связь и physical writer синтетические; ACK/scope ответ — dispatch.
class _Connector extends MeshCoreConnector {
  bool connected = true;
  bool ready = true;
  bool answerScopeInline = false;
  final frames = <List<int>>[];
  final held = <Completer<void>>[];
  Future<void> Function(Uint8List)? write;

  _Connector() {
    setFrameWriterForTest((frame) {
      frames.add(List<int>.of(frame));
      // Query/response проверяем раздельно. Ранний ответ внутри writer —
      // отдельный сценарий, а не скрытое условие всех deferred-тестов.
      if (frame[0] != cmdGetDefaultFloodScope || answerScopeInline) {
        handleFrameForTest([
          frame[0] == cmdGetDefaultFloodScope
              ? respCodeDefaultFloodScope
              : respCodeOk,
        ]);
      }
      return write?.call(frame) ?? Future<void>.value();
    });
  }

  @override
  bool get isConnected => connected;
  @override
  bool get isSessionReady => ready;

  Completer<void> hold() {
    final completion = Completer<void>();
    held.add(completion);
    return completion;
  }

  void installChannel() {
    final frame = Uint8List(50);
    frame[0] = respCodeChannelInfo;
    frame[1] = _channel.index;
    frame.setRange(2, 2 + _channel.name.length, _channel.name.codeUnits);
    handleFrameForTest(frame);
  }
}

class _Result {
  _Result(Future<void> operation) {
    unawaited(operation.then<void>((_) {
      completed = true;
    }, onError: (Object value, StackTrace stack) {
      error = value;
      completed = true;
    }));
  }
  bool completed = false;
  Object? error;
}

class _Harness {
  _Harness(this.c, this.settings, this.tester);
  final _Connector c;
  final AppSettingsService settings;
  final WidgetTester tester;
  int resends = 0;
  Future<void> Function()? resend;

  ChannelMessage hopMessage({String id = 'hop'}) {
    final now = tester.binding.clock.now();
    return ChannelMessage(
      messageId: id, senderName: 'synthetic', text: 'synthetic hop',
      timestamp: now, receivedAt: now, sentByRadioAt: now,
      isOutgoing: true, status: ChannelMessageStatus.sent,
      repeatCount: 1, pathLength: 1, pathHashWidth: 2,
      pathBytes: Uint8List.fromList([0x81, 0x30]),
    );
  }

  Future<void> prepareHop() async {
    await settings.updateSettings(AppSettings(
      channelMinHopsEnabled: true,
      channelMinHops: 2,
      channelMinHopsRetries: 1,
      channelMinHopsDelaySeconds: 5,
      noRetransmissionWarningSeconds: 7,
    ));
    c.setChannelMessagesForTest(_channel.index, [hopMessage()]);
  }

  _Result startHop({String id = 'hop', int maxResends = 1}) =>
      _Result(c.runChannelHopCheckForTest(
        id, minHops: 2, maxResends: maxResends,
        resend: () {
          resends++;
          return resend?.call() ?? Future<void>.value();
        },
      ));

  void echoTwoHops() {
    final original = c.getChannelMessages(_channel).single;
    c.mergeChannelEchoForTest(_channel.index, ChannelMessage(
      messageId: original.messageId, senderName: original.senderName,
      text: original.text, timestamp: original.timestamp,
      receivedAt: tester.binding.clock.now(), isOutgoing: false,
      status: ChannelMessageStatus.sent, pathLength: 2, pathHashWidth: 2,
      pathBytes: Uint8List.fromList([0x81, 0x30, 0x99, 0x99]),
    ));
  }

  void scheduleContact({int delay = 0}) => c.scheduleContactMessage(
    _contact, 'scheduled direct', inputText: 'direct draft', delaySeconds: delay,
  );

  void scheduleChannel({int delay = 0}) => c.scheduleChannelMessage(
    _channel, 'scheduled channel', inputText: 'channel draft',
    delaySeconds: delay, region: '',
  );

  List<String> get channelTexts => c.frames
      .where((frame) => frame[0] == cmdSendChannelTxtMsg)
      .map((frame) => String.fromCharCodes(frame.skip(7)))
      .toList();

  Future<void> drainScopeCompletion() async {
    final before = tester.binding.clock.now();
    await tester.pump();
    // getDefaultRegionScope ждёт subscription.cancel() в finally. Broadcast
    // без onCancel возвращает общий Future из root Zone, вне FakeAsync.
    // Даём ему завершиться, затем продолжаем цепочку в виртуальном времени.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(Duration.zero);
    expect(tester.binding.clock.now(), before,
        reason: 'Scope completion must not advance to the command timeout');
  }

  Future<void> replyToDefaultScope() async {
    expect(
      c.frames.where((frame) => frame[0] == cmdGetDefaultFloodScope),
      hasLength(1),
      reason: 'END must reach the scope query before TX; '
          'contacts=${c.isLoadingContacts}, channels=${c.isSyncingChannels}, '
          'frames=${c.frames.map((frame) => frame[0]).toList()}',
    );
    expect(channelTexts, isEmpty);
    c.handleFrameForTest([respCodeDefaultFloodScope]);
    await drainScopeCompletion();
  }
}

Future<void> _withOutgoing(
  WidgetTester tester,
  Future<void> Function(_Harness h) check,
) async {
  final c = _Connector();
  final settings = AppSettingsService();
  final h = _Harness(c, settings, tester);
  c.attachAppSettingsServiceForTest(settings);
  c.setChannelResendClockForTest(tester.binding.clock.now);
  try {
    await check(h);
  } finally {
    c.ready = false;
    for (final message in c.getPendingContactMessages(_contact.publicKeyHex)) {
      c.cancelPendingContactSend(message.messageId);
    }
    for (final message in c.getPendingChannelMessages(_channel.index)) {
      c.cancelPendingChannelSend(message.messageId);
    }
    c.setChannelMessagesForTest(_channel.index, []);
    for (final completion in c.held) {
      if (!completion.isCompleted) {
        completion.complete();
      }
    }
    // Future.any после раннего эхо сохраняет delayed Future; после held resend
    // возможен ещё один пятисекундный deadline. Не оставляем их тестеру.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    c.connected = false;
    c.resetSyncProgressForTest();
    c.dispose();
    settings.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(seconds: 30));
  late PathProviderPlatform savedPaths;
  setUpAll(() {
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
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

  testWidgets('baseline: hop deadline starts a resend and its pending callback remains awaited', (tester) async {
    await _withOutgoing(tester, (h) async {
      await h.prepareHop();
      final completion = h.c.hold();
      h.resend = () => completion.future;
      final loop = h.startHop();
      await tester.pump(const Duration(milliseconds: 4999));
      expect(h.resends, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.resends, 1);
      expect(loop.completed, isFalse);
      expect(h.c.channelResendProgress('hop'), (resends: 1, maxResends: 1));
      await tester.pump(const Duration(seconds: 5));
      expect(h.resends, 1);
      h.echoTwoHops();
      await tester.pump();
      expect(loop.completed, isFalse);
      completion.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(loop.completed, isTrue);
      expect(loop.error, isNull);
      expect(h.c.channelHopShortfall('hop'), isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: disconnect does not wake the hop wait before its deadline', (tester) async {
    await _withOutgoing(tester, (h) async {
      await h.prepareHop();
      final loop = h.startHop();
      await tester.pump(const Duration(seconds: 1));
      h.c.connected = false;
      expect(loop.completed, isFalse);
      await tester.pump(const Duration(seconds: 4));
      expect(loop.completed, isTrue);
      expect(loop.error, isNull);
      expect(h.resends, 0);
      expect(h.c.channelHopShortfall('hop'), (hops: 1, required: 2));
      expect(h.c.getChannelMessages(_channel).single.status, ChannelMessageStatus.sent);
    });
  }, timeout: timeout);

  testWidgets('baseline: resend failure is caught and completes with a shortfall', (tester) async {
    await _withOutgoing(tester, (h) async {
      await h.prepareHop();
      h.resend = () => Future<void>.error(StateError('synthetic resend failure'));
      final loop = h.startHop();
      await tester.pump(const Duration(seconds: 5));
      expect(loop.completed, isTrue);
      expect(loop.error, isNull);
      expect(h.resends, 1);
      expect(h.c.channelResendProgress('hop'), isNull);
      expect(h.c.channelHopShortfall('hop'), (hops: 1, required: 2));
    });
  }, timeout: timeout);

  testWidgets('baseline: a failed message ends the loop when the pending deadline expires', (tester) async {
    await _withOutgoing(tester, (h) async {
      await h.prepareHop();
      final loop = h.startHop();
      h.c.setChannelMessagesForTest(_channel.index, [
        h.hopMessage().copyWith(status: ChannelMessageStatus.failed),
      ]);
      expect(loop.completed, isFalse);
      await tester.pump(const Duration(seconds: 5));
      expect(loop.completed, isTrue);
      expect(h.resends, 0);
      expect(h.c.channelResendProgress('hop'), isNull);
      expect(h.c.channelHopShortfall('hop'), isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: removing a message does not cancel a running resend Future', (tester) async {
    await _withOutgoing(tester, (h) async {
      await h.prepareHop();
      final completion = h.c.hold();
      h.resend = () => completion.future;
      final loop = h.startHop();
      await tester.pump(const Duration(seconds: 5));
      h.c.setChannelMessagesForTest(_channel.index, []);
      expect(loop.completed, isFalse);
      completion.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(loop.completed, isTrue);
      expect(loop.error, isNull);
      expect(h.resends, 1);
    });
  }, timeout: timeout);

  testWidgets('baseline: independent hop loops keep separate progress and deadlines', (tester) async {
    await _withOutgoing(tester, (h) async {
      await h.prepareHop();
      h.c.setChannelMessagesForTest(_channel.index, [
        h.hopMessage(), h.hopMessage(id: 'other'),
      ]);
      final completion = h.c.hold();
      h.resend = () => completion.future;
      final first = h.startHop(maxResends: 0);
      final second = h.startHop(id: 'other');
      await tester.pump(const Duration(seconds: 5));
      expect(first.completed, isTrue);
      expect(second.completed, isFalse);
      expect(h.c.channelResendProgress('hop'), isNull);
      expect(h.c.channelResendProgress('other'), (resends: 1, maxResends: 1));
      completion.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(second.completed, isTrue);
      expect(second.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: zero-delay scheduled messages wait for resume and cancellation restores drafts', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.c.ready = false;
      h.scheduleContact();
      h.scheduleChannel();
      final direct = h.c.getPendingContactMessages(_contact.publicKeyHex).single;
      final channel = h.c.getPendingChannelMessages(_channel.index).single;
      await tester.pump(const Duration(seconds: 10));
      expect(h.c.frames, isEmpty);
      expect(h.c.pendingContactSendAt(direct.messageId), isNull);
      expect(h.c.pendingChannelSendAt(channel.messageId), isNull);
      expect(h.c.cancelPendingContactSend(direct.messageId), 'direct draft');
      expect(h.c.cancelPendingChannelSend(channel.messageId), 'channel draft');
      expect(h.c.getPendingContactMessages(_contact.publicKeyHex), isEmpty);
      expect(h.c.getPendingChannelMessages(_channel.index), isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: positive direct delay commits at its timer while ready', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.scheduleContact(delay: 2);
      final message = h.c.getPendingContactMessages(_contact.publicKeyHex).single;
      expect(h.c.pendingContactSendDelaySeconds(message.messageId), 2);
      await tester.pump(const Duration(milliseconds: 1999));
      expect(h.c.frames, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.c.frames.single.first, cmdSendTxtMsg);
      expect(h.c.getPendingContactMessages(_contact.publicKeyHex), isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: expired timer keeps its pending message when the session is unready', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.c.ready = false;
      h.scheduleContact(delay: 1);
      await tester.pump(const Duration(seconds: 2));
      expect(h.c.frames, isEmpty);
      expect(h.c.getPendingContactMessages(_contact.publicKeyHex), hasLength(1));
    });
  }, timeout: timeout);

  testWidgets('baseline: resume commits a zero-delay direct send once', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.c.ready = false;
      h.scheduleContact();
      h.c.ready = true;
      final result = _Result(h.c.resumePendingOutgoingMessages());
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(h.c.frames.single.first, cmdSendTxtMsg);
      expect(h.c.getPendingContactMessages(_contact.publicKeyHex), isEmpty);
      await h.c.resumePendingOutgoingMessages();
      expect(h.c.frames, hasLength(1));
    });
  }, timeout: timeout);

  testWidgets('baseline: committed direct message is no longer cancellable from the scheduled queue', (tester) async {
    await _withOutgoing(tester, (h) async {
      final completion = h.c.hold();
      h.c.write = (_) => completion.future;
      h.scheduleContact(delay: 1);
      final message = h.c.getPendingContactMessages(_contact.publicKeyHex).single;
      await tester.pump(const Duration(seconds: 1));
      expect(h.c.frames.single.first, cmdSendTxtMsg);
      expect(h.c.cancelPendingContactSend(message.messageId), isNull);
      expect(completion.isCompleted, isFalse);
      expect(h.c.hasPendingRadioStatsWork, isTrue);
      completion.complete();
      await tester.pump();
      expect(h.c.hasPendingRadioStatsWork, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: a missing live channel fails a scheduled message without radio TX', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.scheduleChannel();
      final id = h.c.getPendingChannelMessages(_channel.index).single.messageId;
      final result = _Result(h.c.resumePendingOutgoingMessages());
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(h.c.frames, isEmpty);
      expect(h.c.getPendingChannelMessages(_channel.index), isEmpty);
      final message = h.c.getChannelMessages(_channel).single;
      expect(message.messageId, id);
      expect(message.status, ChannelMessageStatus.failed);
    });
  }, timeout: timeout);

  testWidgets('baseline: repeated resume does not overlap an unfinished scheduled channel commit', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.c.installChannel();
      await tester.pump();
      expect(h.c.channels, hasLength(1));
      final completion = h.c.hold();
      h.c.write = (_) => h.c.frames.length == 1
          ? completion.future : Future<void>.value();
      h.scheduleChannel();
      final first = _Result(h.c.resumePendingOutgoingMessages());
      await tester.pump();
      expect(h.c.frames.single.first, cmdSetFloodScope);
      expect(first.completed, isFalse);
      final second = _Result(h.c.resumePendingOutgoingMessages());
      await tester.pump();
      expect(second.completed, isTrue);
      expect(h.c.frames, hasLength(1));
      completion.complete();
      await tester.pump();
      expect(first.completed, isTrue);
      expect(first.error, isNull);
      expect(second.error, isNull);
      expect(h.channelTexts, ['scheduled channel']);
      expect(h.c.getPendingChannelMessages(_channel.index), isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: cancelling before a scheduled channel timer prevents commit', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.scheduleChannel(delay: 2);
      final id = h.c.getPendingChannelMessages(_channel.index).single.messageId;
      expect(h.c.cancelPendingChannelSend(id), 'channel draft');
      await tester.pump(const Duration(seconds: 3));
      expect(h.c.frames, isEmpty);
      expect(h.c.getChannelMessages(_channel), isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: default scope reply completes the explicit query before deferred TX tests', (tester) async {
    await _withOutgoing(tester, (h) async {
      String? region;
      final query = _Result(h.c.getDefaultRegionScope().then<void>((value) {
        region = value;
      }));
      await tester.pump();
      expect(query.completed, isFalse);
      await h.replyToDefaultScope();
      expect(query.completed, isTrue);
      expect(query.error, isNull);
      expect(region, '');
    });
  }, timeout: timeout);

  testWidgets('baseline: an early default scope reply inside the physical writer is preserved', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.c.answerScopeInline = true;
      String? region;
      final query = _Result(h.c.getDefaultRegionScope().then<void>((value) {
        region = value;
      }));
      await h.drainScopeCompletion();
      expect(h.c.frames.single, [cmdGetDefaultFloodScope]);
      expect(query.completed, isTrue);
      expect(query.error, isNull);
      expect(region, '');
    });
  }, timeout: timeout);

  testWidgets('baseline: channel TX deferred for contacts starts after END with original text', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.c.setContactSyncInProgressForTest(true);
      final result = _Result(h.c.sendChannelMessage(_channel, 'deferred text', region: ''));
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(h.c.frames, isEmpty);
      expect(h.c.getChannelMessages(_channel).single.status, ChannelMessageStatus.pending);
      h.c.handleFrameForTest([respCodeEndOfContacts]);
      await tester.pump();
      await h.replyToDefaultScope();
      expect(h.channelTexts, ['deferred text']);
      expect(h.c.getChannelMessages(_channel).single.status, ChannelMessageStatus.sent);
    });
  }, timeout: timeout);

  testWidgets('baseline: deferred flush serializes two messages and ignores overlapping END triggers', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.c.setContactSyncInProgressForTest(true);
      await h.c.sendChannelMessage(_channel, 'first', region: '');
      await h.c.sendChannelMessage(_channel, 'second', region: '');
      final completion = h.c.hold();
      var holdingScope = false;
      h.c.write = (frame) {
        if (frame[0] == cmdSetFloodScope && !holdingScope) {
          holdingScope = true;
          return completion.future;
        }
        return Future<void>.value();
      };
      h.c.handleFrameForTest([respCodeEndOfContacts]);
      await tester.pump();
      await h.replyToDefaultScope();
      expect(holdingScope, isTrue);
      expect(h.channelTexts, isEmpty);
      h.c.handleFrameForTest([respCodeEndOfContacts]);
      await tester.pump();
      expect(h.channelTexts, isEmpty);
      completion.complete();
      await tester.pump(Duration.zero);
      expect(h.channelTexts, ['first', 'second']);
      expect(h.c.frames.where((f) => f[0] == cmdGetDefaultFloodScope), hasLength(1));
    });
  }, timeout: timeout);

  testWidgets('baseline: disconnected END keeps deferred TX for a later connected trigger', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.c.setContactSyncInProgressForTest(true);
      await h.c.sendChannelMessage(_channel, 'deferred text', region: '');
      h.c.connected = false;
      h.c.handleFrameForTest([respCodeEndOfContacts]);
      await tester.pump();
      expect(h.c.frames, isEmpty);
      expect(h.c.getChannelMessages(_channel).single.status, ChannelMessageStatus.pending);
      h.c.connected = true;
      h.c.handleFrameForTest([respCodeEndOfContacts]);
      await tester.pump();
      await h.replyToDefaultScope();
      expect(h.channelTexts, ['deferred text']);
    });
  }, timeout: timeout);
}
