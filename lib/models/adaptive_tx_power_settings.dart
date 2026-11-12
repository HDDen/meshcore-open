class AdaptiveTxPowerSettings {
  const AdaptiveTxPowerSettings({
    this.enabled = false,
    this.targetDbm,
    this.channelRetries = 0,
    this.directEnabled = false,
    this.forcedFloodRetries = 0,
  });

  final bool enabled;
  final int? targetDbm;
  final int channelRetries;
  final bool directEnabled;
  final int forcedFloodRetries;

  static const minTargetDbm = 2;
  static const maxTargetDbm = 22;

  static int normalizeTarget(int value) =>
      value.clamp(minTargetDbm, maxTargetDbm).toInt();

  factory AdaptiveTxPowerSettings.fromJson(Object? json) {
    if (json is! Map) return const AdaptiveTxPowerSettings();
    final target = json['target_dbm'];
    return AdaptiveTxPowerSettings(
      enabled: json['enabled'] == true,
      targetDbm: target is int ? normalizeTarget(target) : null,
      channelRetries: _retryCount(json['channel_retries']),
      directEnabled: json['direct_enabled'] == true,
      forcedFloodRetries: _retryCount(json['forced_flood_retries']),
    );
  }

  static int _retryCount(Object? value) => value is int && value > 0 ? value : 0;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'target_dbm': targetDbm,
    'channel_retries': channelRetries,
    'direct_enabled': directEnabled,
    'forced_flood_retries': forcedFloodRetries,
  };

  AdaptiveTxPowerSettings copyWith({
    bool? enabled,
    int? targetDbm,
    int? channelRetries,
    bool? directEnabled,
    int? forcedFloodRetries,
  }) => AdaptiveTxPowerSettings(
    enabled: enabled ?? this.enabled,
    targetDbm: targetDbm ?? this.targetDbm,
    channelRetries: channelRetries ?? this.channelRetries,
    directEnabled: directEnabled ?? this.directEnabled,
    forcedFloodRetries: forcedFloodRetries ?? this.forcedFloodRetries,
  );
}
