import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/quick_actions_header_settings.dart';

void main() {
  test('legacy settings retain the icon and a one-second live-mode default', () {
    final header = AppSettings.fromJson({}).quickActionsHeader;
    expect(header.display, QuickActionsHeaderDisplay.icon);
    expect(header.intervalMsFor(QuickActionsHeaderDisplay.noise), 1000);
  });

  test('all seven steps survive storage and mode changes independently of popup buttons', () {
    expect(QuickActionsHeaderSettings.allowedIntervalsMs, [500, 1000, 2000, 3000, 5000, 7000, 10000]);
    final base = AppSettings();
    for (final milliseconds in QuickActionsHeaderSettings.allowedIntervalsMs) {
      final header = QuickActionsHeaderSettings(display: QuickActionsHeaderDisplay.noise)
          .withInterval(QuickActionsHeaderDisplay.noise, milliseconds);
      final restored = AppSettings.fromJson(jsonDecode(jsonEncode(
        base.copyWith(quickActionsHeader: header).toJson(),
      )) as Map<String, dynamic>);
      expect(restored.quickActionsHeader.display, QuickActionsHeaderDisplay.noise);
      expect(restored.quickActionsHeader.intervalMsFor(QuickActionsHeaderDisplay.noise), milliseconds);
      expect(restored.quickActions.toJson(), base.quickActions.toJson());
      final icon = header.copyWith(display: QuickActionsHeaderDisplay.icon);
      final noise = icon.copyWith(display: QuickActionsHeaderDisplay.noise);
      expect(noise.intervalMsFor(QuickActionsHeaderDisplay.noise), milliseconds);
    }
  });

  test('unknown/unavailable displays and malformed periods are safe defaults', () {
    for (final display in [null, 'unknown', 'extraHops', 1]) {
      expect(QuickActionsHeaderSettings.fromJson({'display': display}).display,
          QuickActionsHeaderDisplay.icon);
    }
    for (final interval in <Object?>[null, '500', 500.0, 0, -1, 501, 10001]) {
      final header = QuickActionsHeaderSettings.fromJson({
        'display': 'noise', 'intervals_ms': {'noise': interval},
      });
      expect(header.display, QuickActionsHeaderDisplay.noise);
      expect(header.intervalMsFor(QuickActionsHeaderDisplay.noise), 1000);
    }
    final input = {QuickActionsHeaderDisplay.noise: 500};
    final header = QuickActionsHeaderSettings(intervalsMs: input);
    input[QuickActionsHeaderDisplay.noise] = 10000;
    expect(header.intervalMsFor(QuickActionsHeaderDisplay.noise), 500);
    expect(header.withInterval(QuickActionsHeaderDisplay.noise, 123)
        .intervalMsFor(QuickActionsHeaderDisplay.noise), 500);
  });
}
