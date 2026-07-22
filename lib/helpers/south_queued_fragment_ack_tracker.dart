import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import 'south_frame_fragment_reassembler.dart';

class SouthPendingQueuedFragmentAck {
  const SouthPendingQueuedFragmentAck({
    required this.fragmentId,
    required this.fragmentIndex,
  });

  final int fragmentId;
  final int fragmentIndex;
}

class SouthQueuedFragmentAckTracker {
  SouthPendingQueuedFragmentAck? _pendingAck;
  bool _awaitingSyncResponse = false;

  SouthPendingQueuedFragmentAck? get pendingAck => _pendingAck;
  bool get awaitingSyncResponse => _awaitingSyncResponse;

  Uint8List buildSyncNextMessageFrameFor({required bool enabled}) {
    final ack = enabled ? _pendingAck : null;
    if (ack == null) return buildSyncNextMessageFrame();
    return buildSyncNextMessageFrame(
      ackFragmentId: ack.fragmentId,
      ackFragmentIndex: ack.fragmentIndex,
    );
  }

  void markSyncRequestSent() => _awaitingSyncResponse = true;

  void clearAwaitingSyncResponse() => _awaitingSyncResponse = false;

  bool takeSyncResponseContext(
    Uint8List frame, {
    required bool isAcceptedQueuedFragment,
  }) {
    if (!_awaitingSyncResponse ||
        !_isSyncNextMessageResponseFrame(
          frame,
          isAcceptedQueuedFragment: isAcceptedQueuedFragment,
        )) {
      return false;
    }
    _awaitingSyncResponse = false;
    _pendingAck = null;
    return true;
  }

  void recordQueuedFragment(
    SouthFrameFragmentInfo fragment, {
    required bool enabled,
  }) {
    if (!enabled || !fragment.isQueued) return;
    _pendingAck = SouthPendingQueuedFragmentAck(
      fragmentId: fragment.fragmentId,
      fragmentIndex: fragment.fragmentIndex,
    );
  }

  void clear() {
    _pendingAck = null;
    _awaitingSyncResponse = false;
  }

  bool _isSyncNextMessageResponseFrame(
    Uint8List frame, {
    required bool isAcceptedQueuedFragment,
  }) {
    if (frame.isEmpty) return false;
    if (frame[0] == SouthFrameFragmentReassembler.fragmentFrameType) {
      return isAcceptedQueuedFragment;
    }
    switch (frame[0]) {
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
