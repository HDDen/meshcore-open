import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/image_chunk_transport.dart';
import 'package:meshcore_open/widgets/image_send_codec_binding.dart';

ImageChunkSet _chunks(int id, {int length = 400}) => buildImageChunks(
  payload: Uint8List.fromList(
    List<int>.generate(length, (index) => (index * 37 + id) & 0xff),
  ),
  metadata: const ImageStreamMetadata(rate: ImageCodecRatePoint.standard),
  senderPrefix: 0x1234,
  imgId: id,
);

void main() {
  test('baseline: pending TTL starts at the first chunk', () {
    final start = DateTime.utc(2026, 10, 21);
    var now = start;
    final failures = <ImageReassemblyFailure>[];
    final reassembler = ImageReassembler(
      clock: () => now,
      onFailed: failures.add,
    );
    final chunks = _chunks(1);
    expect(reassembler.ttl, const Duration(seconds: 60));
    reassembler.addChunk(chunks.blobs[0]);
    now = start.add(const Duration(seconds: 30));
    reassembler.addChunk(chunks.blobs[1]);

    now = start.add(const Duration(milliseconds: 59999));
    expect(reassembler.evictExpired(), isEmpty);
    expect(reassembler.pendingCount, 1);
    expect(failures, isEmpty);

    now = start.add(const Duration(seconds: 60));
    final expired = reassembler.evictExpired();
    expect(expired, hasLength(1));
    expect(failures, expired);
    expect(expired.single.firstSeen, start);
    expect(expired.single.expiredAt, now);
    expect(expired.single.receivedDataChunks, 2);
    expect(expired.single.missingChunks, 1);
    expect(reassembler.pendingCount, 0);
    expect(reassembler.completedCount, 0);
    expect(reassembler.evictExpired(), isEmpty);
    expect(failures, hasLength(1));
  });

  test('baseline: completed-only cache expires from completion time', () {
    final start = DateTime.utc(2026, 10, 21);
    var now = start;
    final failures = <ImageReassemblyFailure>[];
    final images = <ImageReassemblyResult>[];
    final reassembler = ImageReassembler(
      clock: () => now,
      onFailed: failures.add,
      onImage: images.add,
    );
    final chunks = _chunks(2, length: 300);
    reassembler.addChunk(chunks.blobs[0]);
    now = start.add(const Duration(seconds: 20));
    expect(
      reassembler.addChunk(chunks.blobs[1]).status,
      ImageChunkStatus.completed,
    );
    expect(reassembler.pendingCount, 0);
    expect(reassembler.completedCount, 1);

    now = start.add(const Duration(seconds: 60));
    expect(reassembler.evictExpired(), isEmpty);
    expect(reassembler.completedCount, 1);
    now = start.add(const Duration(seconds: 70));
    // Поздний parity не должен продлевать время хранения завершённого потока.
    expect(
      reassembler.addChunk(chunks.blobs.last).status,
      ImageChunkStatus.duplicate,
    );
    now = start.add(const Duration(milliseconds: 79999));
    expect(reassembler.evictExpired(), isEmpty);
    expect(reassembler.completedCount, 1);

    now = start.add(const Duration(seconds: 80));
    expect(reassembler.evictExpired(), isEmpty);
    expect(reassembler.pendingCount, 0);
    expect(reassembler.completedCount, 0);
    expect(images, hasLength(1));
    expect(failures, isEmpty);
  });

  test('baseline: a sweep preserves younger pending and completed streams', () {
    final start = DateTime.utc(2026, 10, 21);
    var now = start;
    final failures = <ImageReassemblyFailure>[];
    final reassembler = ImageReassembler(
      clock: () => now,
      onFailed: failures.add,
    );
    reassembler.addChunk(_chunks(1).blobs.first);
    now = start.add(const Duration(seconds: 10));
    reassembler.addChunk(_chunks(2, length: 20).blobs.first);
    now = start.add(const Duration(seconds: 20));
    reassembler.addChunk(_chunks(3).blobs.first);
    expect(reassembler.pendingCount, 2);
    expect(reassembler.completedCount, 1);

    now = start.add(const Duration(seconds: 60));
    expect(reassembler.evictExpired().single.key.imgId, 1);
    expect(reassembler.pendingKeys.single.imgId, 3);
    expect(reassembler.completedKeys.single.imgId, 2);

    now = start.add(const Duration(seconds: 70));
    expect(reassembler.evictExpired(), isEmpty);
    expect(reassembler.completedCount, 0);
    expect(reassembler.pendingKeys.single.imgId, 3);

    now = start.add(const Duration(seconds: 80));
    expect(reassembler.evictExpired().single.key.imgId, 3);
    expect(reassembler.pendingCount, 0);
    expect(reassembler.completedCount, 0);
    expect(failures.map((failure) => failure.key.imgId), [1, 3]);
  });

  test('baseline: expiry callback can start a fresh stream', () {
    final start = DateTime.utc(2026, 10, 21);
    var now = start;
    final failures = <ImageReassemblyFailure>[];
    final fresh = _chunks(2);
    late ImageReassembler reassembler;
    reassembler = ImageReassembler(
      clock: () => now,
      onFailed: (failure) {
        failures.add(failure);
        if (failure.key.imgId == 1) {
          reassembler.addChunk(fresh.blobs.first);
        }
      },
    );
    reassembler.addChunk(_chunks(1).blobs.first);

    now = start.add(const Duration(seconds: 60));
    expect(reassembler.evictExpired().single.key.imgId, 1);
    expect(reassembler.pendingKeys.single.imgId, 2);
    expect(failures, hasLength(1));
    now = start.add(const Duration(milliseconds: 119999));
    expect(reassembler.evictExpired(), isEmpty);
    expect(reassembler.pendingCount, 1);
    now = start.add(const Duration(seconds: 120));
    expect(reassembler.evictExpired().single.key.imgId, 2);
    expect(reassembler.pendingCount, 0);
    expect(failures.map((failure) => failure.key.imgId), [1, 2]);
  });

  test(
    'baseline: channel cleanup preserves other channels and full clear drains both maps',
    () {
      final now = DateTime.utc(2026, 10, 21);
      final failures = <ImageReassemblyFailure>[];
      final reassembler = ImageReassembler(
        clock: () => now,
        onFailed: failures.add,
      );
      reassembler.addChunk(_chunks(1, length: 20).blobs.first, channelIndex: 3);
      reassembler.addChunk(_chunks(2).blobs.first, channelIndex: 3);
      reassembler.addChunk(_chunks(3, length: 20).blobs.first, channelIndex: 7);
      reassembler.addChunk(_chunks(4).blobs.first, channelIndex: 7);
      expect(reassembler.pendingCount, 2);
      expect(reassembler.completedCount, 2);

      reassembler.clearChannel(3);
      expect(reassembler.pendingKeys.single.channelIndex, 7);
      expect(reassembler.completedKeys.single.channelIndex, 7);
      expect(failures.single.key.imgId, 2);
      expect(
        failures.single.reason,
        ImageReassemblyFailureReason.channelChanged,
      );
      reassembler.clearChannel(3);
      expect(failures, hasLength(1));

      reassembler.clear();
      expect(reassembler.pendingCount, 0);
      expect(reassembler.completedCount, 0);
      expect(failures, hasLength(2));
      expect(failures.last.key.imgId, 4);
      expect(
        failures.last.reason,
        ImageReassemblyFailureReason.disconnected,
      );
      expect(
        reassembler.evictExpired(now: now.add(const Duration(minutes: 2))),
        isEmpty,
      );
      expect(failures, hasLength(2));
    },
  );
}
