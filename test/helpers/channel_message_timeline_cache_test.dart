import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_message_timeline_helper.dart';
import 'package:meshcore_open/models/channel_message.dart';

// Invariants of the cache behind the channel transcript: the same sources hand
// back the same list object, so the transcript's Selector can compare by
// identity, and any real change to a source hands back a new one.
void main() {
  ChannelMessage message(
    String id,
    int minute, {
    String sender = 'a',
    bool outgoing = false,
  }) {
    final at = DateTime(2026, 9, 20, 12, minute);
    return ChannelMessage(
      messageId: id,
      senderName: sender,
      text: 'message $id',
      timestamp: at,
      receivedAt: at,
      isOutgoing: outgoing,
      channelIndex: 3,
    );
  }

  List<ChannelMessage> concat(
    List<ChannelMessage> primary,
    List<ChannelMessage> secondary,
  ) => [...primary, ...secondary];

  var merges = 0;
  List<ChannelMessage> countingMerge(
    List<ChannelMessage> primary,
    List<ChannelMessage> secondary,
  ) {
    merges++;
    return concat(primary, secondary);
  }

  List<ChannelMessage> resolve(
    ChannelMessageTimelineCache cache, {
    required List<ChannelMessage> primary,
    List<ChannelMessage> secondary = const [],
    List<ChannelMessage> pending = const [],
    int filterRevision = 0,
    String filterKey = 'Public',
    bool Function(ChannelMessage message)? include,
    ChannelMessageMerger? merge,
  }) {
    return cache.resolve(
      channelIndex: 3,
      primary: primary,
      secondary: secondary,
      pending: pending,
      filterRevision: filterRevision,
      filterKey: filterKey,
      merge: merge ?? concat,
      include: include ?? (_) => true,
    );
  }

  setUp(() => merges = 0);

  test('the same sources give the same timeline object without merging again',
      () {
    final cache = ChannelMessageTimelineCache();
    final primary = [message('p1', 1), message('p2', 3)];
    final secondary = [message('s1', 2)];

    final first = resolve(
      cache,
      primary: primary,
      secondary: secondary,
      merge: countingMerge,
    );
    final second = resolve(
      cache,
      primary: primary,
      secondary: secondary,
      merge: countingMerge,
    );

    expect(identical(first, second), isTrue);
    expect(merges, 1);
    // Another list holding the same message objects is the same source too.
    final copy = resolve(
      cache,
      primary: List.of(primary),
      secondary: List.of(secondary),
      merge: countingMerge,
    );
    expect(identical(first, copy), isTrue);
    expect(merges, 1);
  });

  test('a message replaced in place gives a new timeline', () {
    final cache = ChannelMessageTimelineCache();
    final primary = [message('p1', 1), message('p2', 3)];
    final before = resolve(cache, primary: primary);

    primary[1] = primary[1].copyWith(repeatCount: 1);
    final after = resolve(cache, primary: primary);

    expect(identical(before, after), isFalse);
    expect(after.map((m) => m.repeatCount), contains(1));
  });

  test('an appended message and a changed pending list give a new timeline',
      () {
    final cache = ChannelMessageTimelineCache();
    final primary = [message('p1', 1)];
    final first = resolve(cache, primary: primary);

    primary.add(message('p2', 2));
    final grown = resolve(cache, primary: primary);
    expect(identical(first, grown), isFalse);
    expect(grown.length, 2);

    final withPending = resolve(
      cache,
      primary: primary,
      pending: [message('q1', 4, outgoing: true)],
    );
    expect(identical(grown, withPending), isFalse);
    expect(withPending.last.messageId, 'q1');

    final pendingGone = resolve(cache, primary: primary);
    expect(identical(withPending, pendingGone), isFalse);
    expect(pendingGone.length, 2);
  });

  test('a filter revision or key change re-runs the filter', () {
    final cache = ChannelMessageTimelineCache();
    final primary = [message('p1', 1), message('p2', 2, sender: 'eve')];

    final all = resolve(cache, primary: primary);
    expect(all.length, 2);

    // The same revision keeps the cached answer even with another predicate:
    // the revision is the contract, not the closure.
    final stale = resolve(
      cache,
      primary: primary,
      include: (m) => m.senderName != 'eve',
    );
    expect(identical(all, stale), isTrue);

    final filtered = resolve(
      cache,
      primary: primary,
      filterRevision: 1,
      include: (m) => m.senderName != 'eve',
    );
    expect(filtered.map((m) => m.messageId), ['p1']);

    final renamed = resolve(
      cache,
      primary: primary,
      filterRevision: 1,
      filterKey: 'Other',
      include: (m) => m.senderName != 'eve',
    );
    expect(identical(filtered, renamed), isFalse);
  });

  test('the timeline is the merge plus pending, sorted by receipt then id',
      () {
    final cache = ChannelMessageTimelineCache();
    final primary = [message('p3', 5), message('p1', 1)];
    final secondary = [message('s2', 3), message('s0', 1)];
    final pending = [message('q9', 2, outgoing: true)];

    final timeline = resolve(
      cache,
      primary: primary,
      secondary: secondary,
      pending: pending,
    );

    expect(
      timeline.map((m) => m.messageId),
      ['p1', 's0', 'q9', 's2', 'p3'],
    );
    expect(() => timeline.add(message('x', 9)), throwsUnsupportedError);
  });

  test('entries are kept per channel', () {
    final cache = ChannelMessageTimelineCache();
    final three = cache.resolve(
      channelIndex: 3,
      primary: [message('p1', 1)],
      secondary: const [],
      pending: const [],
      filterRevision: 0,
      filterKey: 'Public',
      merge: concat,
      include: (_) => true,
    );
    final four = cache.resolve(
      channelIndex: 4,
      primary: [message('p2', 1)],
      secondary: const [],
      pending: const [],
      filterRevision: 0,
      filterKey: 'Other',
      merge: concat,
      include: (_) => true,
    );
    expect(three.single.messageId, 'p1');
    expect(four.single.messageId, 'p2');
  });

  group('merged history behind the timeline', () {
    test('is empty before the channel was resolved', () {
      expect(ChannelMessageTimelineCache().merged(3), isEmpty);
    });

    test('holds the merge before the filter and without pending sends', () {
      final cache = ChannelMessageTimelineCache();
      final primary = [message('p1', 1), message('p2', 2, sender: 'eve')];
      final secondary = [message('s1', 3)];
      final pending = [message('q1', 4, outgoing: true)];

      final timeline = resolve(
        cache,
        primary: primary,
        secondary: secondary,
        pending: pending,
        filterRevision: 1,
        include: (m) => m.senderName != 'eve',
      );
      final merged = cache.merged(3);

      expect(timeline.map((m) => m.messageId), ['p1', 's1', 'q1']);
      expect(merged.map((m) => m.messageId), ['p1', 'p2', 's1']);
      expect(() => merged.add(message('x', 9)), throwsUnsupportedError);
    });

    test('is the same object while the sources stay, a new one after a change',
        () {
      final cache = ChannelMessageTimelineCache();
      final primary = [message('p1', 1)];

      resolve(cache, primary: primary);
      final first = cache.merged(3);
      resolve(cache, primary: primary);
      expect(identical(first, cache.merged(3)), isTrue);
      // Never the live list itself: it is mutated in place by the receive
      // path, and an index keyed on it would go stale without noticing.
      expect(identical(first, primary), isFalse);

      primary.add(message('p2', 2));
      resolve(cache, primary: primary);
      final second = cache.merged(3);
      expect(identical(first, second), isFalse);
      expect(second.map((m) => m.messageId), ['p1', 'p2']);
    });
  });
}
