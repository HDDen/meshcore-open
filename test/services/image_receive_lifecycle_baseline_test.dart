import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
  }
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
  }
}

void main() {
  const timeout = Timeout(Duration(seconds: 30));

  testWidgets('baseline: bitstream is written before the completed entry is published', (tester) async {
    await _withImages(tester, (h) async {
      final gate = h.blobs.hold('bitstream');
      final intake = _Result(h.receive(1));
      await tester.pump();
      expect(intake.completed, isFalse);
      expect(h.store.entries, isEmpty);
      expect(h.blobs.calls, ['bitstream']);
      gate.complete();
      await tester.pump();
      expect(intake.completed, isTrue);
      expect(intake.error, isNull);
      final entry = h.store.entries.single;
      expect(entry.state, ReceivedImageState.reassembled);
      expect(entry.needsManualDecode, isTrue);
      expect(h.blobs.hasBitstream(entry.streamId), isTrue);
      expect(h.decoder.jobs, isEmpty);
    }, automatic: false);
  }, timeout: timeout);

  testWidgets('baseline: state is published before awaited sidecar commit', (tester) async {
    await _withImages(tester, (h) async {
      final gate = h.blobs.hold('sidecar');
      final intake = _Result(h.receive(1));
      await tester.pump();
      final entry = h.store.entries.single;
      expect(entry.state, ReceivedImageState.reassembled);
      expect(h.blobs.hasBitstream(entry.streamId), isTrue);
      expect(await h.blobs.readSidecars(), isEmpty);
      expect(intake.completed, isFalse);
      gate.complete();
      await tester.pump();
      expect(intake.completed, isTrue);
      expect(intake.error, isNull);
      final saved = jsonDecode((await h.blobs.readSidecars())[entry.streamId]!);
      expect(saved['state'], ReceivedImageState.reassembled.name);
    }, automatic: false);
  }, timeout: timeout);

  testWidgets('baseline: intake returns before decode and settle waits through PNG commit', (tester) async {
    await _withImages(tester, (h) async {
      final intake = _Result(h.receive(1));
      await tester.pump();
      expect(intake.completed, isTrue);
      expect(intake.error, isNull);
      expect(h.decoder.active, 1);
      expect(h.store.entries.single.state, ReceivedImageState.decoding);
      final settled = _Result(h.store.settle());
      final gate = h.blobs.hold('png');
      h.decoder.succeed(0);
      await tester.pump();
      expect(h.decoder.active, 0);
      expect(h.store.entries.single.state, ReceivedImageState.decoding);
      expect(settled.completed, isFalse);
      gate.complete();
      await tester.pump();
      expect(settled.completed, isTrue);
      expect(settled.error, isNull);
      final entry = h.store.entries.single;
      expect(entry.state, ReceivedImageState.decoded);
      expect(entry.pngStored, isTrue);
      expect(h.blobs.hasPng(entry.streamId), isTrue);
      expect(entry.pngBytes, [1, 2, 3, 4]);
    });
  }, timeout: timeout);

  testWidgets('baseline: manual request waits for its decode after automatic processing was off', (tester) async {
    await _withImages(tester, (h) async {
      final entry = await h.receive(1);
      expect(entry!.needsManualDecode, isTrue);
      final request = _Result(h.store.requestDecode(entry.streamId));
      await tester.pump();
      expect(request.completed, isFalse);
      expect(h.decoder.jobs, hasLength(1));
      h.decoder.succeed(0);
      await tester.pump();
      expect(request.completed, isTrue);
      expect(request.error, isNull);
      expect(h.store.entryFor(entry.streamId)!.state, ReceivedImageState.decoded);
    }, automatic: false);
  }, timeout: timeout);

  testWidgets('baseline: enabling automatic processing does not decode the old manual backlog', (tester) async {
    await _withImages(tester, (h) async {
      final old = await h.receive(1);
      h.store.processAutomatically = true;
      h.store.notifyDecoderChanged();
      await tester.pump();
      expect(h.decoder.jobs, isEmpty);
      expect(h.store.entryFor(old!.streamId)!.needsManualDecode, isTrue);
      final incoming = _Result(h.receive(2));
      await tester.pump();
      expect(incoming.completed, isTrue);
      expect(h.decoder.jobs, hasLength(1));
      h.decoder.succeed(0);
      await tester.pump();
      expect(h.store.entryFor(old.streamId)!.state, ReceivedImageState.reassembled);
      expect(h.store.entryFor(incoming.value!.streamId)!.state, ReceivedImageState.decoded);
    }, automatic: false);
  }, timeout: timeout);

  testWidgets('baseline: background queue is parked even though isDecoding stays true', (tester) async {
    await _withImages(tester, (h) async {
      h.store.setForeground(false);
      final entry = await h.receive(1);
      await h.store.settle();
      expect(h.store.decodeQueue, [entry!.streamId]);
      expect(h.store.isDecoding, isTrue);
      expect(h.decoder.jobs, isEmpty);
      h.store.setForeground(true);
      await tester.pump();
      expect(h.decoder.active, 1);
      h.decoder.succeed(0);
      await tester.pump();
      expect(h.store.entryFor(entry.streamId)!.state, ReceivedImageState.decoded);
    });
  }, timeout: timeout);

  testWidgets('baseline: busy encoder parks decode until an explicit change notification', (tester) async {
    await _withImages(tester, (h) async {
      h.decoder.isBusy = true;
      final entry = await h.receive(1);
      await h.store.settle();
      expect(h.store.decodeQueue, [entry!.streamId]);
      expect(h.store.isDecoding, isTrue);
      expect(h.decoder.jobs, isEmpty);
      h.decoder.isBusy = false;
      await tester.pump();
      expect(h.decoder.jobs, isEmpty);
      h.store.notifyDecoderChanged();
      await tester.pump();
      expect(h.decoder.active, 1);
      h.decoder.succeed(0);
      await tester.pump();
      expect(h.store.isDecoding, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: two arrivals decode serially while both intake Futures finish', (tester) async {
    await _withImages(tester, (h) async {
      final first = _Result(h.receive(1));
      await tester.pump();
      final second = _Result(h.receive(2));
      await tester.pump();
      expect(first.completed && second.completed, isTrue);
      expect(h.decoder.jobs, hasLength(1));
      expect(h.store.decodeQueue, [second.value!.streamId]);
      h.decoder.succeed(0);
      await tester.pump();
      expect(h.store.entryFor(first.value!.streamId)!.state, ReceivedImageState.decoded);
      expect(h.decoder.jobs, hasLength(2));
      expect(h.decoder.active, 1);
      expect(h.decoder.maxActive, 1);
      h.decoder.succeed(1);
      await tester.pump();
      expect(h.store.entryFor(second.value!.streamId)!.state, ReceivedImageState.decoded);
      expect(h.store.isDecoding, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: background cancellation does not finish native work and failed decode is requeued', (tester) async {
    await _withImages(tester, (h) async {
      final entry = await h.receive(1);
      await tester.pump();
      final settled = _Result(h.store.settle());
      h.store.setForeground(false);
      await tester.pump();
      expect(h.decoder.cancels, 1);
      expect(h.decoder.active, 1);
      expect(settled.completed, isFalse);
      h.decoder.fail(0);
      await tester.pump();
      expect(settled.completed, isTrue);
      expect(h.store.entryFor(entry!.streamId)!.state, ReceivedImageState.reassembled);
      expect(h.store.decodeQueue, [entry.streamId]);
      h.store.setForeground(true);
      await tester.pump();
      expect(h.decoder.jobs, hasLength(2));
      h.decoder.succeed(1);
      await tester.pump();
      expect(h.store.entryFor(entry.streamId)!.state, ReceivedImageState.decoded);
    });
  }, timeout: timeout);

  testWidgets('baseline: completed native pixels are retained despite a background cancellation request', (tester) async {
    await _withImages(tester, (h) async {
      final entry = await h.receive(1);
      await tester.pump();
      h.store.setForeground(false);
      h.decoder.succeed(0);
      await tester.pump();
      expect(h.decoder.cancels, 1);
      expect(h.store.entryFor(entry!.streamId)!.state, ReceivedImageState.decoded);
      expect(h.store.decodeQueue, isEmpty);
      expect(h.store.isForeground, isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: memory pressure asks for cancellation and parks the result for a manual retry', (tester) async {
    await _withImages(tester, (h) async {
      final entry = await h.receive(1);
      await tester.pump();
      final pressure = _Result(h.store.handleMemoryPressure());
      await tester.pump();
      expect(pressure.completed, isTrue);
      expect(h.decoder.cancels, 1);
      expect(h.decoder.active, 1);
      h.decoder.fail(0);
      await tester.pump();
      final parked = h.store.entryFor(entry!.streamId)!;
      expect(parked.state, ReceivedImageState.reassembled);
      expect(parked.needsManualDecode, isTrue);
      expect(h.store.decodeQueue, isEmpty);
      final retry = _Result(h.store.requestDecode(entry.streamId));
      await tester.pump();
      expect(h.decoder.jobs, hasLength(2));
      h.decoder.succeed(1);
      await tester.pump();
      expect(retry.completed, isTrue);
      expect(retry.error, isNull);
    });
  }, timeout: timeout);

  for (final mode in ['failed', 'throw', 'unavailable']) {
    testWidgets('baseline: decoder $mode keeps its existing terminal state', (tester) async {
      await _withImages(tester, (h) async {
        final entry = await h.receive(1);
        await tester.pump();
        final settled = _Result(h.store.settle());
        if (mode == 'failed') {
          h.decoder.fail(0);
        } else if (mode == 'throw') {
          h.decoder.jobs.single.completeError(StateError('synthetic decoder failure'));
        } else {
          h.decoder.jobs.single.complete(null);
        }
        await tester.pump();
        expect(settled.completed, isTrue);
        expect(settled.error, isNull);
        expect(h.decoder.active, 0);
        expect(h.store.entryFor(entry!.streamId)!.state,
            mode == 'unavailable' ? ReceivedImageState.decoderUnavailable : ReceivedImageState.failedCorrupt);
        expect(h.blobs.hasBitstream(entry.streamId), isTrue);
      });
    }, timeout: timeout);
  }

  testWidgets('baseline: an incomplete stream is passive after its sidecar is written', (tester) async {
    await _withImages(tester, (h) async {
      final chunks = h.chunks(1, length: 400);
      final outcome = h.reassembler.addChunk(chunks.blobs.first, channelIndex: 2);
      final entry = await h.store.handleOutcome(outcome, channelIndex: 2);
      await h.store.settle();
      expect(outcome.status, ImageChunkStatus.accepted);
      expect(h.reassembler.pendingCount, 1);
      expect(entry!.state, ReceivedImageState.receiving);
      expect(h.store.isDecoding, isFalse);
      expect(h.decoder.jobs, isEmpty);
      expect(h.blobs.calls, ['sidecar']);
    });
  }, timeout: timeout);

  testWidgets('baseline: reassembly failure awaits its sidecar without starting decode', (tester) async {
    await _withImages(tester, (h) async {
      final outcome = h.reassembler.addChunk(h.chunks(1, length: 400).blobs.first, channelIndex: 2);
      final entry = await h.store.handleOutcome(outcome, channelIndex: 2);
      final gate = h.blobs.hold('sidecar');
      final failure = _Result(h.store.handleFailure(ImageReassemblyFailure(
        key: entry!.key, total: entry.totalChunks, receivedDataChunks: 1,
        hadParity: false, firstSeen: entry.firstSeen,
        expiredAt: entry.firstSeen.add(const Duration(seconds: 60)),
      )));
      await tester.pump();
      expect(failure.completed, isFalse);
      expect(h.store.entryFor(entry.streamId)!.state, ReceivedImageState.failedIncomplete);
      gate.complete();
      await tester.pump();
      expect(failure.completed, isTrue);
      expect(failure.error, isNull);
      expect(h.decoder.jobs, isEmpty);
    });
  }, timeout: timeout);

  testWidgets('baseline: caller timeout does not cancel the active decode', (tester) async {
    await _withImages(tester, (h) async {
      final entry = await h.receive(1);
      await tester.pump();
      final wait = _Result(h.store.settle().timeout(const Duration(milliseconds: 1)));
      await tester.pump(const Duration(milliseconds: 1));
      expect(wait.completed, isTrue);
      expect(wait.error, isA<TimeoutException>());
      expect(h.decoder.cancels, 0);
      expect(h.decoder.active, 1);
      h.decoder.succeed(0);
      await tester.pump();
      expect(h.store.entryFor(entry!.streamId)!.state, ReceivedImageState.decoded);
    });
  }, timeout: timeout);

  testWidgets('baseline: dispose clears queued work without cancelling the already running decode', (tester) async {
    await _withImages(tester, (h) async {
      final first = await h.receive(1);
      await tester.pump();
      final second = await h.receive(2);
      h.dispose();
      expect(h.store.decodeQueue, isEmpty);
      expect(h.decoder.cancels, 0);
      expect(h.decoder.active, 1);
      h.decoder.succeed(0);
      await tester.pump();
      expect(h.decoder.jobs, hasLength(1));
      expect(h.store.entryFor(first!.streamId)!.state, ReceivedImageState.decoded);
      expect(h.store.entryFor(second!.streamId)!.state, ReceivedImageState.reassembled);
      expect(h.blobs.hasPng(first.streamId), isTrue);
    });
  }, timeout: timeout);

  testWidgets('baseline: sidecar errors are caught and do not change the manual entry', (tester) async {
    await _withImages(tester, (h) async {
      h.blobs.sidecarFails = true;
      final intake = _Result(h.receive(1));
      await tester.pump();
      expect(intake.completed, isTrue);
      expect(intake.error, isNull);
      expect(h.store.entries.single.state, ReceivedImageState.reassembled);
      expect(h.store.entries.single.needsManualDecode, isTrue);
      expect(await h.blobs.readSidecars(), isEmpty);
      expect(h.decoder.jobs, isEmpty);
    }, automatic: false);
  }, timeout: timeout);

  testWidgets('baseline: rejected bitstream write becomes corrupt without decode', (tester) async {
    await _withImages(tester, (h) async {
      h.blobs.bitstreamWritten = false;
      final entry = await h.receive(1);
      await tester.pump();
      expect(entry!.state, ReceivedImageState.failedCorrupt);
      expect(entry.bitstreamStored, isFalse);
      expect(h.decoder.jobs, isEmpty);
      expect(h.blobs.hasBitstream(entry.streamId), isFalse);
    });
  }, timeout: timeout);

  testWidgets('baseline: malformed and self outcomes do not touch blobs or decoder', (tester) async {
    await _withImages(tester, (h) async {
      for (final status in [ImageChunkStatus.malformed, ImageChunkStatus.fromSelf]) {
        expect(await h.store.handleOutcome(ImageChunkOutcome(status), channelIndex: 2), isNull);
      }
      expect(h.blobs.calls, isEmpty);
      expect(h.decoder.jobs, isEmpty);
      expect(h.store.entries, isEmpty);
    });
  }, timeout: timeout);
}
