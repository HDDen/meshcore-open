import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/connector/pending_command_replies.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic preferences without a directory');
  }
}

final _blobs = [
  Uint8List.fromList([0x11, 0x22]),
  Uint8List.fromList([0x33]),
];

// Настоящие scope lock/sendImageChunks/sendFrame/ACK. Только наличие связи,
// capability и physical writer синтетические; кодек и радио не задействованы.
class _ImageConnector extends MeshCoreConnector {
  bool connected = true;
  bool channelDataSupported = true;
  final frames = <List<int>>[];
  final held = <Completer<void>>[];
  List<int>? Function(Uint8List)? replyFor;
  Future<void> Function(Uint8List)? write;

  _ImageConnector() {
    setFrameWriterForTest((frame) {
      frames.add(List<int>.of(frame));
      final reply = replyFor == null ? [respCodeOk] : replyFor!(frame);
      if (reply != null) {
        handleFrameForTest(reply);
      }
      return write?.call(frame) ?? Future<void>.value();
    });
  }

  @override
  bool get isConnected => connected;
  @override
  bool get supportsChannelData => connected && channelDataSupported;

  List<int> get codes => frames.map((frame) => frame[0]).toList();

  Completer<void> hold() {
    final completion = Completer<void>();
    held.add(completion);
    return completion;
  }

  Future<bool> send({
    List<Uint8List>? blobs,
    Duration delay = const Duration(seconds: 2),
    void Function(int, int)? onProgress,
  }) => sendImageChunks(
    blobs ?? _blobs,
    channelIndex: 2,
    interChunkDelay: delay,
    onProgress: onProgress,
  );
}

class _Result {
  _Result(Future<bool> operation) {
    unawaited(operation.then<void>((result) {
      value = result;
      completed = true;
    }, onError: (Object failure, StackTrace stack) {
      error = failure;
      completed = true;
    }));
  }
  bool completed = false;
  bool? value;
  Object? error;
}

