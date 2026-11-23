import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/connector/pending_command_replies.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/helpers/channel_raw_packet.dart';
import 'package:meshcore_open/services/image_chunk_transport.dart' show dataTypeAeicImage;
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

final _blobs = [
  Uint8List.fromList([0x11, 0x22]),
  Uint8List.fromList([0x33]),
];

// Настоящие scope lock/sendImageChunks/sendFrame/ACK. Только наличие связи,
// capability и physical writer синтетические; кодек и радио не задействованы.
class _ImageConnector extends MeshCoreConnector {
  final settings = AppSettingsService();
  bool connected = true;
  bool channelDataSupported = true;
  final frames = <List<int>>[];
  final held = <Completer<void>>[];
  List<int>? Function(Uint8List)? replyFor;
  Future<void> Function(Uint8List)? write;

  _ImageConnector() {
    attachAppSettingsServiceForTest(settings);
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
    // Пауза fixture не длиннее 10 с; command/write timeout — прежние 5 с.
    // Два окна также выпускают возможное ожидание reset ACK после timeout.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    if (!c.backgroundWorkSnapshot.isClosed) {
      c.resetSyncProgressForTest();
      c.dispose();
    }
    c.settings.dispose();
  }
}

void _expectWork(_ImageConnector c, {int images = 0, int writes = 0, int commands = 0}) {
  final snapshot = c.backgroundWorkSnapshot;
  expect(snapshot.countFor(BackgroundWorkKind.imageTransfer), images);
  expect(snapshot.countFor(BackgroundWorkKind.transportWrite), writes);
  expect(snapshot.countFor(BackgroundWorkKind.commandReply), commands);
  expect(snapshot.activeCount, images + writes + commands);
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

  for (final enabled in [false, true]) {
    testWidgets('AEIC packet retries honor enablement and keep bytes ($enabled)', (tester) async {
      await _withImage(tester, (c) async {
        c.setChannelResendClockForTest(tester.binding.clock.now);
        await c.settings.updateSettings(c.settings.settings.copyWith(
          channelMinHopsEnabled: enabled,
          channelMinHops: 2,
          channelMinHopsRetries: 2,
          channelMinHopsDelaySeconds: 3,
        ));
        final result = _Result(c.send(blobs: [_blobs.first], delay: Duration.zero));
        await tester.pump();
        expect(result.value, isTrue);
        List<List<int>> packets() => c.frames.where((f) => f[0] == cmdSendChannelData).toList();
        final first = List<int>.of(packets().single);
        expect(c.backgroundWorkSnapshot.countFor(BackgroundWorkKind.retry), enabled ? 1 : 0);
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(seconds: 3));
        }
        expect(packets(), enabled ? [first, first, first] : [first]);
        expect(c.backgroundWorkSnapshot.countFor(BackgroundWorkKind.retry), 0);
      });
    }, timeout: timeout);
  }

  testWidgets('AEIC valid chunks expose attempts only while their own retry is active', (tester) async {
    await _withImage(tester, (c) async {
      c.setChannelResendClockForTest(tester.binding.clock.now);
      await c.settings.updateSettings(c.settings.settings.copyWith(
        channelMinHopsEnabled: true, channelMinHops: 2,
        channelMinHopsRetries: 1, channelMinHopsDelaySeconds: 3,
      ));
      final blob = Uint8List.fromList([0x11, 0x22, 7, 1, 0, 1]);
      final result = _Result(c.send(blobs: [blob], delay: Duration.zero));
      await tester.pump();
      expect(result.value, isTrue);
      final seen = DateTime.now();
      expect(c.imageResendProgress(2, 0x1122, 7, seen), (resends: 0, maxResends: 1));
      expect(c.imageResendProgress(2, 0x1122, 8, seen), isNull);
      expect(c.imageResendProgress(3, 0x1122, 7, seen), isNull);
      expect(c.imageResendProgress(2, 0x1122, 7, DateTime(2000)), isNull);
      await tester.pump(const Duration(seconds: 3));
      expect(c.imageResendProgress(2, 0x1122, 7, seen), (resends: 1, maxResends: 1));
      expect(c.frames.where((frame) => frame[0] == cmdSendChannelData), hasLength(2));
      await tester.pump(const Duration(seconds: 3));
      expect(c.imageResendProgress(2, 0x1122, 7, seen), isNull);
    });
  }, timeout: timeout);

  for (final stop in ['disconnect', 'dispose', 'initial error']) {
    testWidgets('AEIC retry work is released on $stop', (tester) async {
      await _withImage(tester, (c) async {
        c.setChannelResendClockForTest(tester.binding.clock.now);
        await c.settings.updateSettings(c.settings.settings.copyWith(
          channelMinHopsEnabled: true,
          channelMinHopsRetries: 2,
          channelMinHopsDelaySeconds: 3,
        ));
        if (stop == 'initial error') {
          c.replyFor = (frame) => frame[0] == cmdSendChannelData
              ? [respCodeErr, 3] : [respCodeOk];
        }
        final result = _Result(c.send(blobs: [_blobs.first], delay: Duration.zero));
        await tester.pump();
        if (stop == 'initial error') {
          expect(result.error, isNotNull);
        } else {
          expect(result.value, isTrue);
          expect(c.backgroundWorkSnapshot.countFor(BackgroundWorkKind.retry), 1);
          c.connected = false;
          if (stop == 'dispose') {
            c.dispose();
          }
        }
        final count = c.frames.where((f) => f[0] == cmdSendChannelData).length;
        await tester.pump(const Duration(seconds: 3));
        expect(c.frames.where((f) => f[0] == cmdSendChannelData).length, count);
        expect(c.backgroundWorkSnapshot.countFor(BackgroundWorkKind.retry), 0);
      });
    }, timeout: timeout);
  }

  testWidgets('AEIC raw echo completes only the matching chunk retry', (tester) async {
    await _withImage(tester, (c) async {
      c.setChannelResendClockForTest(tester.binding.clock.now);
      await c.settings.updateSettings(c.settings.settings.copyWith(
        channelMinHopsEnabled: true,
        channelMinHops: 2,
        channelMinHopsRetries: 1,
        channelMinHopsDelaySeconds: 3,
      ));
      final psk = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
      final info = Uint8List(50)..[0] = respCodeChannelInfo..[1] = 2;
      info.setRange(2, 6, 'Test'.codeUnits);
      info.setRange(34, 50, psk);
      // CHANNEL_INFO also loads persisted channel settings/history. Await the
      // real handler outside fake async before starting the send under test.
      await tester.runAsync(() => c.handleChannelInfoForTest(info));
      Future<void> advanceUntil(bool Function() done, String phase) async {
        for (var step = 0; step < 200 && !done(); step++) {
          // pump() with no duration only drains microtasks. Advancing fake
          // time also executes the zero-duration inter-chunk timer.
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(done(), isTrue,
          reason: '$phase; commands=${c.codes}; '
              'active work=${c.backgroundWorkSnapshot.activeCount}');
      }
      final result = _Result(c.send(delay: Duration.zero));
      await advanceUntil(() => result.completed, 'initial two-chunk send');
      expect(result.error, isNull);
      expect(result.value, isTrue);
      expect(c.backgroundWorkSnapshot.countFor(BackgroundWorkKind.retry), 2);
      // The same encrypted GRP_DATA body as firmware; two 2-byte path hashes.
      final blob = _blobs.first;
      final plaintext = Uint8List.fromList([
        dataTypeAeicImage & 0xFF, dataTypeAeicImage >> 8, blob.length, ...blob,
      ]);
      c.handleFrameForTest(Uint8List.fromList([
        pushCodeLogRxData, 32, 186,
        (payloadTypeGRPDATA << 2) | 1, (1 << 6) | 2,
        0x11, 0x22, 0x33, 0x44,
        ...ChannelRawPacket.groupTextPayload(psk: psk, plaintext: plaintext),
      ]));
      await advanceUntil(
        () => c.backgroundWorkSnapshot.countFor(BackgroundWorkKind.retry) == 1,
        'matching raw echo completes one retry watcher',
      );
      // The RX-log also starts a real radio-quiet window. This test checks
      // immediate per-packet completion, independently of that clock; bounded
      // retransmission and unchanged bytes are covered in the tests above.
      final packets = c.frames.where((f) => f[0] == cmdSendChannelData).toList();
      expect(packets.length, 2);
      c.connected = false;
      c.dispose();
      await tester.pump();
      expect(c.backgroundWorkSnapshot.countFor(BackgroundWorkKind.retry), 0);
    });
  }, timeout: timeout);

  testWidgets('image lease covers interchunk pacing with Off after the first write has drained', (tester) async {
    await _withImage(tester, (c) async {
      expect(c.settings.settings.powerSaving.profile, PowerSavingProfile.disabled);
      final progress = <(int, int)>[];
      final result = _Result(c.send(
        onProgress: (sent, total) => progress.add((sent, total)),
      ));
      await tester.pump();
      _expectWork(c, images: 1);
      expect(progress, [(1, 2)]);
      expect(result.completed, isFalse);
      await tester.pump(const Duration(milliseconds: 1999));
      _expectWork(c, images: 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(result.value, isTrue);
      expect(result.error, isNull);
      expect(progress, [(1, 2), (2, 2)]);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('scope chunk and final reset waits share one image lease', (tester) async {
    await _withImage(tester, (c) async {
      c.replyFor = (_) => null;
      final result = _Result(c.send(blobs: [_blobs.first]));
      await tester.pump();
      expect(c.codes, [cmdSetFloodScope]);
      _expectWork(c, images: 1, commands: 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData]);
      _expectWork(c, images: 1, commands: 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(result.completed, isFalse);
      expect(c.codes.last, cmdSetFloodScope);
      _expectWork(c, images: 1, commands: 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(result.value, isTrue);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('an early scope ACK does not release the image or its held writer', (tester) async {
    await _withImage(tester, (c) async {
      final completion = c.hold();
      c.write = (_) => c.frames.length == 1
          ? completion.future : Future<void>.value();
      final result = _Result(c.send(blobs: [_blobs.first]));
      await tester.pump();
      expect(c.codes, [cmdSetFloodScope]);
      _expectWork(c, images: 1, commands: 1, writes: 1);
      completion.complete();
      await tester.pump();
      expect(result.value, isTrue);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('parallel images retain separate leases while one waits for the scope lock', (tester) async {
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
      final operation = c.send(blobs: [_blobs.first]);
      final first = _Result(operation);
      final caller = _Result(operation.timeout(const Duration(seconds: 1)));
      final second = _Result(c.send(blobs: [_blobs.last]));
      await tester.pump();
      _expectWork(c, images: 2, commands: 1, writes: 1);
      await tester.pump(const Duration(seconds: 1));
      expect(caller.error, isA<TimeoutException>());
      expect(first.completed, isFalse);
      expect(second.completed, isFalse);
      _expectWork(c, images: 2, commands: 1, writes: 1);
      completion.complete();
      await tester.pump();
      expect(first.value, isTrue);
      expect(second.value, isTrue);
      expect(c.codes, [
        cmdSetFloodScope, cmdSendChannelData, cmdSetFloodScope,
        cmdSetFloodScope, cmdSendChannelData, cmdSetFloodScope,
      ]);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('logical write timeout drains the image and leaves the actual writer held', (tester) async {
    await _withImage(tester, (c) async {
      final completion = c.hold();
      c.write = (frame) => frame[0] == cmdSendChannelData
          ? completion.future : Future<void>.value();
      final result = _Result(c.send());
      await tester.pump();
      _expectWork(c, images: 1, writes: 1, commands: 1);
      await tester.pump(const Duration(seconds: 5));
      expect(result.completed, isTrue);
      expect(result.error, isA<TimeoutException>());
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData, cmdSetFloodScope]);
      _expectWork(c, writes: 1);
      completion.complete();
      await tester.pump();
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('chunk timeout keeps the image through reset and a tombstone adds no hold', (tester) async {
    await _withImage(tester, (c) async {
      c.replyFor = (_) => c.frames.length == 1 ? [respCodeOk] : null;
      final result = _Result(c.send());
      await tester.pump();
      _expectWork(c, images: 1, commands: 1);
      await tester.pump(const Duration(seconds: 5));
      expect(c.codes.last, cmdSetFloodScope);
      expect(result.completed, isFalse);
      _expectWork(c, images: 1, commands: 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(result.completed, isFalse);
      _expectWork(c, images: 1, commands: 1);
      c.handleFrameForTest([respCodeOk]);
      await tester.pump();
      expect(result.error, isA<TimeoutException>());
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('dispose retains actual image and writer while late calls add no lease', (tester) async {
    await _withImage(tester, (c) async {
      final completion = c.hold();
      c.write = (frame) => frame[0] == cmdSendChannelData
          ? completion.future : Future<void>.value();
      final result = _Result(c.send());
      await tester.pump();
      c.connected = false;
      c.dispose();
      expect(c.backgroundWorkSnapshot.isClosed, isTrue);
      _expectWork(c, images: 1, writes: 1, commands: 1);
      final revision = c.backgroundWorkSnapshot.revision;
      final lateResult = _Result(c.send());
      await tester.pump();
      expect(lateResult.value, isFalse);
      expect(c.backgroundWorkSnapshot.revision, revision);
      _expectWork(c, images: 1, writes: 1, commands: 1);
      completion.complete();
      await tester.pump();
      expect(result.value, isFalse);
      expect(result.error, isNull);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('chunk error releases image after the original scope reset', (tester) async {
    await _withImage(tester, (c) async {
      c.replyFor = (frame) => frame[0] == cmdSendChannelData
          ? [respCodeErr, 3] : [respCodeOk];
      final result = _Result(c.send());
      await tester.pump();
      expect(result.error, isA<CommandFailedException>().having((e) => e.errCode, 'errCode', 3));
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData, cmdSetFloodScope]);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('initial scope error releases image without introducing a reset', (tester) async {
    await _withImage(tester, (c) async {
      c.replyFor = (_) => [respCodeErr, 2];
      final result = _Result(c.send());
      await tester.pump();
      expect(result.error, isA<CommandFailedException>());
      expect(c.codes, [cmdSetFloodScope]);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('progress callback error retains its identity and releases image after reset', (tester) async {
    await _withImage(tester, (c) async {
      final failure = StateError('synthetic progress error');
      final result = _Result(c.send(onProgress: (_, _) => throw failure));
      await tester.pump();
      expect(result.error, same(failure));
      expect(c.codes, [cmdSetFloodScope, cmdSendChannelData, cmdSetFloodScope]);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('loss during pacing keeps image until the original error path completes', (tester) async {
    await _withImage(tester, (c) async {
      final result = _Result(c.send());
      await tester.pump();
      c.connected = false;
      _expectWork(c, images: 1);
      await tester.pump(const Duration(seconds: 2));
      expect(result.error, isA<Exception>());
      expect(result.value, isNull);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('loss from progress keeps the original false result and drains image', (tester) async {
    await _withImage(tester, (c) async {
      final result = _Result(c.send(onProgress: (_, _) { c.connected = false; }));
      await tester.pump();
      expect(result.value, isFalse);
      expect(result.error, isNull);
      _expectWork(c);
    });
  }, timeout: timeout);

  testWidgets('switching every profile preserves the same in-progress image', (tester) async {
    await _withImage(tester, (c) async {
      final result = _Result(c.send(delay: const Duration(seconds: 10)));
      await tester.pump();
      for (final profile in PowerSavingProfile.values) {
        await c.settings.setPowerSavingProfile(profile);
        await tester.pump();
        _expectWork(c, images: 1);
      }
      await tester.pump(const Duration(seconds: 10));
      expect(result.value, isTrue);
      _expectWork(c);
    });
  }, timeout: timeout);

  for (final reason in ['empty', 'unsupported', 'disconnected']) {
    testWidgets('$reason return leaves no image hold', (tester) async {
      await _withImage(tester, (c) async {
        if (reason == 'unsupported') {
          c.channelDataSupported = false;
        }
        if (reason == 'disconnected') {
          c.connected = false;
        }
        final result = _Result(c.send(blobs: reason == 'empty' ? [] : _blobs));
        await tester.pump();
        expect(result.value, isFalse);
        expect(result.error, isNull);
        expect(c.frames, isEmpty);
        _expectWork(c);
      });
    }, timeout: timeout);
  }
}

