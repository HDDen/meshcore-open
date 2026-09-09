import '../models/channel_message.dart';

abstract final class ChannelMessageTimelineHelper {
  static int compare(ChannelMessage a, ChannelMessage b) {
    final receivedCompare = a.receivedAt.compareTo(b.receivedAt);
    if (receivedCompare != 0) return receivedCompare;
    return a.messageId.compareTo(b.messageId);
  }

  static DateTime nextBacklogReceivedAt({
    required DateTime now,
    DateTime? previous,
  }) {
    if (previous == null ||
        now.millisecondsSinceEpoch > previous.millisecondsSinceEpoch) {
      return now;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      previous.millisecondsSinceEpoch + 1,
      isUtc: previous.isUtc,
    );
  }

  static DateTime earliestReceivedAt(
    ChannelMessage existing,
    ChannelMessage incoming,
  ) {
    if (existing.isOutgoing) return existing.receivedAt;
    return incoming.receivedAt.isBefore(existing.receivedAt)
        ? incoming.receivedAt
        : existing.receivedAt;
  }

  static ChannelMessage markFirstRadioTransmission(
    ChannelMessage message,
    DateTime sentAt,
  ) {
    if (!message.isOutgoing) return message;
    final firstSentAt = message.sentByRadioAt ?? sentAt;
    if (message.sentByRadioAt == firstSentAt &&
        message.receivedAt == firstSentAt) {
      return message;
    }
    return message.copyWith(
      sentByRadioAt: firstSentAt,
      receivedAt: firstSentAt,
    );
  }
}

typedef ChannelMessageMerger =
    List<ChannelMessage> Function(
      List<ChannelMessage> primary,
      List<ChannelMessage> secondary,
    );

/// Keeps the display timeline stable while unrelated connector state changes.
class ChannelMessageTimelineCache {
  final Map<int, _ChannelMessageTimelineEntry> _entries = {};

  List<ChannelMessage> resolve({
    required int channelIndex,
    required List<ChannelMessage> primary,
    required List<ChannelMessage> secondary,
    required List<ChannelMessage> pending,
    required int filterRevision,
    required String filterKey,
    required ChannelMessageMerger merge,
    required bool Function(ChannelMessage message) include,
  }) {
    final cached = _entries[channelIndex];
    if (cached != null &&
        cached.filterRevision == filterRevision &&
        cached.filterKey == filterKey &&
        _sameMessages(cached.primary, primary) &&
        _sameMessages(cached.secondary, secondary) &&
        _sameMessages(cached.pending, pending)) {
      return cached.timeline;
    }

    final historical = secondary.isEmpty
        ? primary
        : merge(primary, secondary);
    final timeline = <ChannelMessage>[
      for (final message in historical)
        if (include(message)) message,
      ...pending,
    ]..sort(ChannelMessageTimelineHelper.compare);
    final result = List<ChannelMessage>.unmodifiable(timeline);
    _entries[channelIndex] = _ChannelMessageTimelineEntry(
      primary: List<ChannelMessage>.of(primary),
      secondary: List<ChannelMessage>.of(secondary),
      pending: List<ChannelMessage>.of(pending),
      filterRevision: filterRevision,
      filterKey: filterKey,
      timeline: result,
    );
    return result;
  }

  static bool _sameMessages(
    List<ChannelMessage> previous,
    List<ChannelMessage> current,
  ) {
    if (previous.length != current.length) return false;
    for (var index = 0; index < current.length; index++) {
      if (!identical(previous[index], current[index])) return false;
    }
    return true;
  }
}

class _ChannelMessageTimelineEntry {
  const _ChannelMessageTimelineEntry({
    required this.primary,
    required this.secondary,
    required this.pending,
    required this.filterRevision,
    required this.filterKey,
    required this.timeline,
  });

  final List<ChannelMessage> primary;
  final List<ChannelMessage> secondary;
  final List<ChannelMessage> pending;
  final int filterRevision;
  final String filterKey;
  final List<ChannelMessage> timeline;
}
