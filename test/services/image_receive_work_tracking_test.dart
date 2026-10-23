import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/main.dart' show ImageStreamReassembler;
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meshcore_open/models/image_codec_support.dart';
import 'package:meshcore_open/services/image_chunk_transport.dart';
import 'package:meshcore_open/services/received_image_store.dart';
import 'package:meshcore_open/widgets/image_send_codec_binding.dart';

// Только synthetic bytes, in-memory blobs и управляемый decoder Future.
// Кодек/модель, native isolate, сеть, настоящие PNG и файловая система не нужны.
class _Blobs extends InMemoryReceivedImageBlobStore {
  final calls = <String>[];
  final gates = <Completer<void>>[];
  Future<void> Function(String operation)? before;
  bool bitstreamWritten = true;
  bool sidecarFails = false;

  Completer<void> hold(String operation) {
    final gate = Completer<void>();
    gates.add(gate);
    before = (name) => name == operation ? gate.future : Future<void>.value();
    return gate;
  }

  Future<void> _enter(String operation) async {
    calls.add(operation);
    await before?.call(operation);
  }

  @override
  Future<bool> writeBitstream(String streamId, Uint8List bytes) async {
    await _enter('bitstream');
    if (!bitstreamWritten) return false;
    return super.writeBitstream(streamId, bytes);
  }

  @override
  Future<bool> writePng(String streamId, Uint8List bytes) async {
    await _enter('png');
    return super.writePng(streamId, bytes);
  }

  @override
  Future<void> writeSidecar(String streamId, String json) async {
    await _enter('sidecar');
    if (sidecarFails) throw StateError('synthetic sidecar failure');
    await super.writeSidecar(streamId, json);
  }
}

class _Decoder implements ReceivedImageDecoder {
  @override
  ImageCodecAvailability availability = ImageCodecAvailability.ready;
  @override
  bool isBusy = false;
  final jobs = <Completer<ImageCodecResult?>>[];
  int active = 0;
  int maxActive = 0;
  int cancels = 0;

  @override
  Future<ImageCodecResult?> decodeBitstream({
    required Uint8List bitstream,
    required AeicRatePoint ratePoint,
    required int resolution,
  }) async {
    final job = Completer<ImageCodecResult?>();
    jobs.add(job);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      return await job.future;
    } finally {
      active--;
    }
  }

  // Отмена — запрос к native backend, а не завершение его Future.
  @override
  void cancelCodecJob() => cancels++;

  void succeed(int index) => jobs[index].complete(ImageCodecResult(
    ratePoint: AeicRatePoint.ft32,
    resolution: 512,
    durationMs: 7,
    status: ImageCodecStatus.completed,
    pngBytes: Uint8List.fromList([1, 2, 3, 4]),
  ));

  void fail(int index) => jobs[index].complete(ImageCodecResult(
    ratePoint: AeicRatePoint.ft32,
    resolution: 512,
    durationMs: 7,
    status: ImageCodecStatus.failed,
  ));
}

class _Result<T> {
  _Result(Future<T> operation) {
    unawaited(operation.then<void>((result) {
      value = result;
      completed = true;
    }, onError: (Object failure, StackTrace stack) {
      error = failure;
      completed = true;
    }));
  }
  bool completed = false;
  T? value;
  Object? error;
}

class _Rig {
  _Rig(WidgetTester tester, {bool automatic = true}) {
    reassembler = ImageReassembler(clock: tester.binding.clock.now);
    store = ReceivedImageStore(
      blobs: blobs, decoder: decoder, processAutomatically: automatic,
      clock: tester.binding.clock.now,
    );
    store.attachBackgroundWorkTracker(tracker);
  }
  final tracker = BackgroundWorkTracker();
  final connectors = <MeshCoreConnector>[];
  final blobs = _Blobs();
  final decoder = _Decoder();
  late final ImageReassembler reassembler;
  late final ReceivedImageStore store;
  bool disposed = false;

  ImageChunkSet chunks(int id, {int length = 32}) => buildImageChunks(
    payload: Uint8List.fromList(List.generate(length, (i) => (i + id) & 0xff)),
    metadata: const ImageStreamMetadata(rate: ImageCodecRatePoint.standard),
    senderPrefix: 0x1234, imgId: id,
  );

