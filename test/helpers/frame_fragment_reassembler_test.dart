import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/frame_fragment_reassembler.dart';

Uint8List _fragment({
  required int id,
  required int index,
  required int count,
  required Uint8List original,
  required int offset,
  required int length,
  int? originalType,
  int? originalLength,
}) {
  final chunk = original.sublist(offset, offset + length);
  return Uint8List.fromList(<int>[
    FrameFragmentReassembler.fragmentFrameType,
    id & 0xFF,
    (id >> 8) & 0xFF,
    index,
    count,
    originalType ?? original[0],
    (originalLength ?? original.length) & 0xFF,
    ((originalLength ?? original.length) >> 8) & 0xFF,
    offset & 0xFF,
    (offset >> 8) & 0xFF,
    ...chunk,
  ]);
}

void main() {
  group('FrameFragmentReassembler', () {
    test('passes non-fragment frames through unchanged', () {
      final reassembler = FrameFragmentReassembler();
      final frame = Uint8List.fromList(<int>[0x05, 0x01, 0x02]);

      final result = reassembler.ingest(frame);

      expect(result, hasLength(1));
      expect(result.single, orderedEquals(frame));
    });

    test('reassembles one frame split into two fragments', () {
      final reassembler = FrameFragmentReassembler();
      final original = Uint8List.fromList(<int>[0x88, 1, 2, 3, 4, 5]);

      expect(
        reassembler.ingest(
          _fragment(
            id: 7,
            index: 0,
            count: 2,
            original: original,
            offset: 0,
            length: 3,
          ),
        ),
        isEmpty,
      );
      final result = reassembler.ingest(
        _fragment(
          id: 7,
          index: 1,
          count: 2,
          original: original,
          offset: 3,
          length: 3,
        ),
      );

      expect(result, hasLength(1));
      expect(result.single, orderedEquals(original));
    });

    test('reports accepted fragment metadata for queued ACK logic', () {
      final reassembler = FrameFragmentReassembler();
      final original = Uint8List.fromList(<int>[0x88, 1, 2, 3, 4, 5]);

      final first = reassembler.ingestDetailed(
        _fragment(
          id: 0x1234,
          index: 0,
          count: 2,
          original: original,
          offset: 0,
          length: 3,
        ),
      );

      expect(first.frames, isEmpty);
      expect(first.acceptedFragment, isNotNull);
      expect(first.acceptedFragment!.fragmentId, equals(0x1234));
      expect(first.acceptedFragment!.fragmentIndex, equals(0));
      expect(first.acceptedFragment!.fragmentCount, equals(2));
      expect(first.acceptedFragment!.originalFrameType, equals(0x88));
      expect(
        first.acceptedFragment!.originalFrameLength,
        equals(original.length),
      );
      expect(first.acceptedFragment!.chunkOffset, equals(0));
      expect(first.acceptedFragment!.chunkLength, equals(3));
    });

    test(
      'reports duplicate identical fragment metadata without rebuilding',
      () {
        final reassembler = FrameFragmentReassembler();
        final original = Uint8List.fromList(<int>[0x11, 1, 2, 3]);
        final first = _fragment(
          id: 0x2222,
          index: 0,
          count: 2,
          original: original,
          offset: 0,
          length: 2,
        );

        expect(reassembler.ingestDetailed(first).acceptedFragment, isNotNull);
        final duplicate = reassembler.ingestDetailed(first);

        expect(duplicate.frames, isEmpty);
        expect(duplicate.acceptedFragment, isNotNull);
        expect(duplicate.acceptedFragment!.fragmentId, equals(0x2222));
        expect(duplicate.acceptedFragment!.fragmentIndex, equals(0));
      },
    );

    test('does not report metadata for invalid fragment', () {
      final warnings = <String>[];
      final reassembler = FrameFragmentReassembler(onWarning: warnings.add);

      final result = reassembler.ingestDetailed(
        Uint8List.fromList(<int>[
          FrameFragmentReassembler.fragmentFrameType,
          0x01,
        ]),
      );

      expect(result.frames, isEmpty);
      expect(result.acceptedFragment, isNull);
      expect(warnings.last, contains('short frame fragment'));
    });

    test('reassembles fragments received out of order', () {
      final reassembler = FrameFragmentReassembler();
      final original = Uint8List.fromList(<int>[0x27, 10, 11, 12, 13, 14]);

      expect(
        reassembler.ingest(
          _fragment(
            id: 8,
            index: 1,
            count: 2,
            original: original,
            offset: 3,
            length: 3,
          ),
        ),
        isEmpty,
      );
      final result = reassembler.ingest(
        _fragment(
          id: 8,
          index: 0,
          count: 2,
          original: original,
          offset: 0,
          length: 3,
        ),
      );

      expect(result, hasLength(1));
      expect(result.single, orderedEquals(original));
    });

    test('ignores duplicate identical fragment', () {
      final reassembler = FrameFragmentReassembler();
      final original = Uint8List.fromList(<int>[0x11, 1, 2, 3]);
      final first = _fragment(
        id: 9,
        index: 0,
        count: 2,
        original: original,
        offset: 0,
        length: 2,
      );

      expect(reassembler.ingest(first), isEmpty);
      expect(reassembler.ingest(first), isEmpty);
      final result = reassembler.ingest(
        _fragment(
          id: 9,
          index: 1,
          count: 2,
          original: original,
          offset: 2,
          length: 2,
        ),
      );

      expect(result, hasLength(1));
      expect(result.single, orderedEquals(original));
    });

    test('duplicate conflicting fragment drops the pending set', () {
      final warnings = <String>[];
      final reassembler = FrameFragmentReassembler(onWarning: warnings.add);
      final original = Uint8List.fromList(<int>[0x12, 1, 2, 3]);
      final first = _fragment(
        id: 10,
        index: 0,
        count: 2,
        original: original,
        offset: 0,
        length: 2,
      );
      final conflict = Uint8List.fromList(first)..[10] = 0x99;

      expect(reassembler.ingest(first), isEmpty);
      expect(reassembler.ingest(conflict), isEmpty);
      expect(
        reassembler.ingest(
          _fragment(
            id: 10,
            index: 1,
            count: 2,
            original: original,
            offset: 2,
            length: 2,
          ),
        ),
        isEmpty,
      );
      expect(warnings.last, contains('duplicate conflict'));
    });

    test('metadata mismatch drops the pending set', () {
      final warnings = <String>[];
      final reassembler = FrameFragmentReassembler(onWarning: warnings.add);
      final original = Uint8List.fromList(<int>[0x13, 1, 2, 3]);

      expect(
        reassembler.ingest(
          _fragment(
            id: 11,
            index: 0,
            count: 2,
            original: original,
            offset: 0,
            length: 2,
          ),
        ),
        isEmpty,
      );
      expect(
        reassembler.ingest(
          _fragment(
            id: 11,
            index: 1,
            count: 3,
            original: original,
            offset: 2,
            length: 2,
          ),
        ),
        isEmpty,
      );
      expect(warnings.last, contains('metadata mismatch'));
    });

    test('invalid short fragment is ignored', () {
      final warnings = <String>[];
      final reassembler = FrameFragmentReassembler(onWarning: warnings.add);

      final result = reassembler.ingest(
        Uint8List.fromList(<int>[
          FrameFragmentReassembler.fragmentFrameType,
          0x01,
        ]),
      );

      expect(result, isEmpty);
      expect(warnings.last, contains('short frame fragment'));
    });

    test('chunk offset out of bounds is ignored', () {
      final warnings = <String>[];
      final reassembler = FrameFragmentReassembler(onWarning: warnings.add);
      final original = Uint8List.fromList(<int>[0x14, 1, 2, 3]);

      final bad = _fragment(
        id: 12,
        index: 0,
        count: 1,
        original: original,
        offset: 0,
        length: 2,
        originalLength: 1,
      );
      final result = reassembler.ingest(bad);

      expect(result, isEmpty);
      expect(warnings.last, contains('chunk out of bounds'));
    });

    test('original frame type mismatch drops completed set', () {
      final warnings = <String>[];
      final reassembler = FrameFragmentReassembler(onWarning: warnings.add);
      final original = Uint8List.fromList(<int>[0x16, 1, 2, 3]);

      expect(
        reassembler.ingest(
          _fragment(
            id: 16,
            index: 0,
            count: 2,
            original: original,
            offset: 0,
            length: 2,
            originalType: 0x17,
          ),
        ),
        isEmpty,
      );
      expect(
        reassembler.ingest(
          _fragment(
            id: 16,
            index: 1,
            count: 2,
            original: original,
            offset: 2,
            length: 2,
            originalType: 0x17,
          ),
        ),
        isEmpty,
      );
      expect(warnings.last, contains('original type mismatch'));
    });

    test('clear removes pending fragments', () {
      final reassembler = FrameFragmentReassembler();
      final original = Uint8List.fromList(<int>[0x15, 1, 2, 3]);

      expect(
        reassembler.ingest(
          _fragment(
            id: 13,
            index: 0,
            count: 2,
            original: original,
            offset: 0,
            length: 2,
          ),
        ),
        isEmpty,
      );
      reassembler.clear();
      expect(
        reassembler.ingest(
          _fragment(
            id: 13,
            index: 1,
            count: 2,
            original: original,
            offset: 2,
            length: 2,
          ),
        ),
        isEmpty,
      );
    });

    test('timeout removes pending fragments', () {
      final warnings = <String>[];
      final reassembler = FrameFragmentReassembler(
        timeout: const Duration(seconds: 1),
        onWarning: warnings.add,
      );
      final original = Uint8List.fromList(<int>[0x18, 1, 2, 3]);
      final startedAt = DateTime(2026);

      expect(
        reassembler.ingest(
          _fragment(
            id: 17,
            index: 0,
            count: 2,
            original: original,
            offset: 0,
            length: 2,
          ),
          now: startedAt,
        ),
        isEmpty,
      );
      expect(
        reassembler.ingest(
          _fragment(
            id: 17,
            index: 1,
            count: 2,
            original: original,
            offset: 2,
            length: 2,
          ),
          now: startedAt.add(const Duration(seconds: 2)),
        ),
        isEmpty,
      );
      expect(warnings.last, contains('timeout'));
    });

    test('complete fragment produces exactly one parser-ready frame', () {
      final reassembler = FrameFragmentReassembler();
      final original = Uint8List.fromList(<int>[0x1B, 0x02, 0x00, 0x34]);

      expect(
        reassembler.ingest(
          _fragment(
            id: 14,
            index: 0,
            count: 2,
            original: original,
            offset: 0,
            length: 2,
          ),
        ),
        isEmpty,
      );
      final result = reassembler.ingest(
        _fragment(
          id: 14,
          index: 1,
          count: 2,
          original: original,
          offset: 2,
          length: 2,
        ),
      );

      expect(result, hasLength(1));
      expect(result.single, orderedEquals(original));
    });

    test('reassembled channel data parses like the original single frame', () {
      final reassembler = FrameFragmentReassembler();
      final original = Uint8List.fromList(<int>[
        respCodeChannelDataRecv,
        8,
        0,
        0,
        2,
        0xFF,
        0x20,
        0x01,
        3,
        0xAA,
        0xBB,
        0xCC,
      ]);

      final first = reassembler.ingest(
        _fragment(
          id: 15,
          index: 0,
          count: 2,
          original: original,
          offset: 0,
          length: 6,
        ),
      );
      final second = reassembler.ingest(
        _fragment(
          id: 15,
          index: 1,
          count: 2,
          original: original,
          offset: 6,
          length: 6,
        ),
      );

      expect(first, isEmpty);
      expect(second, hasLength(1));
      final direct = parseChannelDataReceivedFrame(original);
      final reassembled = parseChannelDataReceivedFrame(second.single);
      expect(reassembled, isNotNull);
      expect(reassembled!.channelIndex, equals(direct!.channelIndex));
      expect(reassembled.pathLength, equals(direct.pathLength));
      expect(reassembled.dataType, equals(direct.dataType));
      expect(reassembled.payload, orderedEquals(direct.payload));
      expect(reassembled.snr, equals(direct.snr));
    });
  });
}
