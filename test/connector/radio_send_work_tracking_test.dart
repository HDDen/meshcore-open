import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic preferences without a directory');
  }
}

final _contact = Contact(
  publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
  name: 'synthetic contact',
  type: advTypeChat,
  pathLength: -1,
  path: Uint8List(0),
  lastSeen: DateTime.fromMillisecondsSinceEpoch(1700000000000),
);
final _channel = Channel(index: 0, name: 'synthetic', psk: Uint8List(16));

// Настоящие sendMessage/sendChannelMessage/sendFrame и владелец polling.
// Готовность сессии синтетическая, нода/БД не привязаны; async preparer direct
// можно удержать. Подпись, содержимое контейнеров и radio delivery не проверяем.
class _SendConnector extends MeshCoreConnector {
  bool connected = true;
  bool ready = true;
  bool offline = false;
  bool acknowledge = false;
  int preparations = 0;
  final frames = <List<int>>[];
  final activeAtWrite = <bool>[];
  final workAtWrite = <BackgroundWorkSnapshot>[];
  bool Function(Uint8List)? allowAck;
  final heldPreparations = <Completer<String>>[];
  final heldWrites = <Completer<void>>[];
  Future<String> Function(String)? prepare;
  Future<void> Function(Uint8List)? write;

  _SendConnector() {
    setFrameWriterForTest((frame) {
      frames.add(List<int>.of(frame));
      activeAtWrite.add(hasPendingRadioStatsWork);
      workAtWrite.add(backgroundWorkSnapshot);
      if (acknowledge && (allowAck?.call(frame) ?? true)) {
        handleFrameForTest([respCodeOk]);
      }
      return write?.call(frame) ?? Future<void>.value();
    });
  }

  @override
  bool get isConnected => connected;
  @override
  bool get isSessionReady => ready;
  @override
  bool get isOfflineMode => offline;

  @override
  Future<String> prepareContactOutboundTextAsync(
    Contact contact,
    String text, {
    String? replyAuthorName,
    int? replyTimestamp,
    String? replyToText,
    String? replyToMessageId,
  }) {
    preparations++;
    return prepare?.call(text) ?? super.prepareContactOutboundTextAsync(
      contact,
      text,
      replyAuthorName: replyAuthorName,
      replyTimestamp: replyTimestamp,
      replyToText: replyToText,
      replyToMessageId: replyToMessageId,
    );
  }

  Completer<String> holdPreparation() {
    final completion = Completer<String>();
    heldPreparations.add(completion);
    return completion;
  }

