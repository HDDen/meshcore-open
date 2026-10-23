import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' show Endian;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/helpers/channel_echo_recovery.dart';
import 'package:meshcore_open/helpers/direct_echo_crypto.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/translation_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Отдельные регрессии учёта; принятый baseline не меняется. Нода не привязана
// к stores: запись на диск пропускается штатным guard пустого scope. Загрузка
// истории и перевод управляемые; это lifecycle baseline, не проверка БД/сети.
class _NoDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('synthetic replay without a directory');
}

const _timestamp = 1700000000;
final _selfKey = Uint8List.fromList(List<int>.filled(32, 0x11));
final _psk = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
final _channel = Channel(index: 0, name: 'Synthetic', psk: _psk);

Contact _contact(int seed) => Contact(
  publicKey: Uint8List.fromList(List<int>.filled(32, seed)),
  name: 'Synthetic $seed',
  type: advTypeChat,
  pathLength: -1,
  path: Uint8List(0),
  lastSeen: DateTime.fromMillisecondsSinceEpoch(_timestamp * 1000),
);

Uint8List _direct(Contact contact, String text, {int timestamp = _timestamp}) {
  final time = ByteData(4)..setUint32(0, timestamp, Endian.little);
  return Uint8List.fromList([
    respCodeContactMsgRecvV3, 32, 0, 0,
    ...contact.publicKey.take(6), 0xFF, txtTypePlain,
    ...time.buffer.asUint8List(), ...utf8.encode(text), 0,
  ]);
}

Uint8List _heard(String text, {Uint8List? key}) {
  final secret = key ?? _psk;
  final plaintext = ChannelEchoRecovery.groupTextPlaintext(
    timestampSeconds: _timestamp,
    senderName: 'Alice',
    textBytes: Uint8List.fromList(utf8.encode(text)),
  );
  return Uint8List.fromList([
    pushCodeLogRxData, 32, (-70) & 0xFF,
    (0x05 << 2) | 0x01, 1, 0x22,
    crypto.sha256.convert(secret).bytes.first,
    ...ChannelEchoRecovery.encryptedPayloadFor(secret, plaintext),
  ]);
}

Uint8List _heardDirect(Contact sender, Uint8List scalar) {
  final time = ByteData(4)..setUint32(0, _timestamp, Endian.little);
  final plaintext = Uint8List.fromList([
    ...time.buffer.asUint8List(), txtTypePlain << 2,
    ...utf8.encode('direct echo'), 0,
  ]);
  return Uint8List.fromList([
    pushCodeLogRxData, 32, (-70) & 0xFF,
    (payloadTypeTXTMSG << 2) | 0x02, 1, 0x20,
    _selfKey.first, sender.publicKey.first,
    ...ChannelEchoRecovery.encryptedPayloadFor(
      DirectEchoCrypto.sharedSecret(scalar, sender.publicKey), plaintext),
  ]);
}

class _Connector extends MeshCoreConnector {
  bool connected = true;
  bool disposed = false;
  BackgroundWorkSnapshot? workAtSync;
  final frames = <List<int>>[];
  final held = <Completer<void>>[];
  final translated = <String>[];
  Completer<void>? translation;

  _Connector() {
    setFrameWriterForTest((frame) async {
      frames.add(List<int>.of(frame));
      if (frame.first == cmdSyncNextMessage) workAtSync = backgroundWorkSnapshot;
    });
  }

  @override
  bool get isConnected => connected;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  Completer<void> hold() {
    final gate = Completer<void>();
    held.add(gate);
    return gate;
  }

  void fixture(List<Contact> contacts) => setPacketReplayFixtureForTest(
    selfKey: _selfKey, contacts: contacts, channels: [_channel],
  );

  Completer<void> holdLoad(Contact contact) {
    final gate = hold();
    setConversationLoadForTest(contact.publicKeyHex, gate.future);
    return gate;
  }

  int get syncRequests => frames.where((f) => f.first == cmdSyncNextMessage).length;

