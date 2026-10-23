import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
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
    if (!c.backgroundWorkSnapshot.isClosed) {
      for (final message in c.getPendingContactMessages(_contact.publicKeyHex)) {
        c.cancelPendingContactSend(message.messageId);
      }
      for (final message in c.getPendingChannelMessages(_channel.index)) {
        c.cancelPendingChannelSend(message.messageId);
      }
      c.setChannelMessagesForTest(_channel.index, []);
    }
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
    if (!c.backgroundWorkSnapshot.isClosed) {
      c.resetSyncProgressForTest();
      c.dispose();
    }
    settings.dispose();
  }
}

void _expectWork(_Connector c, {int sends = 0, int retries = 0,
    int writes = 0, int commands = 0}) {
  final snapshot = c.backgroundWorkSnapshot;
  expect(snapshot.countFor(BackgroundWorkKind.radioSend), sends);
  expect(snapshot.countFor(BackgroundWorkKind.retry), retries);
  expect(snapshot.countFor(BackgroundWorkKind.transportWrite), writes);
  expect(snapshot.countFor(BackgroundWorkKind.commandReply), commands);
  expect(snapshot.activeCount, sends + retries + writes + commands);
  expect(snapshot.isBusy, snapshot.activeCount > 0);
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

  testWidgets('hop wait is tracked with Off and an early echo drains before its old timer', (tester) async {
    await _withOutgoing(tester, (h) async {
      await h.prepareHop();
      expect(h.settings.settings.powerSaving.profile, PowerSavingProfile.disabled);
      final loop = h.startHop();
      await tester.pump(const Duration(seconds: 1));
      _expectWork(h.c, retries: 1);
      h.echoTwoHops();
      await tester.pump();
      expect(loop.completed, isTrue);
      expect(loop.error, isNull);
      expect(h.resends, 0);
      _expectWork(h.c);
      await tester.pump(const Duration(seconds: 4));
      _expectWork(h.c);
    });
  }, timeout: timeout);

  testWidgets('echo and disconnect do not release an unfinished resend callback', (tester) async {
    await _withOutgoing(tester, (h) async {
      await h.prepareHop();
      final completion = h.c.hold();
      h.resend = () => completion.future;
      final loop = h.startHop();
      await tester.pump(const Duration(seconds: 5));
      _expectWork(h.c, retries: 1);
      h.echoTwoHops();
      h.c.connected = false;
      await tester.pump();
      expect(loop.completed, isFalse);
      _expectWork(h.c, retries: 1);
      completion.complete();
      await tester.pump();
      _expectWork(h.c, retries: 1);
      await tester.pump(const Duration(seconds: 5));
      expect(loop.completed, isTrue);
      expect(loop.error, isNull);
      _expectWork(h.c);
    });
  }, timeout: timeout);

  testWidgets('parallel hop waits release their own leases', (tester) async {
    await _withOutgoing(tester, (h) async {
      await h.prepareHop();
      h.c.setChannelMessagesForTest(_channel.index, [
        h.hopMessage(), h.hopMessage(id: 'other'),
      ]);
      final completion = h.c.hold();
      h.resend = () => completion.future;
      final first = h.startHop(maxResends: 0);
      final second = h.startHop(id: 'other');
      _expectWork(h.c, retries: 2);
      await tester.pump(const Duration(seconds: 5));
      expect(first.completed, isTrue);
      expect(second.completed, isFalse);
      _expectWork(h.c, retries: 1);
      completion.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(second.completed, isTrue);
      _expectWork(h.c);
    });
  }, timeout: timeout);

  testWidgets('caught resend error drains retry without changing shortfall', (tester) async {
    await _withOutgoing(tester, (h) async {
      await h.prepareHop();
      h.resend = () => Future<void>.error(StateError('synthetic resend failure'));
      final loop = h.startHop();
      _expectWork(h.c, retries: 1);
      await tester.pump(const Duration(seconds: 5));
      expect(loop.completed, isTrue);
      expect(loop.error, isNull);
      expect(h.c.channelHopShortfall('hop'), (hops: 1, required: 2));
      _expectWork(h.c);
    });
  }, timeout: timeout);

  testWidgets('removed message keeps its active callback until the original loop exits', (tester) async {
    await _withOutgoing(tester, (h) async {
      await h.prepareHop();
      final completion = h.c.hold();
      h.resend = () => completion.future;
      final loop = h.startHop();
      await tester.pump(const Duration(seconds: 5));
      h.c.setChannelMessagesForTest(_channel.index, []);
      _expectWork(h.c, retries: 1);
      completion.complete();
      await tester.pump();
      _expectWork(h.c, retries: 1);
      await tester.pump(const Duration(seconds: 5));
      expect(loop.completed, isTrue);
      _expectWork(h.c);
    });
  }, timeout: timeout);

  testWidgets('profile changes keep the same active retry lease', (tester) async {
    await _withOutgoing(tester, (h) async {
      await h.prepareHop();
      final loop = h.startHop(maxResends: 0);
      for (final profile in PowerSavingProfile.values) {
        await h.settings.setPowerSavingProfile(profile);
        await tester.pump();
        _expectWork(h.c, retries: 1);
      }
      await tester.pump(const Duration(seconds: 5));
      expect(loop.completed, isTrue);
      _expectWork(h.c);
    });
  }, timeout: timeout);

  testWidgets('scheduled delay and cancelled drafts create no active lease', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.c.ready = false;
      h.scheduleContact(delay: 2);
      h.scheduleChannel();
      _expectWork(h.c);
      await tester.pump(const Duration(seconds: 3));
      _expectWork(h.c);
      expect(h.c.frames, isEmpty);
      final direct = h.c.getPendingContactMessages(_contact.publicKeyHex).single;
      final channel = h.c.getPendingChannelMessages(_channel.index).single;
      expect(h.c.cancelPendingContactSend(direct.messageId), 'direct draft');
      expect(h.c.cancelPendingChannelSend(channel.messageId), 'channel draft');
      _expectWork(h.c);
    });
  }, timeout: timeout);

  testWidgets('timer commit tracks the send and physical writer after the draft is removed', (tester) async {
    await _withOutgoing(tester, (h) async {
      final completion = h.c.hold();
      h.c.write = (_) => completion.future;
      h.scheduleContact(delay: 1);
      final id = h.c.getPendingContactMessages(_contact.publicKeyHex).single.messageId;
      _expectWork(h.c);
      await tester.pump(const Duration(seconds: 1));
      expect(h.c.frames.single.first, cmdSendTxtMsg);
      expect(h.c.cancelPendingContactSend(id), isNull);
      _expectWork(h.c, sends: 2, writes: 1);
      completion.complete();
      await tester.pump();
      _expectWork(h.c);
    });
  }, timeout: timeout);

  testWidgets('logical write timeout drains commit but leaves the physical writer held', (tester) async {
    await _withOutgoing(tester, (h) async {
      final completion = h.c.hold();
      h.c.write = (_) => completion.future;
      h.scheduleContact(delay: 1);
      await tester.pump(const Duration(seconds: 1));
      _expectWork(h.c, sends: 2, writes: 1);
      await tester.pump(const Duration(seconds: 5));
      _expectWork(h.c, writes: 1);
      completion.complete();
      await tester.pump();
      _expectWork(h.c);
    });
  }, timeout: timeout);

  testWidgets('dispose retains the actual scheduled commit until its writer completes', (tester) async {
    await _withOutgoing(tester, (h) async {
      final completion = h.c.hold();
      h.c.write = (_) => completion.future;
      h.scheduleContact(delay: 1);
      await tester.pump(const Duration(seconds: 1));
      h.c.connected = false;
      h.c.ready = false;
      h.c.dispose();
      expect(h.c.backgroundWorkSnapshot.isClosed, isTrue);
      _expectWork(h.c, sends: 2, writes: 1);
      completion.complete();
      await tester.pump();
      _expectWork(h.c);
    });
  }, timeout: timeout);

  testWidgets('resume and nested channel commit are held through scope preparation', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.c.installChannel();
      await tester.pump();
      final completion = h.c.hold();
      h.c.write = (_) => h.c.frames.length == 1
          ? completion.future : Future<void>.value();
      h.scheduleChannel();
      _expectWork(h.c);
      final first = _Result(h.c.resumePendingOutgoingMessages());
      await tester.pump();
      _expectWork(h.c, sends: 3, writes: 1, commands: 1);
      final second = _Result(h.c.resumePendingOutgoingMessages());
      await tester.pump();
      expect(second.completed, isTrue);
      expect(first.completed, isFalse);
      expect(h.c.frames, hasLength(1));
      _expectWork(h.c, sends: 3, writes: 1, commands: 1);
      completion.complete();
      await tester.pump();
      expect(first.completed, isTrue);
      expect(first.error, isNull);
      expect(h.channelTexts, ['scheduled channel']);
      _expectWork(h.c);
    });
  }, timeout: timeout);

  testWidgets('missing channel early return leaves no resume or commit lease', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.scheduleChannel();
      final result = _Result(h.c.resumePendingOutgoingMessages());
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(h.c.frames, isEmpty);
      expect(h.c.getChannelMessages(_channel).single.status, ChannelMessageStatus.failed);
      _expectWork(h.c);
    });
  }, timeout: timeout);

  testWidgets('deferred queue is passive until END and flush holds its scope query', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.c.setContactSyncInProgressForTest(true);
      await h.c.sendChannelMessage(_channel, 'deferred text', region: '');
      await tester.pump();
      _expectWork(h.c);
      expect(h.c.frames, isEmpty);
      h.c.handleFrameForTest([respCodeEndOfContacts]);
      await tester.pump();
      _expectWork(h.c, sends: 2);
      expect(h.c.frames.single, [cmdGetDefaultFloodScope]);
      await h.replyToDefaultScope();
      expect(h.channelTexts, ['deferred text']);
      expect(h.c.getChannelMessages(_channel).single.status, ChannelMessageStatus.sent);
      _expectWork(h.c);
    });
  }, timeout: timeout);

  testWidgets('overlapping END adds no persistent flush and a held writer preserves order', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.c.setContactSyncInProgressForTest(true);
      await h.c.sendChannelMessage(_channel, 'first', region: '');
      await h.c.sendChannelMessage(_channel, 'second', region: '');
      final completion = h.c.hold();
      var holding = false;
      h.c.write = (frame) {
        if (frame[0] == cmdSetFloodScope && !holding) {
          holding = true;
          return completion.future;
        }
        return Future<void>.value();
      };
      h.c.handleFrameForTest([respCodeEndOfContacts]);
      await tester.pump();
      await h.replyToDefaultScope();
      expect(holding, isTrue);
      _expectWork(h.c, sends: 2, writes: 1, commands: 1);
      h.c.handleFrameForTest([respCodeEndOfContacts]);
      await tester.pump();
      _expectWork(h.c, sends: 2, writes: 1, commands: 1);
      expect(h.channelTexts, isEmpty);
      completion.complete();
      await tester.pump(Duration.zero);
      expect(h.channelTexts, ['first', 'second']);
      _expectWork(h.c);
    });
  }, timeout: timeout);

  testWidgets('disconnected deferred trigger stays passive and a connected trigger drains', (tester) async {
    await _withOutgoing(tester, (h) async {
      h.c.setContactSyncInProgressForTest(true);
      await h.c.sendChannelMessage(_channel, 'deferred text', region: '');
      h.c.connected = false;
      h.c.handleFrameForTest([respCodeEndOfContacts]);
      await tester.pump();
      _expectWork(h.c);
      expect(h.c.frames, isEmpty);
      h.c.connected = true;
      h.c.handleFrameForTest([respCodeEndOfContacts]);
      await tester.pump();
      _expectWork(h.c, sends: 2);
      await h.replyToDefaultScope();
      expect(h.channelTexts, ['deferred text']);
      _expectWork(h.c);
    });
  }, timeout: timeout);
}

