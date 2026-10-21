import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/cayenne_lpp.dart';
import 'package:meshcore_open/helpers/telemetry_diagnostics.dart';
import 'package:meshcore_open/services/app_debug_log_service.dart';
import 'package:meshcore_open/utils/app_logger.dart';

void main() {
  for (final grouped in [false, true]) {
    final parse = grouped ? CayenneLpp.parseByChannel : CayenneLpp.parse;
    group('telemetry diagnostics (grouped=$grouped)', () {
      test('identifies the unknown type and its LPP field offset', () {
        final issues = <TelemetryParseIssue>[];
        final payload = Uint8List.fromList([
          2, 103, 0x01, 0x1C,
          2, 0xFE, 0x00,
          3, 115, 0x27, 0xFE,
        ]);
        final decoded = parse(payload, onIssue: issues.add);
        expect(decoded.length, 1);
        final issue = issues.single;
        expect(issue.kind, TelemetryParseIssueKind.unknownType);
        expect(issue.channel, 2);
        expect(issue.type, 254);
        expect(issue.offset, 4);
        expect(issue.packetLength, payload.length);
      });

      test('reports a short known field while retaining earlier data', () {
        final issues = <TelemetryParseIssue>[];
        final payload = Uint8List.fromList([
          2, 103, 0x01, 0x1C,
          3, 115, 0x27,
        ]);
        final decoded = parse(payload, onIssue: issues.add);
        expect(decoded.first['channel'], 2);
        final issue = issues.single;
        expect(issue.kind, TelemetryParseIssueKind.malformedField);
        expect(issue.channel, 3);
        expect(issue.type, 115);
        expect(issue.offset, 4);
        expect(issue.packetLength, 7);
      });

      test('reports a lone nonzero channel byte as an incomplete header', () {
        final issues = <TelemetryParseIssue>[];
        parse(Uint8List.fromList([2, 103, 0x01, 0x1C, 3]), onIssue: issues.add);
        final issue = issues.single;
        expect(issue.kind, TelemetryParseIssueKind.incompleteHeader);
        expect(issue.channel, 3);
        expect(issue.type, isNull);
        expect(issue.offset, 4);
      });

      test('reports truncated polyline data without discarding the partial value', () {
        final issues = <TelemetryParseIssue>[];
        final decoded = parse(
          Uint8List.fromList([2, 103, 0x01, 0x1C, 3, 240, 5, 0x11, 0x22]),
          onIssue: issues.add,
        );
        expect(issues.single.kind, TelemetryParseIssueKind.truncatedPolyline);
        expect(issues.single.offset, 4);
        final value = grouped
            ? decoded.last['values']['polyline']
            : decoded.last['value'];
        expect(value, {'size': 5, 'data': '1122'});
      });

      test('valid fields, empty responses and padding produce no warning', () {
        for (final bytes in <List<int>>[
          [],
          [3, 115, 0x27, 0xFE],
          [3, 115, 0x27, 0xFE, 0],
          [3, 115, 0x27, 0xFE, 0, 0],
          [3, 115, 0x27, 0xFE, 0, 0, 0xFF],
        ]) {
          final issues = <TelemetryParseIssue>[];
          parse(Uint8List.fromList(bytes), onIssue: issues.add);
          expect(issues, isEmpty);
        }
      });
    });
  }

  test('debug log contains the issue and channel field names', () {
    final logs = AppDebugLogService();
    appLogger.initialize(logs, enabled: true);
    try {
      final channels = CayenneLpp.parseByChannel(
        Uint8List.fromList([2, 103, 0x01, 0x1C, 2, 0xFE]),
      );
      logTelemetryChannels(channels, packetLength: 6);
      expect(logs.entries.length, 2);
      expect(logs.entries.first.level, AppDebugLogLevel.warning);
      expect(logs.entries.first.tag, 'Telemetry');
      expect(logs.entries.first.message, contains('unknownType'));
      expect(logs.entries.first.message, contains('type=254, offset=4'));
      expect(logs.entries.last.message, contains('2:[temperature]'));
      expect(logs.entries.last.message, isNot(contains('28.4')));
    } finally {
      appLogger.setEnabled(false);
      logs.dispose();
    }
  });
}