  @override
  Future<TranslationResult?> translateChannelMessage(
    int channelIndex, ChannelMessage message, {bool manualTranslation = false}
  ) async {
    translated.add(message.text);
    await translation?.future;
    return null;
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

Future<void> _withReplay(
  WidgetTester tester, Future<void> Function(_Connector c) check,
) async {
  final c = _Connector()..fixture([]);
  try {
    await check(c);
  } finally {
    c.connected = false;
    for (final gate in c.held) {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.pump();
    c.resetSyncProgressForTest();
    if (!c.disposed) c.dispose();
    await tester.pump(const Duration(seconds: 5));
  }
}

void _expectWork(_Connector c, {
  int replay = 0, int receive = 0, int requests = 0, bool closed = false,
}) {
  final snapshot = c.backgroundWorkSnapshot;
  expect(snapshot.countFor(BackgroundWorkKind.messageReplay), replay);
  expect(snapshot.countFor(BackgroundWorkKind.radioReceive), receive);
  expect(snapshot.countFor(BackgroundWorkKind.queuedMessageRequest), requests);
  expect(snapshot.activeCount, replay + receive + requests);
  expect(snapshot.isClosed, closed);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform originalPathProvider;

  setUp(() async {
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDirectory();
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    PrefsManager.reset();
  });

  testWidgets('unknown replay holds across consecutive loads and preserves FIFO', (tester) async {
    await _withReplay(tester, (c) async {
      final alice = _contact(0x41);
      final bob = _contact(0x42);
      c.fixture([alice, bob]);
      final first = c.holdLoad(alice);
      final second = c.holdLoad(bob);
      c.holdUnknownSenderMessageForTest(_direct(alice, 'first'));
      c.holdUnknownSenderMessageForTest(_direct(bob, 'second'));
      final replay = _Result(c.replayUnknownSenderMessagesForTest());
      _expectWork(c, replay: 1);
      final before = c.backgroundWorkSnapshot;
      expect(c.packetReplayStateForTest.unknown, 0);
      first.complete();
      await tester.pump();
      expect(c.getLoadedMessages(alice).single.text, 'first');
      expect(c.getLoadedMessages(bob), isEmpty);
      expect(replay.completed, isFalse);
      _expectWork(c, replay: 1);
      second.complete();
      await tester.pump();
      expect(replay.completed, isTrue);
      expect(replay.error, isNull);
      _expectWork(c);
      expect(before.countFor(BackgroundWorkKind.messageReplay), 1);
      expect(c.getLoadedMessages(bob).single.text, 'second');
    });
  });

  testWidgets('concurrent unknown replay batches release only their own work', (tester) async {
    await _withReplay(tester, (c) async {
      final alice = _contact(0x41);
      final bob = _contact(0x42);
      c.fixture([alice, bob]);
      final first = c.holdLoad(alice);
      final second = c.holdLoad(bob);
      c.holdUnknownSenderMessageForTest(_direct(alice, 'first batch'));
      final a = _Result(c.replayUnknownSenderMessagesForTest());
      c.holdUnknownSenderMessageForTest(_direct(bob, 'second batch'));
      final b = _Result(c.replayUnknownSenderMessagesForTest());
      _expectWork(c, replay: 2);
      first.complete();
      await tester.pump();
      expect(a.completed, isTrue);
      expect(b.completed, isFalse);
      _expectWork(c, replay: 1);
      second.complete();
      await tester.pump();
      expect(b.completed, isTrue);
      _expectWork(c);
      expect(c.getLoadedMessages(alice), hasLength(1));
      expect(c.getLoadedMessages(bob), hasLength(1));
    });
  });

  testWidgets('passive unknown buffer and empty replay do not keep work busy', (tester) async {
    await _withReplay(tester, (c) async {
      c.holdUnknownSenderMessageForTest(_direct(_contact(0x41), 'held'));
      _expectWork(c);
      await c.replayUnknownSenderMessagesForTest(onlyResolvable: true);
      await c.replayDeferredContactMessagesForTest();
      _expectWork(c);
      expect(c.packetReplayStateForTest.unknown, 1);
      await c.replayUnknownSenderMessagesForTest();
      _expectWork(c);
      expect(c.packetReplayStateForTest.unknown, 0);
    });
  });

  testWidgets('unknown replay propagates load error and releases its work', (tester) async {
    await _withReplay(tester, (c) async {
      final alice = _contact(0x41);
      c.fixture([alice]);
      final load = c.holdLoad(alice);
      c.holdUnknownSenderMessageForTest(_direct(alice, 'failed'));
      final replay = _Result(c.replayUnknownSenderMessagesForTest());
      _expectWork(c, replay: 1);
      final failure = StateError('synthetic replay failure');
      load.completeError(failure);
      await tester.pump();
      expect(replay.error, same(failure));
      _expectWork(c);
      expect(c.getLoadedMessages(alice), isEmpty);
    });
  });

  testWidgets('deferred replay retains work on reentry and hands off before releasing', (tester) async {
    await _withReplay(tester, (c) async {
      final alice = _contact(0x41);
      final bob = _contact(0x42);
      c.fixture([alice, bob]);
      final first = c.holdLoad(alice);
      final second = c.holdLoad(bob);
      c.deferContactMessagesForTest([
        _direct(alice, 'first', timestamp: _timestamp + 1), _direct(bob, 'second'),
      ]);
      final replay = _Result(c.replayDeferredContactMessagesForTest());
      _expectWork(c, replay: 1);
      await c.replayDeferredContactMessagesForTest();
      _expectWork(c, replay: 1);
      await c.syncQueuedMessages(force: true);
      expect(c.syncRequests, 0);
      first.complete();
      await tester.pump();
      _expectWork(c, replay: 1);
      second.complete();
      await tester.pump();
      expect(replay.completed, isTrue);
      expect(replay.error, isNull);
      _expectWork(c, requests: 1);
      expect(c.syncRequests, 1);
      final atWrite = c.workAtSync!;
      expect(atWrite.countFor(BackgroundWorkKind.messageReplay), 1);
      expect(atWrite.countFor(BackgroundWorkKind.queuedMessageRequest), 1);
      expect(atWrite.countFor(BackgroundWorkKind.transportWrite), 1);
      c.handleFrameForTest([respCodeNoMoreMessages]);
      await tester.pump();
      _expectWork(c);
    });
  });

  testWidgets('deferred failure releases work without inventing a queue handoff', (tester) async {
    await _withReplay(tester, (c) async {
      final alice = _contact(0x41);
      c.fixture([alice]);
      final load = c.holdLoad(alice);
      c.deferContactMessagesForTest([
        _direct(alice, 'failed'), _direct(alice, 'remaining', timestamp: _timestamp + 1),
      ]);
      final replay = _Result(c.replayDeferredContactMessagesForTest());
      await c.syncQueuedMessages(force: true);
      _expectWork(c, replay: 1);
      final failure = StateError('synthetic deferred failure');
      load.completeError(failure);
      await tester.pump();
      expect(replay.error, same(failure));
      _expectWork(c);
      expect(c.packetReplayStateForTest.deferred, 1);
      expect(c.packetReplayStateForTest.replaying, isFalse);
      expect(c.syncRequests, 0);
    });
  });

  testWidgets('sync reset cannot release a replay already waiting for history', (tester) async {
    await _withReplay(tester, (c) async {
      final alice = _contact(0x41);
      c.fixture([alice]);
      final load = c.holdLoad(alice);
      c.holdUnknownSenderMessageForTest(_direct(alice, 'pending'));
      final replay = _Result(c.replayUnknownSenderMessagesForTest());
      c.resetSyncProgressForTest();
      _expectWork(c, replay: 1);
      load.complete();
      await tester.pump();
      expect(replay.completed, isTrue);
      _expectWork(c);
    });
  });

  for (final deferred in [false, true]) {
    testWidgets('dispose retains actual replay, deferred=$deferred', (tester) async {
      await _withReplay(tester, (c) async {
        final alice = _contact(0x41);
        c.fixture([alice]);
        final load = c.holdLoad(alice);
        if (deferred) {
          c.deferContactMessagesForTest([_direct(alice, 'pending')]);
        } else {
          c.holdUnknownSenderMessageForTest(_direct(alice, 'pending'));
        }
        final replay = _Result(deferred
            ? c.replayDeferredContactMessagesForTest()
            : c.replayUnknownSenderMessagesForTest());
        c.dispose();
        _expectWork(c, replay: 1, closed: true);
        final revision = c.backgroundWorkSnapshot.revision;
        await c.replayDeferredContactMessagesForTest();
        expect(c.backgroundWorkSnapshot.revision, revision);
        load.complete();
        await tester.pump();
        expect(replay.completed, isTrue);
        expect(replay.error, isNull);
        _expectWork(c, closed: true);
      });
    });
  }

  testWidgets('caller timeout does not cancel the original replay work', (tester) async {
    await _withReplay(tester, (c) async {
      final alice = _contact(0x41);
      c.fixture([alice]);
      final load = c.holdLoad(alice);
      c.holdUnknownSenderMessageForTest(_direct(alice, 'pending'));
      final original = c.replayUnknownSenderMessagesForTest();
      final replay = _Result(original);
      final timed = _Result(original.timeout(const Duration(seconds: 1)));
      await tester.pump(const Duration(seconds: 1));
      expect(timed.error, isA<TimeoutException>());
      expect(replay.completed, isFalse);
      _expectWork(c, replay: 1);
      load.complete();
      await tester.pump();
      expect(replay.completed, isTrue);
      _expectWork(c);
    });
  });

  for (final fails in [false, true]) {
    testWidgets('channel RX holds its translation and drains, failure=$fails', (tester) async {
      await _withReplay(tester, (c) async {
        final translation = c.hold();
        c.translation = translation;
        c.handleFrameForTest(_heard('radio message'));
        _expectWork(c, receive: 1);
        await tester.pump();
        expect(c.translated, ['radio message']);
        expect(c.getLoadedChannelMessages(_channel), hasLength(1));
        _expectWork(c, receive: 1);
        if (fails) {
          translation.completeError(StateError('synthetic translation failure'));
        } else {
          translation.complete();
        }
        await tester.pump();
        _expectWork(c);
        expect(binding.takeException(), isNull);
      });
    });
  }

  testWidgets('dispose retains channel RX until its awaited translation ends', (tester) async {
    await _withReplay(tester, (c) async {
      final translation = c.hold();
      c.translation = translation;
      c.handleFrameForTest(_heard('radio message'));
      await tester.pump();
      _expectWork(c, receive: 1);
      c.dispose();
      _expectWork(c, receive: 1, closed: true);
      translation.complete();
      await tester.pump();
      _expectWork(c, closed: true);
      expect(binding.takeException(), isNull);
    });
  });

  for (final fails in [false, true]) {
    testWidgets('direct RX holds the original decrypt/receive path, failure=$fails', (tester) async {
      await _withReplay(tester, (c) async {
        final alice = _contact(0x41);
        c.fixture([alice]);
        final scalar = Uint8List.fromList(List<int>.generate(32, (i) => i + 17));
        c.setDirectEchoKeyForTest(scalar);
        final settings = AppSettingsService();
        await settings.updateSettings(settings.settings.copyWith(
          directEchoRecovery: true, notificationsEnabled: false,
        ));
        c.attachAppSettingsServiceForTest(settings);
        try {
          final load = c.holdLoad(alice);
          c.connected = false;
          c.handleFrameForTest(_heardDirect(alice, scalar));
          await tester.pump();
          _expectWork(c, receive: 1);
          expect(c.getLoadedMessages(alice), isEmpty);
          if (fails) {
            load.completeError(StateError('synthetic direct load failure'));
          } else {
            load.complete();
          }
          await tester.pump();
          _expectWork(c);
          expect(c.getLoadedMessages(alice).map((m) => m.text),
              fails ? isEmpty : orderedEquals(['direct echo']));
          expect(c.frames, isEmpty);
          expect(binding.takeException(), isNull);
        } finally {
          settings.dispose();
        }
      });
    });
  }

  testWidgets('ignored and malformed RX do not retain a passive lease', (tester) async {
    await _withReplay(tester, (c) async {
      c.handleFrameForTest([pushCodeLogRxData]);
      c.handleFrameForTest([pushCodeLogRxData, 0, 0, 0xFF]);
      c.handleFrameForTest(_heard('foreign', key: Uint8List(16)));
      await tester.pump();
      _expectWork(c);
      expect(c.frames, isEmpty);
      expect(c.getLoadedChannelMessages(_channel), isEmpty);
    });
  });
}
