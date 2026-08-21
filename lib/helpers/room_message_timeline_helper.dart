import '../models/message.dart';

abstract final class RoomMessageTimelineHelper {
  static DateTime orderAt(Message message) =>
      message.receivedAt ?? message.timestamp;

  static int compare(Message a, Message b) {
    final receivedCompare = orderAt(a).compareTo(orderAt(b));
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
}
