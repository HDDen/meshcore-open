/// App-wide low-battery notifications. Independent of power-saving profiles.
class LowBatteryAlertSettings {
  static const supportedThresholds = [5, 10, 15, 20, 25, 30];
  static const defaultThresholds = [10, 25];

  final bool enabled;
  final List<int> thresholds;

  const LowBatteryAlertSettings({
    this.enabled = true,
    this.thresholds = defaultThresholds,
  });

  static List<int> normalizeThresholds(Iterable<Object?> values) {
    final selected = values.whereType<int>().toSet();
    return List<int>.unmodifiable(supportedThresholds.where(selected.contains));
  }

  factory LowBatteryAlertSettings.fromJson(Object? value) {
    if (value is! Map) return const LowBatteryAlertSettings();
    final raw = value['thresholds'];
    return LowBatteryAlertSettings(
      enabled: value['enabled'] is bool ? value['enabled'] as bool : true,
      // An explicit empty list disables every level; only absent/invalid
      // containers fall back to the pre-existing 10/25 percent behavior.
      thresholds: raw is List ? normalizeThresholds(raw) : defaultThresholds,
    );
  }

  LowBatteryAlertSettings copyWith({bool? enabled, List<int>? thresholds}) =>
      LowBatteryAlertSettings(
        enabled: enabled ?? this.enabled,
        thresholds: normalizeThresholds(thresholds ?? this.thresholds),
      );

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'thresholds': normalizeThresholds(thresholds),
  };
}