Future<void> _withImage(
  WidgetTester tester,
  Future<void> Function(_ImageConnector c) check,
) async {
  final c = _ImageConnector();
  try {
    await check(c);
  } finally {
    c.connected = false;
    for (final completion in c.held) {
      if (!completion.isCompleted) {
        completion.complete();
      }
    }
    // Межчанковая пауза fixture — 2 с; command/write timeout — прежние 5 с.
    // Два окна также выпускают возможное ожидание reset ACK после timeout.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    if (!c.backgroundWorkSnapshot.isClosed) {
      c.resetSyncProgressForTest();
      c.dispose();
    }
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

  for (final reason in ['empty', 'unsupported', 'disconnected']) {
    testWidgets('baseline: $reason returns false without scope or progress', (tester) async {
      await _withImage(tester, (c) async {
        if (reason == 'unsupported') {
          c.channelDataSupported = false;
        }
        if (reason == 'disconnected') {
          c.connected = false;
        }
        final progress = <(int, int)>[];
        final result = _Result(c.send(
          blobs: reason == 'empty' ? [] : _blobs,
          onProgress: (sent, total) => progress.add((sent, total)),
        ));
        await tester.pump();
        expect(result.completed, isTrue);
        expect(result.value, isFalse);
        expect(result.error, isNull);
        expect(c.frames, isEmpty);
        expect(progress, isEmpty);
      });
    }, timeout: timeout);
  }

  testWidgets('baseline: chunks keep their bytes and order inside one scope with the exact delay', (tester) async {
    await _withImage(tester, (c) async {
      final progress = <(int, int)>[];
      final result = _Result(c.send(
        onProgress: (sent, total) => progress.add((sent, total)),
      ));
      await tester.pump();
      expect(c.frames, [
        [cmdSetFloodScope, 0],
        [cmdSendChannelData, 2, 0xFF, 0x1C, 0xAE, 0x11, 0x22],
      ]);
      expect(progress, [(1, 2)]);
      expect(result.completed, isFalse);
      await tester.pump(const Duration(milliseconds: 1999));
      expect(c.frames, hasLength(2));
      await tester.pump(const Duration(milliseconds: 1));
      expect(c.frames, [
        [cmdSetFloodScope, 0],
        [cmdSendChannelData, 2, 0xFF, 0x1C, 0xAE, 0x11, 0x22],
        [cmdSendChannelData, 2, 0xFF, 0x1C, 0xAE, 0x33],
        [cmdSetFloodScope, 0],
      ]);
      expect(progress, [(1, 2), (2, 2)]);
      expect(result.value, isTrue);
      expect(result.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: scope chunk and reset each await their own ACK', (tester) async {
    await _withImage(tester, (c) async {
      c.replyFor = (_) => null;
      final progress = <(int, int)>[];
      final result = _Result(c.send(
        blobs: [_blobs.first],
        onProgress: (sent, total) => progress.add((sent, total)),
      ));
      await tester.pump();
      expect(c.codes, [cmdSetFloodScope]);
      expect(progress, isEmpty);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData]);
      expect(progress, isEmpty);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(progress, [(1, 1)]);
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData, cmdSetFloodScope]);
      expect(result.completed, isFalse);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(result.value, isTrue);
      expect(result.error, isNull);
    });
  }, timeout: timeout);

  testWidgets('baseline: early ACK does not finish a held physical chunk write', (tester) async {
    await _withImage(tester, (c) async {
      final completion = c.hold();
      c.write = (frame) => frame[0] == cmdSendChannelData
          ? completion.future : Future<void>.value();
      final progress = <(int, int)>[];
      final result = _Result(c.send(
        blobs: [_blobs.first],
        onProgress: (sent, total) => progress.add((sent, total)),
      ));
      await tester.pump();
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData]);
      expect(progress, isEmpty);
      expect(result.completed, isFalse);
      completion.complete();
      await tester.pump();
      expect(progress, [(1, 1)]);
      expect(result.value, isTrue);
    });
  }, timeout: timeout);

  testWidgets('baseline: chunk ERR preserves its code and resets scope without progress', (tester) async {
    await _withImage(tester, (c) async {
      c.replyFor = (frame) => frame[0] == cmdSendChannelData
          ? [respCodeErr, 3] : [respCodeOk];
      final progress = <(int, int)>[];
      final result = _Result(c.send(
        onProgress: (sent, total) => progress.add((sent, total)),
      ));
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isA<CommandFailedException>().having((e) => e.errCode, 'errCode', 3));
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData, cmdSetFloodScope]);
      expect(progress, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: initial scope ERR exits before the action and does not reset scope', (tester) async {
    await _withImage(tester, (c) async {
      c.replyFor = (_) => [respCodeErr, 2];
      final result = _Result(c.send());
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isA<CommandFailedException>().having((e) => e.errCode, 'errCode', 2));
      expect(c.codes, [cmdSetFloodScope]);
    });
  }, timeout: timeout);

  testWidgets('baseline: timed-out chunk tombstone absorbs a late ACK before reset completes', (tester) async {
    await _withImage(tester, (c) async {
      c.replyFor = (_) => c.frames.length == 1 ? [respCodeOk] : null;
      final result = _Result(c.send());
      await tester.pump();
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData]);
      await tester.pump(const Duration(seconds: 5));
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData, cmdSetFloodScope]);
      expect(result.completed, isFalse);
      c.handleFrameForTest([respCodeOk]); // Поздний ответ чанка поглощён.
      await tester.pump();
      expect(result.completed, isFalse);
      c.handleFrameForTest([respCodeOk]); // Ответ reset.
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, isA<TimeoutException>());
    });
  }, timeout: timeout);

  testWidgets('baseline: disconnect after progress returns false before the next chunk', (tester) async {
    await _withImage(tester, (c) async {
      final progress = <(int, int)>[];
      final result = _Result(c.send(onProgress: (sent, total) {
        progress.add((sent, total));
        c.connected = false;
      }));
      await tester.pump();
      expect(result.value, isFalse);
      expect(result.error, isNull);
      expect(progress, [(1, 2)]);
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData]);
    });
  }, timeout: timeout);

  testWidgets('baseline: disconnect inside interchunk delay follows the existing send error path', (tester) async {
    await _withImage(tester, (c) async {
      final result = _Result(c.send());
      await tester.pump();
      c.connected = false;
      await tester.pump(const Duration(seconds: 2));
      expect(result.completed, isTrue);
      expect(result.error, isA<Exception>());
      expect(result.value, isNull);
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData]);
    });
  }, timeout: timeout);

  testWidgets('baseline: two images share the scope lock without interleaving', (tester) async {
    await _withImage(tester, (c) async {
      final completion = c.hold();
      var holding = false;
      c.write = (frame) {
        if (frame[0] == cmdSendChannelData && !holding) {
          holding = true;
          return completion.future;
        }
        return Future<void>.value();
      };
      final first = _Result(c.send(blobs: [_blobs.first]));
      final second = _Result(c.send(blobs: [_blobs.last]));
      await tester.pump();
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData]);
      expect(first.completed, isFalse);
      expect(second.completed, isFalse);
      completion.complete();
      await tester.pump();
      expect(c.codes, [
        cmdSetFloodScope, cmdSendChannelData, cmdSetFloodScope,
        cmdSetFloodScope, cmdSendChannelData, cmdSetFloodScope,
      ]);
      expect(c.frames.where((f) => f[0] == cmdSendChannelData).map((f) => f.last), [0x22, 0x33]);
      expect(first.value, isTrue);
      expect(second.value, isTrue);
    });
  }, timeout: timeout);

  testWidgets('baseline: progress callback error is preserved after scope reset', (tester) async {
    await _withImage(tester, (c) async {
      final failure = StateError('synthetic progress error');
      final result = _Result(c.send(onProgress: (_, _) => throw failure));
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, same(failure));
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData, cmdSetFloodScope]);
    });
  }, timeout: timeout);

  testWidgets('baseline: caller timeout does not cancel a pending image write', (tester) async {
    await _withImage(tester, (c) async {
      final completion = c.hold();
      c.write = (frame) => frame[0] == cmdSendChannelData
          ? completion.future : Future<void>.value();
      final operation = c.send(blobs: [_blobs.first]);
      final actual = _Result(operation);
      final caller = _Result(operation.timeout(const Duration(seconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(caller.error, isA<TimeoutException>());
      expect(actual.completed, isFalse);
      completion.complete();
      await tester.pump();
      expect(actual.value, isTrue);
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData, cmdSetFloodScope]);
    });
  }, timeout: timeout);

  testWidgets('baseline: dispose does not complete a held chunk callback', (tester) async {
    await _withImage(tester, (c) async {
      final completion = c.hold();
      c.write = (frame) => frame[0] == cmdSendChannelData
          ? completion.future : Future<void>.value();
      final progress = <(int, int)>[];
      final result = _Result(c.send(
        onProgress: (sent, total) => progress.add((sent, total)),
      ));
      await tester.pump();
      c.connected = false;
      c.dispose();
      expect(result.completed, isFalse);
      expect(progress, isEmpty);
      completion.complete();
      await tester.pump();
      expect(result.value, isFalse);
      expect(result.error, isNull);
      expect(progress, [(1, 2)]);
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData]);
    });
  }, timeout: timeout);

  testWidgets('baseline: physical write error retains identity and resets scope', (tester) async {
    await _withImage(tester, (c) async {
      final failure = StateError('synthetic physical write failure');
      c.write = (frame) => frame[0] == cmdSendChannelData
          ? Future<void>.error(failure) : Future<void>.value();
      final result = _Result(c.send());
      await tester.pump();
      expect(result.completed, isTrue);
      expect(result.error, same(failure));
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData, cmdSetFloodScope]);
    });
  }, timeout: timeout);
}
