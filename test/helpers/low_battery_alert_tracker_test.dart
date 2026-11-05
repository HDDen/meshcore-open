import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/low_battery_alert_tracker.dart';
import 'package:meshcore_open/models/low_battery_alert_settings.dart';

void main() {
  LowBatteryAlertTracker tracker(List<int> levels) => LowBatteryAlertTracker()
    ..configure(LowBatteryAlertSettings(thresholds: levels), notificationsEnabled: true);

  for (final level in LowBatteryAlertSettings.supportedThresholds) {
    test('selected $level percent needs two valid readings and alerts once', () {
      final state = tracker([level]);
      final voltage = 3000 + level * 10;
      expect(state.observe(millivolts: voltage, percent: level).threshold, isNull);
      expect(state.observe(millivolts: voltage, percent: level).threshold, level);
      expect(state.observe(millivolts: voltage - 10, percent: level - 1).threshold, isNull);
    });
  }

  test('rising voltage and its plateau cannot confirm even a selected level', () {
    final state = tracker([5, 10, 15, 20, 25, 30]);
    state.observe(millivolts: 3040, percent: 4);
    for (final percent in [5, 10, 15, 20, 25, 30]) {
      for (var i = 0; i < 3; i++) {
        expect(state.observe(millivolts: 3000 + percent * 10, percent: percent).threshold, isNull);
      }
    }
    expect(state.alertedThresholds, isEmpty);
    expect(state.observe(millivolts: 3290, percent: 29).threshold, isNull);
    expect(state.observe(millivolts: 3290, percent: 29).threshold, 30);
  });

  test('lowest confirmed level wins; rearm remains strictly above level + 5', () {
    final state = tracker([25, 10]);
    state.observe(millivolts: 3100, percent: 10);
    expect(state.observe(millivolts: 3100, percent: 10).threshold, 10);
    expect(state.alertedThresholds, unorderedEquals([10, 25]));
    expect(state.observe(millivolts: 3300, percent: 30).rearmed, [10]);
    expect(state.observe(millivolts: 3310, percent: 31).rearmed, [25]);
    expect(state.observe(millivolts: 3250, percent: 25).threshold, isNull);
    expect(state.observe(millivolts: 3250, percent: 25).threshold, 25);
  });

  test('settings edits break confirmation, cancel disabled levels and invalidate queued shows', () {
    final state = tracker([10, 25]);
    state.observe(millivolts: 3250, percent: 25);
    state.breakConfirmation();
    expect(state.observe(millivolts: 3250, percent: 25).threshold, isNull);
    expect(state.observe(millivolts: 3250, percent: 25).threshold, 25);
    expect(state.notificationToken(25), isNotNull);
    final stillSelectedToken = state.notificationToken(25);
    state.configure(const LowBatteryAlertSettings(thresholds: [5, 10, 25]),
        notificationsEnabled: true);
    expect(state.notificationToken(25), stillSelectedToken);
    expect(state.allowsNotification(25), isTrue);
    expect(state.configure(const LowBatteryAlertSettings(thresholds: [10]),
        notificationsEnabled: true), [25]);
    expect(state.notificationToken(25), isNull);
    expect(state.allowsNotification(25), isFalse);
    state.observe(millivolts: 3100, percent: 10);
    state.configure(const LowBatteryAlertSettings(thresholds: [10]), notificationsEnabled: false);
    expect(state.observe(millivolts: 3100, percent: 10).threshold, isNull);
    state.configure(const LowBatteryAlertSettings(thresholds: [10]), notificationsEnabled: true);
    expect(state.observe(millivolts: 3100, percent: 10).threshold, isNull);
    expect(state.observe(millivolts: 3100, percent: 10).threshold, 10);
  });

  test('empty selection disables alerts; resetting identity drops old trend and confirmations', () {
    final state = tracker([]);
    state.observe(millivolts: 3050, percent: 5);
    expect(state.observe(millivolts: 3050, percent: 5).threshold, isNull);
    state.configure(const LowBatteryAlertSettings(thresholds: [10]), notificationsEnabled: true);
    state.observe(millivolts: 3100, percent: 10); // Rising: suppressed.
    state.reset();
    expect(state.observe(millivolts: 3100, percent: 10).threshold, isNull);
    expect(state.observe(millivolts: 3100, percent: 10).threshold, 10);
  });
}
