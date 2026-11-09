import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/services/message_filter/duplicate_tracker.dart';

void main() {
  final start = DateTime.utc(2026, 1, 1, 12);
  const campaign = 'join the local mesh channel today';

  FilterReason? check(
    DuplicateTracker tracker, {
    String channel = 'a',
    String sender = 'Bob',
    String text = campaign,
    int sentMinutes = 0,
    int receivedMinutes = 0,
  }) => tracker.check(
    channelId: channel,
    sender: sender,
    textKey: text,
    sentAt: start.add(Duration(minutes: sentMinutes)),
    receivedAt: start.add(Duration(minutes: receivedMinutes)),
  );

  test('out-of-order matches use sender time and stay within one channel', () {
    final tracker = DuplicateTracker();
    expect(check(tracker, sentMinutes: 10), isNull);
    expect(check(tracker, channel: 'b', receivedMinutes: 1), isNull);
    expect(
      check(tracker, receivedMinutes: 1),
      FilterReason.duplicate,
    );
    expect(
      check(tracker, sentMinutes: 21, receivedMinutes: 2),
      isNull,
    );
  });

  test('a late inbox burst and an expired entry do not count', () {
    final tracker = DuplicateTracker();
    expect(check(tracker), isNull);
    expect(check(tracker, sentMinutes: 180), isNull);
    expect(check(tracker, sentMinutes: 1, receivedMinutes: 31), isNull);
  });

  test('third distinct sender counts only for sentence-length text', () {
    final tracker = DuplicateTracker();
    for (final sender in ['A', 'B', 'C']) {
      expect(check(tracker, sender: sender, text: 'happy new year'), isNull);
    }
    expect(check(tracker, sender: 'A'), isNull);
    expect(check(tracker, sender: 'B', sentMinutes: 1), isNull);
    expect(
      check(tracker, sender: 'C', sentMinutes: 30),
      FilterReason.crossSenderDuplicate,
    );
    expect(
      check(tracker, sender: 'C', sentMinutes: 31),
      FilterReason.duplicate,
    );
  });

  test('a busy channel only evicts its own oldest publications', () {
    final tracker = DuplicateTracker();
    expect(check(tracker, channel: 'quiet'), isNull);

    String text(int id) => 'distinct test publication $id';
    for (var id = 0; id < 4001; id++) {
      check(tracker, channel: 'busy-a', text: text(id));
      check(tracker, channel: 'busy-b', text: text(id));
    }

    expect(check(tracker, channel: 'quiet'), FilterReason.duplicate);
    // Each check inserts a publication, so probe the boundary in two channels.
    expect(check(tracker, channel: 'busy-a', text: text(3000)), isNull);
    expect(
      check(tracker, channel: 'busy-b', text: text(3001)),
      FilterReason.duplicate,
    );
  });

  test('capacity evicts the oldest entry and allowances stay in one channel', () {
    final tracker = DuplicateTracker(maxEntriesPerChannel: 2);
    expect(check(tracker), isNull);
    expect(check(tracker, text: 'second distinct publication'), isNull);
    expect(check(tracker, text: 'third distinct publication'), isNull);
    expect(check(tracker), isNull);
    tracker.allow('a', campaign);
    expect(check(tracker), isNull);
    expect(check(tracker, channel: 'b'), isNull);
    expect(check(tracker, channel: 'b'), FilterReason.duplicate);
  });
}
