import 'contact_option_storage.dart';

typedef BackupContactOptionKey = (String contact, String name);

const backupContactOptionNames = {
  'smaz_enabled',
  'mcmp_enabled',
  'mcmp_version',
  'mcmp_use_sign',
  'mcotxt_enabled',
  'mcotxt_plain_when_smaller',
  'cyr2lat_enabled',
  'cyr2lat_profile',
  'sending_delay_enabled',
  'url_images_enabled',
};

const _codecFlags = {
  'smaz_enabled', 'mcmp_enabled', 'mcotxt_enabled', 'cyr2lat_enabled',
};
const _codecOptions = {
  ..._codecFlags,
  'mcmp_version',
  'mcmp_use_sign',
  'mcotxt_plain_when_smaller',
  'cyr2lat_profile',
};

class BackupContactSettings {
  BackupContactSettings(Map<BackupContactOptionKey, String> values)
    : values = Map.unmodifiable(values);

  factory BackupContactSettings.fromPreferences(
    Map<String, Object?> preferences,
    String sourceScope,
  ) {
    final values = <BackupContactOptionKey, String>{};
    for (final row in contactOptionsFromPreferences(preferences).values) {
      if (row.nodeKey != sourceScope || !backupContactOptionNames.contains(row.name)) {
        continue;
      }
      final key = (row.contactKey, row.name);
      if (values.containsKey(key) && values[key] != row.value) {
        throw const FormatException('Ambiguous backup contact setting');
      }
      if (row.name == 'mcmp_version' && row.value != '2' && row.value != '3') {
        throw const FormatException('Invalid backup contact codec version');
      }
      values[key] = row.value;
    }
    return BackupContactSettings(values);
  }

  final Map<BackupContactOptionKey, String> values;
  bool get isEmpty => values.isEmpty;
  Set<String> get contacts => {for (final (contact, _) in values.keys) contact};

  Map<String, Object?> toPreferences(String scope) => {
    for (final MapEntry(key: (contact, name), :value) in values.entries)
      contactOptionDefinitions[name]!.legacyKey(scope, contact):
          contactOptionDefinitions[name]!.decode(value),
  };

  BackupContactSettingsPreview preview({
    required Object session,
    required Set<String> destinationKeys,
    required BackupContactSettings current,
    required bool Function(String) hasCyr2LatProfile,
  }) {
    final configuredCodecs = {
      for (final (contact, name) in current.values.keys)
        if (_codecOptions.contains(name)) contact,
    };
    final enabledCodecCounts = <String, int>{};
    for (final MapEntry(key: (contact, name), :value) in values.entries) {
      if (_codecFlags.contains(name) && value == '1') {
        enabledCodecCounts.update(contact, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final additions = <BackupContactOptionKey, String>{};
    for (final MapEntry(key: (contact, name), :value) in values.entries) {
      if (!destinationKeys.contains(contact) || current.values.containsKey((contact, name))) {
        continue;
      }
      if (_codecOptions.contains(name) &&
          (configuredCodecs.contains(contact) || (enabledCodecCounts[contact] ?? 0) > 1)) {
        continue;
      }
      if (name == 'cyr2lat_profile' && !hasCyr2LatProfile(value)) continue;
      additions[(contact, name)] = value;
    }
    return BackupContactSettingsPreview(
      session: session,
      source: this,
      additions: BackupContactSettings(additions),
      skipped: values.length - additions.length,
    );
  }
}

class BackupContactSettingsPreview {
  const BackupContactSettingsPreview({
    required this.session,
    required this.source,
    required this.additions,
    required this.skipped,
  });

  final Object session;
  final BackupContactSettings source;
  final BackupContactSettings additions;
  final int skipped;
}
