import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
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
  final heldPreparations = <Completer<String>>[];
  final heldWrites = <Completer<void>>[];
  Future<String> Function(String)? prepare;
  Future<void> Function(Uint8List)? write;

  _SendConnector() {
    setFrameWriterForTest((frame) {
      frames.add(List<int>.of(frame));
      activeAtWrite.add(hasPendingRadioStatsWork);
      if (acknowledge) {
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

  testWidgets('baseline: direct preparation is active before the first physical write', (tester) async {
    await _withSend(tester, (c) async {
      final preparation = c.holdPreparation();
      c.prepare = (_) => preparation.future;
      final result = _Result(c.sendMessage(_contact, 'synthetic message'));
      await tester.pump();
      expect(c.hasPendingRadioStatsWork, isTrue);
      expect(c.frames, isEmpty);
      expect(result.completed, isFalse);
      preparation.complete('synthetic prepared message');
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.frames.single.first, cmdSendTxtMsg);
      expect(c.activeAtWrite, [true]);
      expect(c.hasPendingRadioStatsWork, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: overlapping preparations remain active until the last finishes', (tester) async {
    await _withSend(tester, (c) async {
      final first = c.holdPreparation();
      final second = c.holdPreparation();
      c.prepare = (text) => text == 'first' ? first.future : second.future;
      final a = _Result(c.sendMessage(_contact, 'first'));
      final b = _Result(c.sendMessage(_contact, 'second'));
      await tester.pump();
      expect(c.preparations, 2);
      expect(c.frames, isEmpty);
      first.complete('first');
      await tester.pump();
      expect(a.completed, isTrue);
      expect(b.completed, isFalse);
      expect(c.frames, hasLength(1));
      expect(c.hasPendingRadioStatsWork, isTrue);
      second.complete('second');
      await tester.pump();
      expect(b.completed, isTrue);
      expect(a.error, isNull);
      expect(b.error, isNull);
      expect(c.frames, hasLength(2));
      expect(c.hasPendingRadioStatsWork, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: preparation failure propagates before any write', (tester) async {
    await _withSend(tester, (c) async {
      final preparation = c.holdPreparation();
      c.prepare = (_) => preparation.future;
      final failure = StateError('synthetic preparation failure');
      final result = _Result(c.sendMessage(_contact, 'synthetic message'));
      await tester.pump();
      preparation.completeError(failure);
      await tester.pump();
      expect(result.error, same(failure));
      expect(c.frames, isEmpty);
      expect(c.hasPendingRadioStatsWork, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: caller timeout does not finish the underlying preparation', (tester) async {
    await _withSend(tester, (c) async {
      final preparation = c.holdPreparation();
      c.prepare = (_) => preparation.future;
      final operation = c.sendMessage(_contact, 'synthetic message');
      final caller = _Result(operation.timeout(const Duration(seconds: 1)));
      await tester.pump(const Duration(seconds: 1));
      expect(caller.error, isA<TimeoutException>());
      expect(c.hasPendingRadioStatsWork, isTrue);
      expect(c.frames, isEmpty);
      preparation.complete('synthetic message');
      await tester.pump();
      expect(c.frames, hasLength(1));
      expect(c.hasPendingRadioStatsWork, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: disconnect during preparation skips the physical write', (tester) async {
    await _withSend(tester, (c) async {
      final preparation = c.holdPreparation();
      c.prepare = (_) => preparation.future;
      final result = _Result(c.sendMessage(_contact, 'synthetic message'));
      await tester.pump();
      c.connected = false;
      preparation.complete('synthetic message');
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.frames, isEmpty);
      expect(c.hasPendingRadioStatsWork, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: empty and offline direct and channel sends do no work', (tester) async {
    await _withSend(tester, (c) async {
      await c.sendMessage(_contact, '');
      await c.sendChannelMessage(_channel, '', region: '');
      c.offline = true;
      await c.sendMessage(_contact, 'synthetic message');
      await c.sendChannelMessage(_channel, 'synthetic message', region: '');
      expect(c.preparations, 0);
      expect(c.frames, isEmpty);
      expect(c.hasPendingRadioStatsWork, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: an unready retry returns without rescheduling or writing', (tester) async {
    await _withSend(tester, (c) async {
      c.ready = false;
      await c.sendMessage(_contact, 'synthetic message', pendingMessageId: 'direct');
      await c.sendChannelMessage(
        _channel, 'synthetic message', pendingMessageId: 'channel', region: '',
      );
      expect(c.preparations, 0);
      expect(c.frames, isEmpty);
      expect(c.hasPendingRadioStatsWork, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: direct write failure propagates without automatic retry', (tester) async {
    await _withSend(tester, (c) async {
      final failure = StateError('synthetic write failure');
      c.write = (_) => Future<void>.error(failure);
      final result = _Result(c.sendMessage(_contact, 'synthetic message'));
      await tester.pump();
      expect(result.error, same(failure));
      expect(c.hasPendingRadioStatsWork, isFalse);
      await tester.pump(const Duration(seconds: 6));
      expect(c.frames, hasLength(1));
    });
  }, timeout: timeout);

  testWidgets('baseline: direct operation times out while its physical I/O can continue', (tester) async {
    await _withSend(tester, (c) async {
      final write = c.holdWrite();
      c.write = (_) => write.future;
      final result = _Result(c.sendMessage(_contact, 'synthetic message'));
      await tester.pump();
      expect(c.hasPendingRadioStatsWork, isTrue);
      await tester.pump(const Duration(seconds: 5));
      expect(result.error, isA<TimeoutException>());
      expect(write.isCompleted, isFalse);
      expect(c.hasPendingRadioStatsWork, isFalse);
      write.complete();
      await tester.pump();
      expect(c.frames, hasLength(1));
    });
  }, timeout: timeout);

  testWidgets('baseline: dispose does not complete a preparation still awaiting its Future', (tester) async {
    await _withSend(tester, (c) async {
      final preparation = c.holdPreparation();
      c.prepare = (_) => preparation.future;
      final result = _Result(c.sendMessage(_contact, 'synthetic message'));
      await tester.pump();
      c.connected = false;
      c.dispose();
      expect(c.hasPendingRadioStatsWork, isTrue);
      expect(result.completed, isFalse);
      preparation.complete('synthetic message');
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.frames, isEmpty);
      expect(c.hasPendingRadioStatsWork, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: channel send stays active through scope, text ACK and scope reset', (tester) async {
    await _withSend(tester, (c) async {
      c.acknowledge = true;
      final result = _Result(c.sendChannelMessage(_channel, 'synthetic message', region: ''));
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isNull);
      expect(c.frames.map((frame) => frame.first), [
        cmdSetFloodScope, cmdSendChannelTxtMsg, cmdSetFloodScope,
      ]);
      expect(c.activeAtWrite, [true, true, true]);
      expect(c.hasPendingRadioStatsWork, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: channel scope write failure ends operation before text TX', (tester) async {
    await _withSend(tester, (c) async {
      final failure = StateError('synthetic scope failure');
      c.write = (_) => Future<void>.error(failure);
      final result = _Result(c.sendChannelMessage(_channel, 'synthetic message', region: ''));
      await tester.pump();
      expect(result.error, same(failure));
      expect(c.frames.single.first, cmdSetFloodScope);
      expect(c.hasPendingRadioStatsWork, isFalse);
    });
  }, timeout: timeout);
}
