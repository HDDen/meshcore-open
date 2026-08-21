const Duration mcmpTimestampWarningThreshold = Duration(minutes: 30);

/// Detects a suspicious clock mismatch; it does not establish message
/// freshness or prove that a replay occurred.
abstract final class McmpTimestampWarning {
  static int? differenceSeconds({
    required DateTime packetTimestamp,
    required int? mcmpTimestamp,
  }) {
    if (mcmpTimestamp == null) return null;
    final packetTimestampSeconds =
        packetTimestamp.millisecondsSinceEpoch ~/ 1000;
    return (mcmpTimestamp - packetTimestampSeconds).abs();
  }

  static int? suspiciousDifferenceSeconds({
    required DateTime packetTimestamp,
    required int? mcmpTimestamp,
  }) {
    final difference = differenceSeconds(
      packetTimestamp: packetTimestamp,
      mcmpTimestamp: mcmpTimestamp,
    );
    if (difference == null ||
        difference <= mcmpTimestampWarningThreshold.inSeconds) {
      return null;
    }
    return difference;
  }
}
