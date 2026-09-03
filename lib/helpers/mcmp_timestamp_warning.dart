const Duration mcmpTimestampWarningThreshold = Duration(minutes: 30);

/// Detects a suspicious clock mismatch between the packet timestamp and the
/// container timestamp (MCMP v3 or MCOtxt v1); it does not establish
/// message freshness or prove that a replay occurred.
abstract final class McmpTimestampWarning {
  static int? differenceSeconds({
    required DateTime packetTimestamp,
    required int? containerTimestamp,
  }) {
    if (containerTimestamp == null) return null;
    final packetTimestampSeconds =
        packetTimestamp.millisecondsSinceEpoch ~/ 1000;
    return (containerTimestamp - packetTimestampSeconds).abs();
  }

  static int? suspiciousDifferenceSeconds({
    required DateTime packetTimestamp,
    required int? containerTimestamp,
  }) {
    final difference = differenceSeconds(
      packetTimestamp: packetTimestamp,
      containerTimestamp: containerTimestamp,
    );
    if (difference == null ||
        difference <= mcmpTimestampWarningThreshold.inSeconds) {
      return null;
    }
    return difference;
  }
}
