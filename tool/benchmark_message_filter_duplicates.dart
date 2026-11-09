import 'dart:collection';
import 'dart:io';

import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/services/message_filter/duplicate_tracker.dart';

const _capacity = 1000;
const _singleSenderWindowMs = 10 * Duration.millisecondsPerMinute;
const _multiSenderWindowMs = 30 * Duration.millisecondsPerMinute;
const _channel = 'synthetic';

typedef _Post = ({String text, String sender, DateTime at});
typedef _Check = FilterReason? Function(_Post post);

// Upstream scans one channel's recent arrivals. This reference runs that
// search on the same pre-normalized, sentence-length corpus as the index.
class _LinearTracker {
  final _posts = ListQueue<_Post>();

  FilterReason? check(_Post post) {
    final cutoff = post.at.millisecondsSinceEpoch - _multiSenderWindowMs;
    while (_posts.isNotEmpty && _posts.first.at.millisecondsSinceEpoch < cutoff) {
      _posts.removeFirst();
    }
    var sameSender = false;
    final senders = {post.sender};
    for (final previous in _posts) {
      if (previous.text != post.text) continue;
      final gap = post.at.difference(previous.at).inMilliseconds.abs();
      if (previous.sender == post.sender) {
        if (gap <= _singleSenderWindowMs) sameSender = true;
      } else if (gap <= _multiSenderWindowMs) {
        senders.add(previous.sender);
      }
    }
    _posts.addLast(post);
    if (_posts.length > _capacity) _posts.removeFirst();
    if (sameSender) return FilterReason.duplicate;
    return senders.length >= 3 ? FilterReason.crossSenderDuplicate : null;
  }
}

_Check _indexedTracker() {
  final tracker = DuplicateTracker(maxEntriesPerChannel: _capacity);
  return (post) => tracker.check(
    channelId: _channel,
    sender: post.sender,
    textKey: post.text,
    sentAt: post.at,
    receivedAt: post.at,
  );
}

({int elapsedUs, List<FilterReason?> output}) _run(
  List<_Post> corpus,
  _Check check,
) {
  final watch = Stopwatch()..start();
  final output = [for (final post in corpus) check(post)];
  watch.stop();
  return (elapsedUs: watch.elapsedMicroseconds, output: output);
}

void main() {
  final start = DateTime.utc(2026, 1, 1);
  final corpus = <_Post>[
    for (var i = 0; i < 20000; i++)
      (
        text: i % 11 == 0
            ? 'join the local mesh channel today'
            : 'anyone near the local repeater site $i',
        sender: 'sender-${i % 7}',
        at: start.add(Duration(seconds: i)),
      ),
  ];

  stdout.writeln('One channel, pre-normalized texts, capacity=$_capacity.');
  stdout.writeln('Synthetic CPU timing of duplicate lookup and retention.');
  _run(corpus, _LinearTracker().check);
  _run(corpus, _indexedTracker());

  for (var round = 1; round <= 3; round++) {
    final linear = _run(corpus, _LinearTracker().check);
    final indexed = _run(corpus, _indexedTracker());
    var filtered = 0;
    for (var i = 0; i < corpus.length; i++) {
      if (linear.output[i] != indexed.output[i]) {
        throw StateError('Verdict differs at post $i');
      }
      if (indexed.output[i] != null) filtered++;
    }
    stdout.writeln(
      'round=$round posts=${corpus.length} filtered=$filtered '
      'linearUs=${linear.elapsedUs} indexedUs=${indexed.elapsedUs} '
      'verdicts=equal',
    );
  }
}
