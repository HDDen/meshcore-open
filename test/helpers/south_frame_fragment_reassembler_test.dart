import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/south_frame_fragment_reassembler.dart';

Uint8List _fragment({
  required Uint8List original,
  required int id,
  required int index,
  bool queued = false,
  List<int> signature = SouthFrameFragmentReassembler.versionSignature,
  int? flags,
  int? count,
  int? offset,
}) {
  final chunkOffset = offset ??
      index * SouthFrameFragmentReassembler.chunkLength;
  final end = (chunkOffset + SouthFrameFragmentReassembler.chunkLength)
      .clamp(0, original.length)
      .toInt();
  final chunk = chunkOffset <= original.length
      ? original.sublist(chunkOffset, end)
      : <int>[];
  final fragmentCount = count ??
      (original.length + SouthFrameFragmentReassembler.chunkLength - 1) ~/
          SouthFrameFragmentReassembler.chunkLength;
  return Uint8List.fromList(<int>[
    SouthFrameFragmentReassembler.fragmentFrameType,
    ...signature,
    flags ?? (queued ? SouthFrameFragmentReassembler.queuedFlag : 0),
    id & 0xFF,
    (id >> 8) & 0xFF,
    index,
    fragmentCount,
    original[0],
    original.length & 0xFF,
    (original.length >> 8) & 0xFF,
    chunkOffset & 0xFF,
    (chunkOffset >> 8) & 0xFF,
    ...chunk,
  ]);
}

Uint8List _original(int length, {int type = 0x1B}) {
  return Uint8List.fromList(
    List<int>.generate(length, (index) => index == 0 ? type : index & 0xFF),
  );
}

void main() {
  group('SouthFrameFragmentReassembler', () {
    test('passes non-FR01 frames through unchanged', () {
      final reassembler = SouthFrameFragmentReassembler();
      final frame = Uint8List.fromList(<int>[0x05, 1, 2]);

      final result = reassembler.ingestDetailed(frame);

      expect(result.frames.single, same(frame));
      expect(result.acceptedFragment, isNull);
    });

    test('reassembles exact 177-byte boundary and reports queued metadata', () {
      final reassembler = SouthFrameFragmentReassembler();
      final original = _original(177);

      final first = reassembler.ingestDetailed(
        _fragment(original: original, id: 0x1234, index: 0, queued: true),
      );
      final second = reassembler.ingestDetailed(
        _fragment(original: original, id: 0x1234, index: 1, queued: true),
      );

      expect(first.frames, isEmpty);
      expect(first.acceptedFragment?.isQueued, isTrue);
      expect(first.acceptedFragment?.chunkLength, 161);
      expect(second.acceptedFragment?.chunkLength, 16);
      expect(second.frames.single, orderedEquals(original));
    });

    test('reassembles maximum 259-byte live frame', () {
      final reassembler = SouthFrameFragmentReassembler();
      final original = _original(259, type: 0x89);

      expect(
        reassembler
            .ingestDetailed(_fragment(original: original, id: 7, index: 0))
            .frames,
        isEmpty,
      );
      final result = reassembler.ingestDetailed(
        _fragment(original: original, id: 7, index: 1),
      );

      expect(result.acceptedFragment?.isQueued, isFalse);
      expect(result.acceptedFragment?.chunkLength, 98);
      expect(result.frames.single, orderedEquals(original));
    });

    test('rejects unknown signature, flags, and inconsistent geometry', () {
      final warnings = <String>[];
      final reassembler = SouthFrameFragmentReassembler(
        onWarning: warnings.add,
      );
      final original = _original(177);

      expect(
        reassembler
            .ingestDetailed(
              _fragment(
                original: original,
                id: 1,
                index: 0,
                signature: const <int>[0x46, 0x52, 0x30, 0x32],
              ),
            )
            .frames,
        isEmpty,
      );
      expect(
        reassembler
            .ingestDetailed(
              _fragment(original: original, id: 2, index: 0, flags: 0x80),
            )
            .frames,
        isEmpty,
      );
      expect(
        reassembler
            .ingestDetailed(
              _fragment(original: original, id: 3, index: 0, count: 3),
            )
            .frames,
        isEmpty,
      );
      expect(warnings, hasLength(3));
    });

    test('identical duplicate is accepted for repeated queued ACK', () {
      final reassembler = SouthFrameFragmentReassembler();
      final original = _original(177);
      final first = _fragment(
        original: original,
        id: 9,
        index: 0,
        queued: true,
      );

      expect(reassembler.ingestDetailed(first).acceptedFragment, isNotNull);
      final duplicate = reassembler.ingestDetailed(first);

      expect(duplicate.frames, isEmpty);
      expect(duplicate.acceptedFragment?.fragmentIndex, 0);
    });

    test('clear and timeout discard incomplete sets', () {
      final warnings = <String>[];
      final reassembler = SouthFrameFragmentReassembler(
        timeout: const Duration(seconds: 1),
        onWarning: warnings.add,
      );
      final original = _original(177);
      final startedAt = DateTime(2026);

      reassembler.ingestDetailed(
        _fragment(original: original, id: 11, index: 0),
        now: startedAt,
      );
      expect(
        reassembler
            .ingestDetailed(
              _fragment(original: original, id: 12, index: 0),
              now: startedAt.add(const Duration(seconds: 2)),
            )
            .frames,
        isEmpty,
      );
      expect(warnings.last, contains('timeout'));

      reassembler.clear();
      expect(
        reassembler
            .ingestDetailed(_fragment(original: original, id: 12, index: 1))
            .frames,
        isEmpty,
      );
    });
  });
}
