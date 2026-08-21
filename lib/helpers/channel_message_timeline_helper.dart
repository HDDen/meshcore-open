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
    if (previous == null || now.isAfter(previous)) return now;
    return previous.add(const Duration(seconds: 1));
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
