import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/south_frame_fragment_reassembler.dart';
import 'package:meshcore_open/helpers/south_queued_fragment_ack_tracker.dart';

SouthFrameFragmentInfo _info({required bool queued, int index = 0}) {
  return SouthFrameFragmentInfo(
    fragmentId: 0x1234,
    fragmentIndex: index,
    fragmentCount: 2,
    originalFrameType: respCodeChannelDataRecv,
    originalFrameLength: 177,
    chunkOffset: index * SouthFrameFragmentReassembler.chunkLength,
    chunkLength: index == 0 ? 161 : 16,
    isQueued: queued,
  );
}

void main() {
  group('SouthQueuedFragmentAckTracker', () {
    test('disabled mode always builds legacy sync request', () {
      final tracker = SouthQueuedFragmentAckTracker();
      tracker.recordQueuedFragment(_info(queued: true), enabled: true);

      expect(
        tracker.buildSyncNextMessageFrameFor(enabled: false),
        orderedEquals(<int>[cmdSyncNextMessage]),
      );
    });

    test('queued fragment is ACKed by the next sync request', () {
      final tracker = SouthQueuedFragmentAckTracker();
      final frame = Uint8List.fromList(<int>[
        SouthFrameFragmentReassembler.fragmentFrameType,
      ]);
      tracker.markSyncRequestSent();

      expect(
        tracker.takeSyncResponseContext(frame, isAcceptedQueuedFragment: true),
        isTrue,
      );
      tracker.recordQueuedFragment(_info(queued: true), enabled: true);

      expect(
        tracker.buildSyncNextMessageFrameFor(enabled: true),
        orderedEquals(<int>[cmdSyncNextMessage, 0x01, 0x34, 0x12, 0x00]),
      );
    });

    test('live or invalid FR01 does not consume queue response context', () {
      final tracker = SouthQueuedFragmentAckTracker();
      final frame = Uint8List.fromList(<int>[
        SouthFrameFragmentReassembler.fragmentFrameType,
      ]);
      tracker.markSyncRequestSent();

      expect(
        tracker.takeSyncResponseContext(frame, isAcceptedQueuedFragment: false),
        isFalse,
      );
      expect(tracker.awaitingSyncResponse, isTrue);
    });

    test('normal queue response consumes the previous ACK', () {
      final tracker = SouthQueuedFragmentAckTracker();
      tracker.recordQueuedFragment(_info(queued: true), enabled: true);
      tracker.markSyncRequestSent();

      expect(
        tracker.takeSyncResponseContext(
          Uint8List.fromList(<int>[respCodeNoMoreMessages]),
          isAcceptedQueuedFragment: false,
        ),
        isTrue,
      );
      expect(tracker.pendingAck, isNull);
    });

    test('clear removes ACK and in-flight state', () {
      final tracker = SouthQueuedFragmentAckTracker();
      tracker.recordQueuedFragment(_info(queued: true), enabled: true);
      tracker.markSyncRequestSent();

      tracker.clear();

      expect(tracker.pendingAck, isNull);
      expect(tracker.awaitingSyncResponse, isFalse);
    });
  });
}
