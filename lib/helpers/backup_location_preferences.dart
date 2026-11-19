import 'dart:convert';

/// Optional upstream location settings, alongside coordinates and telemetry.
class BackupLocationPreferences {
  BackupLocationPreferences._(this.values);

  static const contactFlags = {
    'autoAddChat', 'autoAddRepeater', 'autoAddRoomServer',
    'autoAddSensor', 'overwriteOldest',
  };
  final Map<String, Object?> values;

  factory BackupLocationPreferences.read(
    Map<String, Object?> section, Set<String> items,
  ) {
    final result = <String, Object?>{};
    void readBool(Map<String, Object?> source, String key, Map<String, Object?> target) {
      final value = source[key];
      if (value == null) return;
      if (value is! bool) throw const FormatException('Invalid backup switch');
      target[key] = value;
    }
    if (items.contains('location')) {
      readBool(section, 'gpsEnabled', result);
      final interval = section['gpsIntervalSeconds'];
      if (interval != null) {
        if (interval is! int || interval < 0 || interval >= 86400) {
          throw const FormatException('Invalid backup GPS interval');
        }
        result['gpsIntervalSeconds'] = interval;
      }
    }
    if (items.contains('contactSettings') && section['contactSettings'] != null) {
      final raw = section['contactSettings'];
      if (raw is! Map<String, Object?>) {
        throw const FormatException('Invalid backup contact settings');
      }
      final contacts = <String, Object?>{};
      for (final key in [...contactFlags, 'evictDiscoveredContactsEnabled']) {
        readBool(raw, key, contacts);
      }
      final hops = raw['maxHops'];
      if (hops != null) {
        if (hops is! int || hops < 0 || hops > 64) {
          throw const FormatException('Invalid backup contact hop limit');
        }
        contacts['maxHops'] = hops;
      }
      if (contacts.isNotEmpty) result['contactSettings'] = Map<String, Object?>.unmodifiable(contacts);
    }
    if (items.contains('privacySettings') && section['privacySettings'] != null) {
      final raw = section['privacySettings'];
      if (raw is! Map<String, Object?>) {
        throw const FormatException('Invalid backup privacy settings');
      }
      final privacy = <String, Object?>{};
      readBool(raw, 'autoSendZeroHopAdvertOnGpsUpdate', privacy);
      if (privacy.isNotEmpty) result['privacySettings'] = Map<String, Object?>.unmodifiable(privacy);
    }
    return BackupLocationPreferences._(Map<String, Object?>.unmodifiable(result));
  }

  bool get isEmpty => values.isEmpty;
  Map<String, Object?> get contacts =>
      (values['contactSettings'] as Map<String, Object?>?) ?? const {};
  bool get hasAutoAdd => contacts.keys.any(contactFlags.contains) ||
      contacts.containsKey('maxHops');
  bool get hasGps => values.containsKey('gpsEnabled') ||
      values.containsKey('gpsIntervalSeconds');
  String get fingerprint => jsonEncode(values);
  List<String> get items => [
    if (hasGps) 'location',
    if (contacts.isNotEmpty) 'contactSettings',
    if (values.containsKey('privacySettings')) 'privacySettings',
  ];
}

typedef BackupLocationPreview = ({
  Object session,
  BackupLocationPreferences before,
  BackupLocationPreferences source,
});
