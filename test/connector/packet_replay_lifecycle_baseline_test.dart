import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' show Endian;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
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

// Настоящие replay-циклы, receive/parser/decrypt и sendFrame. Нода не привязана
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
  final frames = <List<int>>[];
  final held = <Completer<void>>[];
  final translated = <String>[];
  Completer<void>? translation;

  _Connector() {
    setFrameWriterForTest((frame) async => frames.add(List<int>.of(frame)));
  }

  @override
  bool get isConnected => connected;

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
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
  }
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

  testWidgets('baseline: empty replay paths complete without queue requests', (tester) async {
    await _withReplay(tester, (c) async {
      await c.replayUnknownSenderMessagesForTest();
      await c.replayDeferredContactMessagesForTest();
      c.deferContactMessagesForTest([]);
      await c.replayDeferredContactMessagesForTest();
      expect(c.packetReplayStateForTest,
          (unknown: 0, deferred: 0, replaying: false, deferring: false));
      expect(c.frames, isEmpty);
    });
  });

  testWidgets('baseline: onlyResolvable keeps unknown frames and replays a known sender once',
      (tester) async {
    await _withReplay(tester, (c) async {
      final alice = _contact(0x41);
      final bob = _contact(0x42);
      c.fixture([alice]);
      final load = c.holdLoad(alice);
      c.holdUnknownSenderMessageForTest(_direct(bob, 'held'));
      c.holdUnknownSenderMessageForTest(_direct(alice, 'ready'));
      final replay = _Result(c.replayUnknownSenderMessagesForTest(onlyResolvable: true));
      await tester.pump();
      expect(replay.completed, isFalse);
      expect(c.packetReplayStateForTest.unknown, 1);
      await c.replayUnknownSenderMessagesForTest(onlyResolvable: true);
      load.complete();
      await tester.pump();
      expect(replay.completed, isTrue);
      expect(replay.error, isNull);
      expect(c.getLoadedMessages(alice).map((m) => m.text), ['ready']);
      expect(c.packetReplayStateForTest.unknown, 1);
      expect(c.syncRequests, 0);
    });
  });

  testWidgets('baseline: full unknown replay drops unresolved frames and awaits FIFO loads',
      (tester) async {
    await _withReplay(tester, (c) async {
      final alice = _contact(0x41);
      final bob = _contact(0x42);
      c.fixture([alice, bob]);
      final first = c.holdLoad(alice);
      final second = c.holdLoad(bob);
      c.holdUnknownSenderMessageForTest(_direct(_contact(0x43), 'unresolved'));
      c.holdUnknownSenderMessageForTest(_direct(alice, 'first'));
      c.holdUnknownSenderMessageForTest(_direct(bob, 'second'));
      final replay = _Result(c.replayUnknownSenderMessagesForTest());
      await tester.pump();
      expect(c.packetReplayStateForTest.unknown, 0);
      expect(c.getLoadedMessages(bob), isEmpty);
      first.complete();
      await tester.pump();
      expect(c.getLoadedMessages(alice).single.text, 'first');
      expect(replay.completed, isFalse);
      second.complete();
      await tester.pump();
      expect(replay.completed, isTrue);
      expect(replay.error, isNull);
      expect(c.getLoadedMessages(bob).single.text, 'second');
      await c.replayUnknownSenderMessagesForTest();
      expect(c.getLoadedMessages(alice), hasLength(1));
      expect(c.getLoadedMessages(bob), hasLength(1));
      expect(c.syncRequests, 0);
    });
  });

  testWidgets('baseline: unknown replay failure propagates after selected frames leave buffer',
      (tester) async {
    await _withReplay(tester, (c) async {
      final alice = _contact(0x41);
      c.fixture([alice]);
      final load = c.holdLoad(alice);
      c.holdUnknownSenderMessageForTest(_direct(alice, 'not stored'));
      c.holdUnknownSenderMessageForTest(_direct(alice, 'not reached', timestamp: _timestamp + 1));
      final replay = _Result(c.replayUnknownSenderMessagesForTest());
      final failure = StateError('synthetic load failure');
      load.completeError(failure);
      await tester.pump();
      expect(replay.error, same(failure));
      expect(c.packetReplayStateForTest.unknown, 0);
      expect(c.getLoadedMessages(alice), isEmpty);
      expect(c.syncRequests, 0);
    });
  });

  testWidgets('baseline: deferred replay serializes loads, ignores reentry and hands off once',
      (tester) async {
    await _withReplay(tester, (c) async {
      final alice = _contact(0x41);
      final bob = _contact(0x42);
      c.fixture([alice, bob]);
      final first = c.holdLoad(alice);
      final second = c.holdLoad(bob);
      c.deferContactMessagesForTest([
        _direct(alice, 'first', timestamp: _timestamp + 1),
        _direct(bob, 'second'),
      ]);
      final replay = _Result(c.replayDeferredContactMessagesForTest());
      await tester.pump();
      expect(c.packetReplayStateForTest.deferred, 1);
      expect(c.packetReplayStateForTest.replaying, isTrue);
      await c.replayDeferredContactMessagesForTest();
      await c.syncQueuedMessages(force: true);
      expect(c.syncRequests, 0);
      first.complete();
      await tester.pump();
      expect(c.getLoadedMessages(alice).single.text, 'first');
      expect(c.getLoadedMessages(bob), isEmpty);
      expect(replay.completed, isFalse);
      expect(c.syncRequests, 0);
      second.complete();
      await tester.pump();
      expect(replay.completed, isTrue);
      expect(replay.error, isNull);
      expect(c.getLoadedMessages(bob).single.text, 'second');
      expect(c.getLoadedMessages(bob).single.receivedAt!.isAfter(
          c.getLoadedMessages(alice).single.receivedAt!), isTrue);
      expect(c.packetReplayStateForTest,
          (unknown: 0, deferred: 0, replaying: false, deferring: false));
      expect(c.syncRequests, 1);
      c.handleFrameForTest([respCodeNoMoreMessages]);
    });
  });

  testWidgets('baseline: empty deferred replay releases a pending explicit sync', (tester) async {
    await _withReplay(tester, (c) async {
      final alice = _contact(0x41);
      c.fixture([alice]);
      final load = c.holdLoad(alice);
      c.deferContactMessagesForTest([_direct(alice, 'first')]);
      final replay = _Result(c.replayDeferredContactMessagesForTest());
      await c.syncQueuedMessages(force: true);
      c.connected = false;
      load.complete();
      await tester.pump();
      expect(replay.completed, isTrue);
      expect(c.syncRequests, 0);
      c.connected = true;
      c.deferContactMessagesForTest([]);
      await c.replayDeferredContactMessagesForTest();
      await tester.pump();
      expect(c.syncRequests, 1);
      c.handleFrameForTest([respCodeNoMoreMessages]);
    });
  });

  testWidgets('baseline: deferred failure clears flags but leaves unprocessed frames',
      (tester) async {
    await _withReplay(tester, (c) async {
      final alice = _contact(0x41);
      c.fixture([alice]);
      final load = c.holdLoad(alice);
      c.deferContactMessagesForTest([
        _direct(alice, 'failed'), _direct(alice, 'remaining', timestamp: _timestamp + 1),
      ]);
      final replay = _Result(c.replayDeferredContactMessagesForTest());
      await c.syncQueuedMessages(force: true);
      final failure = StateError('synthetic deferred load failure');
      load.completeError(failure);
      await tester.pump();
      expect(replay.error, same(failure));
      expect(c.packetReplayStateForTest,
          (unknown: 0, deferred: 1, replaying: false, deferring: false));
      expect(c.syncRequests, 0);
      expect(c.getLoadedMessages(alice), isEmpty);
    });
  });

  testWidgets('baseline: RX log returns to dispatch while its translation is still pending',
      (tester) async {
    await _withReplay(tester, (c) async {
      c.translation = c.hold();
      c.handleFrameForTest(_heard('radio message'));
      await tester.pump();
      expect(c.translated, ['radio message']);
      final message = c.getLoadedChannelMessages(_channel).single;
      expect(message.text, 'radio message');
      expect(message.senderName, 'Alice');
      expect(message.pathBytes, orderedEquals([0x22]));
      expect(message.snr, 8);
      expect(message.rssi, -70);
      expect(c.translation!.isCompleted, isFalse);
      expect(c.syncRequests, 0);
      c.translation!.complete();
      await tester.pump();
      expect(c.getLoadedChannelMessages(_channel), hasLength(1));
      expect(binding.takeException(), isNull);
    });
  });

  for (final fails in [false, true]) {
    testWidgets('baseline: direct RX echo awaits history load and catches failure=$fails',
        (tester) async {
      await _withReplay(tester, (c) async {
        final alice = _contact(0x41);
        c.fixture([alice]);
        // Все байты созданы здесь; реальные ключи/лицензии не читаются.
        final scalar = Uint8List.fromList(List<int>.generate(32, (i) => i + 17));
        c.setDirectEchoKeyForTest(scalar);
        final settings = AppSettingsService();
        await settings.updateSettings(settings.settings.copyWith(
          directEchoRecovery: true, notificationsEnabled: false,
        ));
        c.attachAppSettingsServiceForTest(settings);
        try {
          final load = c.holdLoad(alice);
          // Проверяем RX; отдельная отправка ACK здесь не запускается.
          c.connected = false;
          c.handleFrameForTest(_heardDirect(alice, scalar));
          await tester.pump();
          expect(c.getLoadedMessages(alice), isEmpty);
          if (fails) {
            load.completeError(StateError('synthetic direct echo load failure'));
          } else {
            load.complete();
          }
          await tester.pump();
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

  testWidgets('baseline: malformed or foreign RX packets create no message or queue request',
      (tester) async {
    await _withReplay(tester, (c) async {
      c.handleFrameForTest([pushCodeLogRxData]);
      c.handleFrameForTest([pushCodeLogRxData, 0, 0, 0xFF]);
      c.handleFrameForTest(_heard('foreign', key: Uint8List(16)));
      await tester.pump();
      expect(c.getLoadedChannelMessages(_channel), isEmpty);
      expect(c.translated, isEmpty);
      expect(c.frames, isEmpty);
    });
  });
}
