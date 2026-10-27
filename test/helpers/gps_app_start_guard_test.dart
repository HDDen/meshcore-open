import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/gps_app_start_guard.dart';
import 'package:meshcore_open/helpers/south_frame_fragment_reassembler.dart';
import 'package:meshcore_open/helpers/south_queued_fragment_ack_tracker.dart';

// Первый фрагмент валидного 177-байтового GRP_DATA; никакого декодирования.
Uint8List _firstFragment() => Uint8List.fromList([
  0xED, 0x46, 0x52, 0x30, 0x31,
  0, 1, 0, 0, 2, respCodeChannelDataRecv, 177, 0, 0, 0,
  respCodeChannelDataRecv, ...List.filled(160, 0),
]);

void main() {
  late SouthFrameFragmentReassembler fragments;
  late SouthQueuedFragmentAckTracker queuedAcks;
  final now = DateTime.utc(2026, 10, 27);

  setUp(() {
    fragments = SouthFrameFragmentReassembler();
    queuedAcks = SouthQueuedFragmentAckTracker();
  });

  bool defer({
    bool loadingContacts = false,
    bool awaitingSelfInfo = false,
    bool syncingQueuedMessages = false,
    bool queuedMessageInFlight = false,
    DateTime? at,
  }) => shouldDeferGpsAppStart(
    loadingContacts: loadingContacts,
    awaitingSelfInfo: awaitingSelfInfo,
    syncingQueuedMessages: syncingQueuedMessages,
    queuedMessageInFlight: queuedMessageInFlight,
    fragments: fragments,
    queuedAcks: queuedAcks,
    now: at ?? now,
  );

  test('idle allows a periodic poll', () {
    expect(defer(), isFalse);
  });

  test('contact and SELF_INFO synchronization retain their own APP_START', () {
    expect(defer(loadingContacts: true), isTrue);
    expect(defer(awaitingSelfInfo: true), isTrue);
    expect(defer(), isFalse);
  });

  test('queue parsing and outstanding writes defer a poll without FR01', () {
    expect(defer(syncingQueuedMessages: true), isTrue);
    expect(defer(queuedMessageInFlight: true), isTrue);
    expect(defer(), isFalse);
  });

  test('an incomplete frame defers until the existing fragment TTL expires', () {
    final result = fragments.ingestDetailed(_firstFragment(), now: now);
    expect(result.acceptedFragment, isNotNull);
    expect(defer(), isTrue);
    expect(defer(at: now.add(const Duration(seconds: 30))), isTrue);
    expect(defer(at: now.add(const Duration(seconds: 30, milliseconds: 1))),
        isFalse);
    expect(defer(at: now.add(const Duration(minutes: 2))), isFalse);
  });

  test('duplicate fragments retain the existing sliding TTL', () {
    fragments.ingestDetailed(_firstFragment(), now: now);
    fragments.ingestDetailed(_firstFragment(),
        now: now.add(const Duration(seconds: 20)));
    expect(defer(at: now.add(const Duration(seconds: 31))), isTrue);
    expect(defer(at: now.add(const Duration(seconds: 51))), isFalse);
  });

  test('a session reset immediately removes the fragment guard', () {
    fragments.ingestDetailed(_firstFragment(), now: now);
    expect(defer(), isTrue);
    fragments.clear();
    expect(defer(), isFalse);
  });

  test('rejected bytes do not hold the poll', () {
    fragments.ingestDetailed(Uint8List.fromList([0xED]), now: now);
    expect(defer(), isFalse);
  });

  test('an outstanding queue response defers until NO_MORE', () {
    queuedAcks.markSyncRequestSent();
    expect(defer(), isTrue);
    queuedAcks.takeSyncResponseContext(
      Uint8List.fromList([respCodeNoMoreMessages]),
      isAcceptedQueuedFragment: false,
    );
    expect(defer(), isFalse);
  });

  test('a stopped queue ACK alone does not hold GPS forever or erase the ACK', () {
    queuedAcks.recordQueuedFragment(
      const SouthFrameFragmentInfo(
        fragmentId: 0x1234,
        fragmentIndex: 1,
        fragmentCount: 2,
        originalFrameType: respCodeChannelDataRecv,
        originalFrameLength: 177,
        chunkOffset: 161,
        chunkLength: 16,
        isQueued: true,
      ),
      enabled: true,
    );
    queuedAcks.markSyncRequestSent();
    expect(defer(), isTrue);
    queuedAcks.clearAwaitingSyncResponse(); // Прежний путь ошибки/timeout.
    expect(defer(), isFalse);
    expect(queuedAcks.buildSyncNextMessageFrameFor(enabled: true),
        [cmdSyncNextMessage, 1, 0x34, 0x12, 1]);
  });
}
