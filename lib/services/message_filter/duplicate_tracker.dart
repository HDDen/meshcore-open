import 'dart:collection';

import '../../models/message_filter.dart';

typedef _TextKey = (String channelId, String text);
typedef _PublicationKey = (String channelId, String sender, Object id);

final class _Publication extends LinkedListEntry<_Publication> {
  _Publication(
    this.key,
    this.sender,
    this.sentAtMs,
    this.receivedAtMs,
    this.publicationKey,
  );

  final _TextKey key;
  final String sender;
  final int sentAtMs;
  final int receivedAtMs;
  final _PublicationKey? publicationKey;
}

/// A bounded, session-local index of separate publications with the same text.
///
/// Compare send times for matches so a replayed inbox does not compress the
/// window between posts. Use local arrival time to expire entries instead.
class DuplicateTracker {
  DuplicateTracker({this.maxEntriesPerChannel = 1000})
    : assert(maxEntriesPerChannel > 0);

  static const _sameSenderWindowMs = 10 * Duration.millisecondsPerMinute;
  static const _crossSenderWindowMs = 30 * Duration.millisecondsPerMinute;
  static const _sameSenderMinWords = 3;
  static const _crossSenderMinWords = 6;

  static const _maxAllowedTexts = 4000;

  final int maxEntriesPerChannel;
  // A channel can evict its own oldest entry from the global expiry order
  // without walking through entries belonging to other channels.
  final _arrivalOrder = LinkedList<_Publication>();
  final _byChannel = <String, ListQueue<_Publication>>{};
  final _byText = <_TextKey, ListQueue<_Publication>>{};
  final _seenPublications = <_PublicationKey>{};
  final _allowed = <_TextKey>{};

  FilterReason? check({
    required String channelId,
    required String sender,
    required String textKey,
    required DateTime sentAt,
    required DateTime receivedAt,
    int sameSenderSends = MessageFilterSettings.minRepeatSends,
    Object? publicationId,
  }) {
    if (textKey.length < 10) return null;
    var words = 1;
    for (var i = 0; i < textKey.length && words < _crossSenderMinWords; i++) {
      if (textKey.codeUnitAt(i) == 0x20) words++;
    }
    if (words < _sameSenderMinWords) return null;

    final key = (channelId, textKey);
    if (_allowed.contains(key)) return null;
    final nowMs = receivedAt.millisecondsSinceEpoch;
    final sentAtMs = sentAt.millisecondsSinceEpoch;
    final crossSenderCutoffMs = nowMs - _crossSenderWindowMs;
    // Five consecutive sends can span forty minutes.
    final sameSenderRetentionMs = (sameSenderSends - 1) * _sameSenderWindowMs;
    final cutoffMs = sameSenderRetentionMs > _crossSenderWindowMs
        ? nowMs - sameSenderRetentionMs
        : crossSenderCutoffMs;
    while (_arrivalOrder.isNotEmpty &&
        _arrivalOrder.first.receivedAtMs < cutoffMs) {
      _drop(_arrivalOrder.first);
    }

    // A copy can be replayed through another node's inbox.
    final publicationKey = publicationId == null
        ? null
        : (channelId, sender, publicationId);
    if (publicationKey != null && !_seenPublications.add(publicationKey)) {
      return null;
    }

    final matches = _byText.putIfAbsent(key, ListQueue.new);
    var nearbySends = 1;
    var crossSenderRepeat = false;
    String? otherSender;
    List<int>? sameSenderTimes;
    for (final entry in matches) {
      final gapMs = (sentAtMs - entry.sentAtMs).abs();
      if (entry.sender == sender) {
        if (gapMs <= _sameSenderWindowMs) {
          nearbySends++;
          if (nearbySends >= sameSenderSends) break;
        }
        if (sameSenderSends > MessageFilterSettings.minRepeatSends) {
          (sameSenderTimes ??= [sentAtMs]).add(entry.sentAtMs);
        }
      } else if (words >= _crossSenderMinWords &&
          gapMs <= _crossSenderWindowMs &&
          entry.receivedAtMs >= crossSenderCutoffMs) {
        if (otherSender != null && otherSender != entry.sender) {
          crossSenderRepeat = true;
        }
        otherSender = entry.sender;
      }
    }
    final sameSenderRepeat =
        nearbySends >= sameSenderSends ||
        (sameSenderTimes != null &&
            sameSenderTimes.length >= sameSenderSends &&
            _hasRepeatRun(sameSenderTimes, sentAtMs, sameSenderSends));

    final publication = _Publication(
      key,
      sender,
      sentAtMs,
      nowMs,
      publicationKey,
    );
    final channel = _byChannel.putIfAbsent(channelId, ListQueue.new);
    _arrivalOrder.add(publication);
    channel.addLast(publication);
    matches.addLast(publication);
    if (channel.length > maxEntriesPerChannel) _drop(channel.first);
    if (sameSenderRepeat) return FilterReason.duplicate;
    return crossSenderRepeat ? FilterReason.crossSenderDuplicate : null;
  }

  // Use chronological neighbours so a late inbox entry can fill a gap.
  static bool _hasRepeatRun(List<int> times, int sentAtMs, int threshold) {
    times.sort();
    var runLength = 0;
    var includesPublication = false;
    var previous = times.first;
    for (final time in times) {
      if (time - previous > _sameSenderWindowMs) {
        if (includesPublication) return false;
        runLength = 0;
      }
      runLength++;
      includesPublication = includesPublication || time == sentAtMs;
      if (includesPublication && runLength >= threshold) return true;
      previous = time;
    }
    return false;
  }

  void _drop(_Publication oldest) {
    final publicationKey = oldest.publicationKey;
    if (publicationKey != null) _seenPublications.remove(publicationKey);
    oldest.unlink();
    final channelId = oldest.key.$1;
    final channel = _byChannel[channelId]!;
    channel.removeFirst();
    if (channel.isEmpty) _byChannel.remove(channelId);
    final bucket = _byText[oldest.key]!;
    bucket.removeFirst();
    if (bucket.isEmpty) _byText.remove(oldest.key);
  }

  void allow(String channelId, String textKey) {
    if (textKey.isEmpty) return;
    final key = (channelId, textKey);
    _allowed.remove(key);
    _allowed.add(key);
    if (_allowed.length > _maxAllowedTexts) _allowed.remove(_allowed.first);
  }
}
