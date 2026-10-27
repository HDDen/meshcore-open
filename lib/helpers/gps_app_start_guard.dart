import 'south_frame_fragment_reassembler.dart';
import 'south_queued_fragment_ack_tracker.dart';

/// APP_START сбрасывает сессию прошивки; фоновый GPS-тик может подождать.
bool shouldDeferGpsAppStart({
  required bool loadingContacts,
  required bool awaitingSelfInfo,
  required bool syncingQueuedMessages,
  required bool queuedMessageInFlight,
  required SouthFrameFragmentReassembler fragments,
  required SouthQueuedFragmentAckTracker queuedAcks,
  DateTime? now,
}) {
  if (loadingContacts ||
      awaitingSelfInfo ||
      syncingQueuedMessages ||
      queuedMessageInFlight ||
      queuedAcks.awaitingSyncResponse) {
    return true;
  }
  // pendingAck без активного обмена остаётся после ошибки/timeout очереди:
  // он не должен навсегда выключать GPS. Неполные наборы живут по прежнему TTL.
  return fragments.hasPendingFragments(now: now);
}