  Future<ReceivedImageEntry?> receive(int id) => store.handleOutcome(
    reassembler.addChunk(chunks(id).blobs.first, channelIndex: 2),
    channelIndex: 2, channelId: 'synthetic-channel',
  );

  MeshCoreConnector connector() {
    final connector = MeshCoreConnector();
    connectors.add(connector);
    connector.bindImageReceiveBackgroundWork(store);
    return connector;
  }

  void expectCount(int count, {BackgroundWorkSnapshot? snapshot}) {
    final state = snapshot ?? tracker.snapshot;
    expect(state.countFor(BackgroundWorkKind.receiveAssembly), count);
    expect(state.activeCount, count);
    expect(state.isBusy, count > 0);
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    store.dispose();
  }
}

Future<void> _withImages(WidgetTester tester, Future<void> Function(_Rig) check,
    {bool automatic = true}) async {
  final rig = _Rig(tester, automatic: automatic);
  try {
    await check(rig);
  } finally {
    // Dispose до release запрещает старт следующей queued-декодировки.
    rig.dispose();
    for (final gate in rig.blobs.gates) {
      if (!gate.isCompleted) gate.complete();
    }
    for (final job in rig.decoder.jobs) {
      if (!job.isCompleted) job.complete(null);
    }
    await tester.pump();
    await rig.store.settle();
    for (final connector in rig.connectors) {
      if (!connector.backgroundWorkSnapshot.isClosed) connector.dispose();
    }
    rig.tracker.close();
  }
}

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic preferences without a directory');
  }
}

