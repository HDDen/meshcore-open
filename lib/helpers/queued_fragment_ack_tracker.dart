import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import 'frame_fragment_reassembler.dart';

class PendingQueuedFragmentAck {
  const PendingQueuedFragmentAck({
    required this.fragmentId,
    required this.fragmentIndex,
  });

  final int fragmentId;
  final int fragmentIndex;
}

class QueuedFragmentAckTracker {
  PendingQueuedFragmentAck? _pendingAck;
  bool _awaitingSyncResponse = false;

  PendingQueuedFragmentAck? get pendingAck => _pendingAck;
  bool get awaitingSyncResponse => _awaitingSyncResponse;

  Uint8List buildSyncNextMessageFrameFor({required bool supportsFragmentAck}) {
    final ack = supportsFragmentAck ? _pendingAck : null;
    if (ack == null) return buildSyncNextMessageFrame();
    return buildSyncNextMessageFrame(
      ackFragmentId: ack.fragmentId,
      ackFragmentIndex: ack.fragmentIndex,
    );
  }

  void markSyncRequestSent() {
    _awaitingSyncResponse = true;
  }

  void clearAwaitingSyncResponse() {
    _awaitingSyncResponse = false;
  }

  bool takeSyncResponseContext(Uint8List frame) {
    if (!_awaitingSyncResponse || !_isSyncNextMessageResponseFrame(frame)) {
      return false;
    }
    _awaitingSyncResponse = false;
    _pendingAck = null;
    return true;
  }

  void recordQueuedFragment(
    FrameFragmentInfo fragment, {
    required bool supportsFragmentAck,
  }) {
    if (!supportsFragmentAck) return;
    _pendingAck = PendingQueuedFragmentAck(
      fragmentId: fragment.fragmentId,
      fragmentIndex: fragment.fragmentIndex,
    );
  }

  void clear() {
    _pendingAck = null;
    _awaitingSyncResponse = false;
  }

  bool _isSyncNextMessageResponseFrame(Uint8List frame) {
    if (frame.isEmpty) return false;
    switch (frame[0]) {
      case FrameFragmentReassembler.fragmentFrameType:
      case respCodeContactMsgRecv:
      case respCodeContactMsgRecvV3:
      case respCodeChannelMsgRecv:
      case respCodeChannelMsgRecvV3:
      case respCodeChannelDataRecv:
      case respCodeNoMoreMessages:
      case respCodeErr:
        return true;
      default:
        return false;
    }
  }
}