  Completer<void> holdWrite() {
    final completion = Completer<void>();
    heldWrites.add(completion);
    return completion;
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

Future<void> _withSend(
  WidgetTester tester,
  Future<void> Function(_SendConnector c) check,
) async {
  final c = _SendConnector();
  try {
    await check(c);
  } finally {
    c.connected = false;
    for (final completion in c.heldPreparations) {
      if (!completion.isCompleted) {
        completion.complete('synthetic cleanup');
      }
    }
    for (final completion in c.heldWrites) {
      if (!completion.isCompleted) {
        completion.complete();
      }
    }
    await tester.pump();
    if (!c.backgroundWorkSnapshot.isClosed) {
      c.resetSyncProgressForTest();
      c.dispose();
    }
    await tester.pump(const Duration(seconds: 5));
  }
}

void _expectWork(
  _SendConnector c, {
  int sends = 0,
  int writes = 0,
  int commands = 0,
}) {
  final snapshot = c.backgroundWorkSnapshot;
  expect(snapshot.countFor(BackgroundWorkKind.radioSend), sends);
  expect(snapshot.countFor(BackgroundWorkKind.transportWrite), writes);
  expect(snapshot.countFor(BackgroundWorkKind.commandReply), commands);
  expect(snapshot.activeCount, sends + writes + commands);
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

  testWidgets('preparation is held before any writer and its completed send drains', (tester) async {
    await _withSend(tester, (c) async {
      final preparation = c.holdPreparation();
      c.prepare = (_) => preparation.future;
      final result = _Result(c.sendMessage(_contact, 'synthetic message'));
      await tester.pump();
      _expectWork(c, sends: 1);
      expect(c.frames, isEmpty);
      preparation.complete('synthetic prepared message');
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.workAtWrite, hasLength(1));
      expect(c.workAtWrite.single.countFor(BackgroundWorkKind.radioSend), 1);
      expect(c.workAtWrite.single.countFor(BackgroundWorkKind.transportWrite), 1);
      expect(c.activeAtWrite, [true]);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('overlapping preparations own separate send leases', (tester) async {
    await _withSend(tester, (c) async {
      final first = c.holdPreparation();
      final second = c.holdPreparation();
      c.prepare = (text) => text == 'first' ? first.future : second.future;
      final a = _Result(c.sendMessage(_contact, 'first'));
      final b = _Result(c.sendMessage(_contact, 'second'));
      await tester.pump();
      _expectWork(c, sends: 2);
      first.complete('first');
      await tester.pump();
      _expectWork(c, sends: 1);
      expect(a.completed, isTrue);
      expect(b.completed, isFalse);
      second.complete('second');
      await tester.pump();
      _expectWork(c);
      expect(a.error, isNull);
      expect(b.error, isNull);
      expect(b.completed, isTrue);
    });
  }, timeout: timeout);

  testWidgets('preparation failure releases its send and preserves the error', (tester) async {
    await _withSend(tester, (c) async {
      final preparation = c.holdPreparation();
      c.prepare = (_) => preparation.future;
      final failure = StateError('synthetic preparation failure');
      final result = _Result(c.sendMessage(_contact, 'synthetic message'));
      await tester.pump();
      _expectWork(c, sends: 1);
      preparation.completeError(failure);
      await tester.pump();
      expect(result.error, same(failure));
      expect(c.frames, isEmpty);
      expect(c.hasPendingRadioStatsWork, isFalse);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('caller timeout leaves the original send held until preparation completes', (tester) async {
    await _withSend(tester, (c) async {
      final preparation = c.holdPreparation();
      c.prepare = (_) => preparation.future;
      final operation = c.sendMessage(_contact, 'synthetic message');
      final caller = _Result(operation.timeout(const Duration(seconds: 1)));
      await tester.pump(const Duration(seconds: 1));
      expect(caller.error, isA<TimeoutException>());
      _expectWork(c, sends: 1);
      expect(c.frames, isEmpty);
      preparation.complete('synthetic message');
      await tester.pump();
      _expectWork(c);
      expect(c.frames, hasLength(1));
    });
  }, timeout: timeout);

  testWidgets('disconnect during preparation releases without a writer', (tester) async {
    await _withSend(tester, (c) async {
      final preparation = c.holdPreparation();
      c.prepare = (_) => preparation.future;
      final result = _Result(c.sendMessage(_contact, 'synthetic message'));
      await tester.pump();
      _expectWork(c, sends: 1);
      c.connected = false;
      preparation.complete('synthetic message');
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.frames, isEmpty);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('empty offline and unready retries leave no active send', (tester) async {
    await _withSend(tester, (c) async {
      await c.sendMessage(_contact, '');
      await c.sendChannelMessage(_channel, '', region: '');
      _expectWork(c);
      c.offline = true;
      await c.sendMessage(_contact, 'synthetic message');
      await c.sendChannelMessage(_channel, 'synthetic message', region: '');
      _expectWork(c);
      c.offline = false;
      c.ready = false;
      await c.sendMessage(_contact, 'synthetic message', pendingMessageId: 'direct');
      await c.sendChannelMessage(
        _channel, 'synthetic message', pendingMessageId: 'channel', region: '',
      );
      expect(c.preparations, 0);
      expect(c.frames, isEmpty);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('direct write failure releases both physical and active send work', (tester) async {
    await _withSend(tester, (c) async {
      final completion = c.holdWrite();
      c.write = (_) => completion.future;
      final failure = StateError('synthetic write failure');
      final result = _Result(c.sendMessage(_contact, 'synthetic message'));
      await tester.pump();
      _expectWork(c, sends: 1, writes: 1);
      completion.completeError(failure);
      await tester.pump();
      expect(result.error, same(failure));
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('write timeout ends logical send while original I/O stays held', (tester) async {
    await _withSend(tester, (c) async {
      final completion = c.holdWrite();
      c.write = (_) => completion.future;
      final result = _Result(c.sendMessage(_contact, 'synthetic message'));
      await tester.pump();
      _expectWork(c, sends: 1, writes: 1);
      await tester.pump(const Duration(seconds: 5));
      expect(result.error, isA<TimeoutException>());
      _expectWork(c, writes: 1);
      expect(c.hasPendingRadioStatsWork, isFalse);
      completion.complete();
      await tester.pump();
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('dispose retains started preparation and late sends add no leases', (tester) async {
    await _withSend(tester, (c) async {
      final preparation = c.holdPreparation();
      c.prepare = (_) => preparation.future;
      final result = _Result(c.sendMessage(_contact, 'synthetic message'));
      await tester.pump();
      _expectWork(c, sends: 1);
      c.connected = false;
      c.dispose();
      expect(c.backgroundWorkSnapshot.isClosed, isTrue);
      _expectWork(c, sends: 1);
      c.prepare = (_) => Future<String>.value('synthetic late message');
      final revision = c.backgroundWorkSnapshot.revision;
      await c.sendMessage(_contact, 'synthetic late message');
      expect(c.backgroundWorkSnapshot.revision, revision);
      _expectWork(c, sends: 1);
      preparation.complete('synthetic message');
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.frames, isEmpty);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('every channel scope text and reset writer sees the same active send', (tester) async {
    await _withSend(tester, (c) async {
      c.acknowledge = true;
      final result = _Result(c.sendChannelMessage(_channel, 'synthetic message', region: ''));
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.frames.map((frame) => frame.first), [
        cmdSetFloodScope, cmdSendChannelTxtMsg, cmdSetFloodScope,
      ]);
      expect(c.workAtWrite, hasLength(3));
      for (final snapshot in c.workAtWrite) {
        expect(snapshot.countFor(BackgroundWorkKind.radioSend), 1);
        expect(snapshot.countFor(BackgroundWorkKind.commandReply), 1);
        expect(snapshot.countFor(BackgroundWorkKind.transportWrite), 1);
        expect(snapshot.activeCount, 3);
      }
      expect(c.activeAtWrite, [true, true, true]);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('channel scope ACK wait holds the send between physical writes', (tester) async {
    await _withSend(tester, (c) async {
      final result = _Result(c.sendChannelMessage(_channel, 'synthetic message', region: ''));
      await tester.pump();
      expect(c.frames.single.first, cmdSetFloodScope);
      _expectWork(c, sends: 1, commands: 1);
      expect(result.completed, isFalse);
      c.acknowledge = true;
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('channel scope reset ACK is still part of the original send', (tester) async {
    await _withSend(tester, (c) async {
      c.acknowledge = true;
      c.allowAck = (_) => c.frames.length < 3;
      final result = _Result(c.sendChannelMessage(_channel, 'synthetic message', region: ''));
      await tester.pump();
      expect(c.frames, hasLength(3));
      expect(result.completed, isFalse);
      _expectWork(c, sends: 1, commands: 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('channel scope failure releases the send without sending text', (tester) async {
    await _withSend(tester, (c) async {
      final failure = StateError('synthetic scope failure');
      c.write = (_) => Future<void>.error(failure);
      final result = _Result(c.sendChannelMessage(_channel, 'synthetic message', region: ''));
      await tester.pump();
      expect(result.error, same(failure));
      expect(c.frames.single.first, cmdSetFloodScope);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('channel command timeout releases send and command but retains its tombstone', (tester) async {
    await _withSend(tester, (c) async {
      final result = _Result(c.sendChannelMessage(_channel, 'synthetic message', region: ''));
      await tester.pump();
      _expectWork(c, sends: 1, commands: 1);
      await tester.pump(const Duration(seconds: 5));
      expect(result.error, isA<TimeoutException>());
      expect(c.pendingCommandReplyCountForTest, 1);
      _expectWork(c);
      c.handleFrameForTest([respCodeOk]);
      expect(c.pendingCommandReplyCountForTest, 0);
      _expectWork(c);
    });
  }, timeout: timeout);
}

