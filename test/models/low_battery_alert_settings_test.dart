import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/low_battery_alert_settings.dart';

void main() {
  test('old settings retain enabled alerts at 10 and 25 percent', () {
    final settings = AppSettings.fromJson({});
    expect(settings.lowBatteryAlerts.enabled, isTrue);
    expect(settings.lowBatteryAlerts.thresholds, [10, 25]);
  });

  test('new alert options survive app settings serialization and unrelated edits', () {
    final settings = AppSettings().copyWith(lowBatteryAlerts:
        const LowBatteryAlertSettings(enabled: false, thresholds: [5, 15, 30]));
    final restored = AppSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())));
    expect(restored.lowBatteryAlerts.enabled, isFalse);
    expect(restored.lowBatteryAlerts.thresholds, [5, 15, 30]);
    expect(restored.copyWith(notifyOnNewAdvert: false).lowBatteryAlerts.toJson(),
        settings.lowBatteryAlerts.toJson());
  });

  test('explicit empty selection stays empty; invalid levels are not persisted', () {
    expect(LowBatteryAlertSettings.fromJson({'thresholds': []}).thresholds, isEmpty);
    expect(LowBatteryAlertSettings.fromJson({
      'enabled': 'invalid', 'thresholds': [30, null, 10, 10, 99, '15', 0],
    }).toJson(), {'enabled': true, 'thresholds': [10, 30]});
    expect(LowBatteryAlertSettings.fromJson({'thresholds': 'invalid'}).thresholds, [10, 25]);
    expect(const LowBatteryAlertSettings().copyWith(thresholds: []).thresholds, isEmpty);
  });
}
