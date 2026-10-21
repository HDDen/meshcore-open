import '../utils/app_logger.dart';

enum TelemetryParseIssueKind {
  unknownType,
  malformedField,
  incompleteHeader,
  truncatedPolyline,
}

/// Offsets refer to the LPP payload, excluding the response frame header.
class TelemetryParseIssue {
  final TelemetryParseIssueKind kind;
  final int offset;
  final int packetLength;
  final int? channel;
  final int? type;

  const TelemetryParseIssue({
    required this.kind,
    required this.offset,
    required this.packetLength,
    this.channel,
    this.type,
  });
}

void reportTelemetryParseIssue({
  required TelemetryParseIssueKind kind,
  required int offset,
  required int packetLength,
  int? channel,
  int? type,
  void Function(TelemetryParseIssue issue)? onIssue,
}) {
  final issue = TelemetryParseIssue(
    kind: kind,
    offset: offset,
    packetLength: packetLength,
    channel: channel,
    type: type,
  );
  appLogger.warn(
    'Incomplete Cayenne LPP telemetry: ${kind.name}, '
    'channel=$channel, type=$type, offset=$offset, bytes=$packetLength; '
    'retaining decoded fields',
    tag: 'Telemetry',
  );
  onIssue?.call(issue);
}

/// Log field names only: useful for missing-sensor reports without a raw dump.
void logTelemetryChannels(
  List<Map<String, dynamic>> channels, {
  required int packetLength,
}) {
  if (!appLogger.isEnabled) {
    return;
  }
  final fields = channels
      .map((channel) {
        final values = channel['values'] as Map<String, dynamic>;
        return '${channel['channel']}:[${values.keys.join(',')}]';
      })
      .join('; ');
  appLogger.info(
    'Decoded Cayenne LPP telemetry: bytes=$packetLength, channels={$fields}',
    tag: 'Telemetry',
  );
}