void main() {
  const timeout = Timeout(Duration(seconds: 30));
  late PathProviderPlatform savedPaths;
  setUpAll(() {
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
  });
  tearDownAll(() => PathProviderPlatform.instance = savedPaths);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  testWidgets('intake holds bitstream and sidecar commit with automatic processing off', (tester) async {
    await _withImages(tester, (h) async {
      final bitstream = h.blobs.hold('bitstream');
      final intake = _Result(h.receive(1));
      await tester.pump();
      h.expectCount(1);
      expect(intake.completed, isFalse);
      final sidecar = h.blobs.hold('sidecar');
      bitstream.complete();
      await tester.pump();
      h.expectCount(1);
      expect(h.store.entries.single.state, ReceivedImageState.reassembled);
      expect(intake.completed, isFalse);
      sidecar.complete();
      await tester.pump();
      expect(intake.completed, isTrue);
      expect(intake.error, isNull);
      expect(h.decoder.jobs, isEmpty);
      h.expectCount(0);
    }, automatic: false);
  }, timeout: timeout);

  testWidgets('detached app intake and decode stay held through final PNG write', (tester) async {
    await _withImages(tester, (h) async {
      final appReassembler = ImageStreamReassembler(store: h.store);
      final outcome = appReassembler.addChunk(h.chunks(1).blobs.first, channelIndex: 2);
      expect(outcome.status, ImageChunkStatus.completed);
      await tester.pump();
      expect(h.decoder.active, 1);
      h.expectCount(1);
      final gate = h.blobs.hold('png');
      h.decoder.succeed(0);
      await tester.pump();
      expect(h.decoder.active, 0);
      expect(h.store.entries.single.state, ReceivedImageState.decoding);
      h.expectCount(1);
      gate.complete();
      await tester.pump();
      expect(h.store.entries.single.state, ReceivedImageState.decoded);
      h.expectCount(0);
    });
  }, timeout: timeout);

  testWidgets('independent intake and active decode overlap without losing either lease', (tester) async {
    await _withImages(tester, (h) async {
      final first = await h.receive(1);
      await tester.pump();
      h.expectCount(1);
      final gate = h.blobs.hold('bitstream');
      final second = _Result(h.receive(2));
      await tester.pump();
      h.expectCount(2);
      h.decoder.succeed(0);
      await tester.pump();
      expect(h.store.entryFor(first!.streamId)!.state, ReceivedImageState.decoded);
      h.expectCount(1);
      expect(second.completed, isFalse);
      gate.complete();
      await tester.pump();
      expect(second.completed, isTrue);
      expect(h.decoder.jobs, hasLength(2));
      h.expectCount(1);
      h.decoder.succeed(1);
      await tester.pump();
      h.expectCount(0);
    });
  }, timeout: timeout);

  for (final parked in ['background', 'busy']) {
    testWidgets('$parked queue stays passive and resume holds only actual decode', (tester) async {
      await _withImages(tester, (h) async {
        if (parked == 'background') {
          h.store.setForeground(false);
        } else {
          h.decoder.isBusy = true;
        }
        final entry = await h.receive(1);
        await h.store.settle();
        expect(h.store.decodeQueue, [entry!.streamId]);
        expect(h.store.isDecoding, isTrue);
        expect(h.decoder.jobs, isEmpty);
        h.expectCount(0);
        if (parked == 'background') {
          h.store.setForeground(true);
        } else {
          h.decoder.isBusy = false;
          h.store.notifyDecoderChanged();
        }
        await tester.pump();
        h.expectCount(1);
        h.decoder.succeed(0);
        await tester.pump();
        expect(h.store.entryFor(entry.streamId)!.state, ReceivedImageState.decoded);
        h.expectCount(0);
      });
    }, timeout: timeout);
  }

  testWidgets('partial assembly is passive after intake and failure holds its sidecar', (tester) async {
    await _withImages(tester, (h) async {
      final outcome = h.reassembler.addChunk(h.chunks(1, length: 400).blobs.first, channelIndex: 2);
      final intakeGate = h.blobs.hold('sidecar');
      final intake = _Result(h.store.handleOutcome(outcome, channelIndex: 2));
      await tester.pump();
      h.expectCount(1);
      intakeGate.complete();
      await tester.pump();
      expect(intake.completed, isTrue);
      expect(h.reassembler.pendingCount, 1);
      h.expectCount(0);
      final entry = intake.value!;
      final failureGate = h.blobs.hold('sidecar');
      final failed = _Result(h.store.handleFailure(ImageReassemblyFailure(
        key: entry.key, total: entry.totalChunks, receivedDataChunks: 1,
        hadParity: false, firstSeen: entry.firstSeen,
        expiredAt: entry.firstSeen.add(const Duration(seconds: 60)),
      )));
      await tester.pump();
      expect(failed.completed, isFalse);
      h.expectCount(1);
      failureGate.complete();
      await tester.pump();
      expect(failed.completed, isTrue);
      expect(failed.error, isNull);
      expect(h.decoder.jobs, isEmpty);
      h.expectCount(0);
    });
  }, timeout: timeout);

  testWidgets('manual retry holds actual decode without changing its awaited Future', (tester) async {
    await _withImages(tester, (h) async {
      final entry = await h.receive(1);
      h.expectCount(0);
      final retry = _Result(h.store.requestDecode(entry!.streamId));
      await tester.pump();
      expect(retry.completed, isFalse);
      h.expectCount(1);
      h.decoder.succeed(0);
      await tester.pump();
      expect(retry.completed, isTrue);
      expect(retry.error, isNull);
      h.expectCount(0);
    }, automatic: false);
  }, timeout: timeout);

  for (final result in ['failed', 'completed']) {
    testWidgets('background cancellation retains actual $result result until completion', (tester) async {
      await _withImages(tester, (h) async {
        final entry = await h.receive(1);
        await tester.pump();
        h.store.setForeground(false);
        expect(h.decoder.cancels, 1);
        h.expectCount(1);
        if (result == 'completed') {
          h.decoder.succeed(0);
        } else {
          h.decoder.fail(0);
        }
        await tester.pump();
        h.expectCount(0);
        expect(h.store.entryFor(entry!.streamId)!.state,
            result == 'completed' ? ReceivedImageState.decoded : ReceivedImageState.reassembled);
        if (result == 'failed') {
          expect(h.store.decodeQueue, [entry.streamId]);
          h.store.setForeground(true);
          await tester.pump();
          h.expectCount(1);
          h.decoder.succeed(1);
          await tester.pump();
          h.expectCount(0);
        }
      });
    }, timeout: timeout);
  }

  testWidgets('memory pressure requests cancellation without releasing native work', (tester) async {
    await _withImages(tester, (h) async {
      final entry = await h.receive(1);
      await tester.pump();
      await h.store.handleMemoryPressure();
      expect(h.decoder.cancels, 1);
      h.expectCount(1);
      h.decoder.fail(0);
      await tester.pump();
      h.expectCount(0);
      expect(h.store.entryFor(entry!.streamId)!.needsManualDecode, isTrue);
      expect(h.store.decodeQueue, isEmpty);
    });
  }, timeout: timeout);

  for (final mode in ['failed', 'throw', 'unavailable']) {
    testWidgets('native decoder $mode releases work with the original terminal state', (tester) async {
      await _withImages(tester, (h) async {
        final entry = await h.receive(1);
        await tester.pump();
        h.expectCount(1);
        if (mode == 'failed') {
          h.decoder.fail(0);
        } else if (mode == 'throw') {
          h.decoder.jobs.single.completeError(StateError('synthetic decoder failure'));
        } else {
          h.decoder.jobs.single.complete(null);
        }
        await tester.pump();
        expect(h.store.entryFor(entry!.streamId)!.state,
            mode == 'unavailable' ? ReceivedImageState.decoderUnavailable : ReceivedImageState.failedCorrupt);
        h.expectCount(0);
      });
    }, timeout: timeout);
  }

  testWidgets('unavailable codec holds queued state persistence despite never starting a native job', (tester) async {
    await _withImages(tester, (h) async {
      h.decoder.availability = ImageCodecAvailability.unavailable;
      final gate = h.blobs.hold('sidecar');
      var sidecars = 0;
      h.blobs.before = (operation) async {
        if (operation == 'sidecar' && ++sidecars == 2) await gate.future;
      };
      final intake = _Result(h.receive(1));
      await tester.pump();
      expect(intake.completed, isTrue);
      expect(h.store.entries.single.state, ReceivedImageState.decoderUnavailable);
      expect(h.decoder.jobs, isEmpty);
      h.expectCount(1);
      gate.complete();
      await tester.pump();
      h.expectCount(0);
    });
  }, timeout: timeout);

  testWidgets('external settle timeout does not release the running decode', (tester) async {
    await _withImages(tester, (h) async {
      await h.receive(1);
      await tester.pump();
      final wait = _Result(h.store.settle().timeout(const Duration(milliseconds: 1)));
      await tester.pump(const Duration(milliseconds: 1));
      expect(wait.error, isA<TimeoutException>());
      expect(h.decoder.cancels, 0);
      h.expectCount(1);
      h.decoder.succeed(0);
      await tester.pump();
      h.expectCount(0);
    });
  }, timeout: timeout);

  testWidgets('store dispose retains the active decode and discards only the passive queue', (tester) async {
    await _withImages(tester, (h) async {
      await h.receive(1);
      await tester.pump();
      await h.receive(2);
      h.dispose();
      expect(h.store.decodeQueue, isEmpty);
      expect(h.decoder.cancels, 0);
      h.expectCount(1);
      h.decoder.succeed(0);
      await tester.pump();
      expect(h.decoder.jobs, hasLength(1));
      h.expectCount(0);
    });
  }, timeout: timeout);

  testWidgets('late connector adopts work and repeated binding does not duplicate it', (tester) async {
    await _withImages(tester, (h) async {
      h.store.detachBackgroundWorkTracker(h.tracker);
      final gate = h.blobs.hold('bitstream');
      final intake = _Result(h.receive(1));
      await tester.pump();
      h.expectCount(0);
      final connector = h.connector();
      h.expectCount(1, snapshot: connector.backgroundWorkSnapshot);
      final revision = connector.backgroundWorkSnapshot.revision;
      connector.bindImageReceiveBackgroundWork(h.store);
      expect(connector.backgroundWorkSnapshot.revision, revision);
      gate.complete();
      await tester.pump();
      expect(intake.completed, isTrue);
      h.expectCount(0, snapshot: connector.backgroundWorkSnapshot);
    }, automatic: false);
  }, timeout: timeout);

  testWidgets('connector dispose retains work and replacement adopts it without new leases on the old tracker', (tester) async {
    await _withImages(tester, (h) async {
      final old = h.connector();
      await h.receive(1);
      await tester.pump();
      old.dispose();
      expect(old.backgroundWorkSnapshot.isClosed, isTrue);
      h.expectCount(1, snapshot: old.backgroundWorkSnapshot);
      final current = h.connector();
      h.expectCount(1, snapshot: current.backgroundWorkSnapshot);
      final revision = old.backgroundWorkSnapshot.revision;
      final parked = await h.receive(2);
      expect(parked, isNotNull);
      expect(old.backgroundWorkSnapshot.revision, revision);
      h.expectCount(1, snapshot: current.backgroundWorkSnapshot);
      h.decoder.succeed(0);
      await tester.pump();
      h.expectCount(0, snapshot: old.backgroundWorkSnapshot);
      h.expectCount(1, snapshot: current.backgroundWorkSnapshot);
      h.decoder.succeed(1);
      await tester.pump();
      h.expectCount(0, snapshot: current.backgroundWorkSnapshot);
      h.expectCount(0);
    });
  }, timeout: timeout);

  testWidgets('switching stores retains old actual work and binding null stops future registration', (tester) async {
    await _withImages(tester, (h) async {
      final connector = h.connector();
      await h.receive(1);
      await tester.pump();
      final replacement = ReceivedImageStore(processAutomatically: false);
      try {
        connector.bindImageReceiveBackgroundWork(replacement);
        h.expectCount(1, snapshot: connector.backgroundWorkSnapshot);
        final revision = connector.backgroundWorkSnapshot.revision;
        final second = _Result(h.receive(2));
        await tester.pump();
        expect(second.completed, isTrue);
        expect(connector.backgroundWorkSnapshot.revision, revision);
        h.decoder.succeed(0);
        await tester.pump();
        h.expectCount(0, snapshot: connector.backgroundWorkSnapshot);
        h.expectCount(1);
        h.decoder.succeed(1);
        await tester.pump();
        h.expectCount(0);
        final before = connector.backgroundWorkSnapshot.revision;
        final incoming = _Result(replacement.handleOutcome(
          ImageReassembler().addChunk(h.chunks(3).blobs.first, channelIndex: 2),
          channelIndex: 2,
        ));
        await tester.pump();
        expect(incoming.completed, isTrue);
        expect(connector.backgroundWorkSnapshot.revision, greaterThan(before));
        connector.bindImageReceiveBackgroundWork(null);
        final detached = connector.backgroundWorkSnapshot.revision;
        await replacement.handleOutcome(const ImageChunkOutcome(ImageChunkStatus.malformed), channelIndex: 2);
        expect(connector.backgroundWorkSnapshot.revision, detached);
      } finally {
        replacement.dispose();
      }
    });
  }, timeout: timeout);

  testWidgets('caught sidecar failure and rejected bitstream do not leave active leases', (tester) async {
    await _withImages(tester, (h) async {
      h.blobs.sidecarFails = true;
      final first = _Result(h.receive(1));
      await tester.pump();
      expect(first.completed, isTrue);
      expect(first.error, isNull);
      h.expectCount(0);
      h.blobs.sidecarFails = false;
      h.blobs.bitstreamWritten = false;
      final second = _Result(h.receive(2));
      await tester.pump();
      expect(second.completed, isTrue);
      expect(second.value!.state, ReceivedImageState.failedCorrupt);
      h.expectCount(0);
    }, automatic: false);
  }, timeout: timeout);

  testWidgets('propagated bitstream exception releases intake and retains error identity', (tester) async {
    await _withImages(tester, (h) async {
      final error = StateError('synthetic bitstream failure');
      h.blobs.before = (operation) async {
        if (operation == 'bitstream') throw error;
      };
      final intake = _Result(h.receive(1));
      await tester.pump();
      expect(intake.completed, isTrue);
      expect(intake.error, same(error));
      h.expectCount(0);
    });
  }, timeout: timeout);
}
