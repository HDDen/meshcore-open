import 'package:flutter/foundation.dart';

import '../models/low_battery_alert_settings.dart';

/// No timers or polling: consumes only the node's existing battery readings.
class LowBatteryAlertTracker {
  final Set<int> _alerted = {};
  final Map<int, int> _streaks = {};
  List<int> _thresholds = const [];
  bool _enabled = false;
  int? _previousMillivolts;
  bool _voltageRising = false;
  final Map<int, int> _notificationTokens = {};
  int _nextNotificationToken = 0;

  Iterable<int> get alertedThresholds => _alerted;
  int? notificationToken(int threshold) => _notificationTokens[threshold];

  bool allowsNotification(int threshold) => _enabled && !_voltageRising &&
      _thresholds.contains(threshold) && _alerted.contains(threshold);

  /// Returns levels whose native notifications must be cancelled. Settings
  /// changes never count a previously received reading as a new confirmation.
  List<int> configure(
    LowBatteryAlertSettings options, {
    required bool notificationsEnabled,
  }) {
    final enabled = notificationsEnabled && options.enabled;
    final thresholds = LowBatteryAlertSettings.normalizeThresholds(options.thresholds);
    if (_enabled == enabled && listEquals(_thresholds, thresholds)) {
      return const [];
    }
    _enabled = enabled;
    _thresholds = thresholds;
    _streaks.clear();
    final cancelled = _alerted
        .where((value) => !enabled || !thresholds.contains(value)).toList();
    _alerted.removeAll(cancelled);
    for (final threshold in cancelled) {
      _notificationTokens.remove(threshold);
    }
    return cancelled;
  }

  void breakConfirmation() => _streaks.clear();

  void reset() {
    _alerted.clear();
    _notificationTokens.clear();
    _streaks.clear();
    _previousMillivolts = null;
    _voltageRising = false;
  }

  ({int? threshold, List<int> rearmed}) observe({
    required int millivolts,
    required int percent,
  }) {
    final previous = _previousMillivolts;
    _previousMillivolts = millivolts;
    if (previous != null && millivolts != previous) {
      _voltageRising = millivolts > previous;
    }
    // The protocol exposes voltage, not charger state. After a rise, equal
    // readings remain suppressed until an actual decline is observed.
    final rearmed = <int>[];
    final crossed = <int>[];
    for (final threshold in _thresholds) {
      if (percent > threshold + 5 && _alerted.remove(threshold)) {
        _notificationTokens.remove(threshold);
        rearmed.add(threshold);
      }
      if (!_enabled || _voltageRising || percent > threshold ||
          _alerted.contains(threshold)) {
        _streaks.remove(threshold);
        continue;
      }
      final streak = (_streaks[threshold] ?? 0) + 1;
      _streaks[threshold] = streak;
      if (streak >= 2) crossed.add(threshold);
    }
    _alerted.addAll(crossed);
    for (final threshold in crossed) {
      _streaks.remove(threshold);
      _notificationTokens[threshold] = ++_nextNotificationToken;
    }
    // A sudden fall can cross several configured levels. Show only the
    // lowest one, retaining the other confirmations to avoid duplicate alerts.
    return (
      threshold: crossed.isEmpty ? null : crossed.first,
      rearmed: rearmed,
    );
  }
}
