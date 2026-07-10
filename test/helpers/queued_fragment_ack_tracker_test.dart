import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/frame_fragment_reassembler.dart';
import 'package:meshcore_open/helpers/queued_fragment_ack_tracker.dart';

FrameFragmentInfo _fragmentInfo({required int id, required int index}) {
  return FrameFragmentInfo(
    fragmentId: id,
    fragmentIndex: index,
    fragmentCount: 2,
    originalFrameType: respCodeChannelDataRecv,
    originalFrameLength: 20,
    chunkOffset: index * 10,
    chunkLength: 10,
  );
}

Uint8List _fragmentFrame({required int id, required int index}) {
  return Uint8List.fromList(<int>[
    FrameFragmentReassembler.fragmentFrameType,
    id & 0xFF,
    (id >> 8) & 0xFF,
    index,
    2,
    respCodeChannelDataRecv,
    20,
    0,
    (index * 10) & 0xFF,
    0,
    1,
  ]);
}

void main() {
  group('QueuedFragmentAckTracker', () {
    test('first sync request uses old format', () {
      final tracker = QueuedFragmentAckTracker();

      expect(
        tracker.buildSyncNextMessageFrameFor(supportsFragmentAck: true),
        orderedEquals(<int>[cmdSyncNextMessage]),
      );
    });

    test('queued fragment ACK is included in next v14 sync request', () {
      final tracker = QueuedFragmentAckTracker();
      final frame = _fragmentFrame(id: 0x1234, index: 0);

      tracker.markSyncRequestSent();
      expect(tracker.takeSyncResponseContext(frame), isTrue);
      tracker.recordQueuedFragment(
        _fragmentInfo(id: 0x1234, index: 0),
        supportsFragmentAck: true,
      );

      expect(
        tracker.buildSyncNextMessageFrameFor(supportsFragmentAck: true),
        orderedEquals(<int>[cmdSyncNextMessage, 0x01, 0x34, 0x12, 0x00]),
      );
    });

    test('new queued fragment replaces previous pending ACK index', () {
      final tracker = QueuedFragmentAckTracker();

      tracker.markSyncRequestSent();
      expect(
        tracker.takeSyncResponseContext(_fragmentFrame(id: 0x1234, index: 0)),
        isTrue,
      );
      tracker.recordQueuedFragment(
        _fragmentInfo(id: 0x1234, index: 0),
        supportsFragmentAck: true,
      );
      tracker.markSyncRequestSent();
      expect(
        tracker.takeSyncResponseContext(_fragmentFrame(id: 0x1234, index: 1)),
        isTrue,
      );
      tracker.recordQueuedFragment(
        _fragmentInfo(id: 0x1234, index: 1),
        supportsFragmentAck: true,
      );

      expect(
        tracker.buildSyncNextMessageFrameFor(supportsFragmentAck: true),
        orderedEquals(<int>[cmdSyncNextMessage, 0x01, 0x34, 0x12, 0x01]),
      );
    });

    test('last fragment is still ACKed by the next sync request', () {
      final tracker = QueuedFragmentAckTracker();

      tracker.markSyncRequestSent();
      expect(
        tracker.takeSyncResponseContext(_fragmentFrame(id: 0x4321, index: 1)),
        isTrue,
      );
      tracker.recordQueuedFragment(
        _fragmentInfo(id: 0x4321, index: 1),
        supportsFragmentAck: true,
      );

      expect(
        tracker.buildSyncNextMessageFrameFor(supportsFragmentAck: true),
        orderedEquals(<int>[cmdSyncNextMessage, 0x01, 0x21, 0x43, 0x01]),
      );
    });

    test('live fragment does not create pending ACK', () {
      final tracker = QueuedFragmentAckTracker();
      final frame = _fragmentFrame(id: 0x1234, index: 0);

      expect(tracker.takeSyncResponseContext(frame), isFalse);

      expect(
        tracker.buildSyncNextMessageFrameFor(supportsFragmentAck: true),
        orderedEquals(<int>[cmdSyncNextMessage]),
      );
    });

    test('firmware below v14 keeps old sync request even with pending ACK', () {
      final tracker = QueuedFragmentAckTracker();

      tracker.recordQueuedFragment(
        _fragmentInfo(id: 0x1234, index: 0),
        supportsFragmentAck: true,
      );

      expect(
        tracker.buildSyncNextMessageFrameFor(supportsFragmentAck: false),
        orderedEquals(<int>[cmdSyncNextMessage]),
      );
    });

    test('clear removes pending ACK and response wait state', () {
      final tracker = QueuedFragmentAckTracker();

      tracker.markSyncRequestSent();
      tracker.recordQueuedFragment(
        _fragmentInfo(id: 0x1234, index: 0),
        supportsFragmentAck: true,
      );
      tracker.clear();

      expect(tracker.awaitingSyncResponse, isFalse);
      expect(tracker.pendingAck, isNull);
      expect(
        tracker.buildSyncNextMessageFrameFor(supportsFragmentAck: true),
        orderedEquals(<int>[cmdSyncNextMessage]),
      );
    });

    test('non-fragment queued response clears previous pending ACK', () {
      final tracker = QueuedFragmentAckTracker();

      tracker.recordQueuedFragment(
        _fragmentInfo(id: 0x1234, index: 1),
        supportsFragmentAck: true,
      );
      tracker.markSyncRequestSent();
      expect(
        tracker.takeSyncResponseContext(
          Uint8List.fromList(<int>[respCodeNoMoreMessages]),
        ),
        isTrue,
      );

      expect(tracker.pendingAck, isNull);
      expect(
        tracker.buildSyncNextMessageFrameFor(supportsFragmentAck: true),
        orderedEquals(<int>[cmdSyncNextMessage]),
      );
    });

    test('non-sync frame while waiting does not consume pending ACK', () {
      final tracker = QueuedFragmentAckTracker();

      tracker.recordQueuedFragment(
        _fragmentInfo(id: 0x1234, index: 0),
        supportsFragmentAck: true,
      );
      tracker.markSyncRequestSent();
      expect(
        tracker.takeSyncResponseContext(
          Uint8List.fromList(<int>[pushCodeLogRxData]),
        ),
        isFalse,
      );

      expect(
        tracker.buildSyncNextMessageFrameFor(supportsFragmentAck: true),
        orderedEquals(<int>[cmdSyncNextMessage, 0x01, 0x34, 0x12, 0x00]),
      );
    });
  });
}
