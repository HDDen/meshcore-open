import 'dart:convert';

import '../models/message_filter.dart';
import '../services/message_filter/message_filter_text.dart';
import '../storage/message_filter_store.dart';

class BackupMessageFilter {
  static const section = 'mcoaMessageFilter';

  BackupMessageFilter.fromPreferences(Map<String, Object?> preferences)
    : _settings = _readSettings(preferences[settingsKey]),
      rules = _readRules(preferences[rulesKey]);

  factory BackupMessageFilter.capture(
    MessageFilterSettings settings,
    List<FilterRule> rules,
  ) => BackupMessageFilter.fromPreferences({
    settingsKey: settings.toJson(),
    rulesKey: [for (final rule in rules) rule.toJson()],
  });

  static const settingsKey = MessageFilterStore.settingsKey;
  static const rulesKey = MessageFilterStore.rulesKey;
  static final _channelId = RegExp(r'^[0-9a-f]{16}$');
  static const _booleanKeys = ['duplicates', 'repeatedCharacters'];
  final Map<String, Object> _settings;
  final List<FilterRule> rules;

  bool get isEmpty => _settings.isEmpty && rules.isEmpty;

  Map<String, Object> toPreferences() => {
    if (_settings.isNotEmpty) settingsKey: _settings,
    if (rules.isNotEmpty) rulesKey: [for (final rule in rules) rule.toJson()],
  };

  static Object? _decode(Object? value) {
    if (value is! String) return value;
    try {
      return jsonDecode(value);
    } on FormatException {
      throw const FormatException('Invalid message filter backup');
    }
  }

  static Map<String, Object> _readSettings(Object? value) {
    final settings = _decode(value);
    if (settings == null) return const {};
    if (settings is! Map<String, Object?>) {
      throw const FormatException('Invalid message filter settings');
    }
    final mode = settings['displayMode'];
    return Map.unmodifiable({
      for (final key in _booleanKeys)
        if (settings[key] case final bool flag) key: flag,
      if (mode == 'hide' || mode == 'placeholder') 'displayMode': mode as String,
      if (settings['repeatSends'] case final int count)
        'repeatSends': count.clamp(
          MessageFilterSettings.minRepeatSends, MessageFilterSettings.maxRepeatSends,
        ),
      if (settings['excludedChannelIds'] case final List<Object?> ids)
        'excludedChannelIds': List<String>.unmodifiable({
          for (final id in ids.whereType<String>())
            if (_channelId.hasMatch(id.toLowerCase())) id.toLowerCase(),
        }),
    });
  }

  static List<FilterRule> _readRules(Object? value) {
    final rules = _decode(value);
    if (rules == null) return const [];
    if (rules is! List<Object?>) {
      throw const FormatException('Invalid message filter rules');
    }
    final parsed = <FilterRule>[];
    for (final rule in rules.whereType<Map<String, Object?>>()) {
      final id = rule['id'];
      final pattern = rule['pattern'];
      final enabled = rule['enabled'];
      if (id is! String || id.isEmpty || pattern is! String ||
          MessageFilterText.normalize(pattern).isEmpty ||
          (enabled != null && enabled is! bool) ||
          !_knownEnum(rule['field'], FilterRuleField.values) ||
          !_knownEnum(rule['match'], FilterRuleMatch.values)) {
        continue;
      }
      parsed.add(FilterRule.fromJson(rule));
    }
    return List.unmodifiable(parsed);
  }

  static bool _knownEnum(Object? value, List<Enum> variants) =>
      value == null || variants.any((variant) => variant.name == value);

  BackupMessageFilterPreview preview(
    MessageFilterSettings current,
    List<FilterRule> currentRules,
  ) {
    final mode = _settings['displayMode'];
    final exclusions = _settings['excludedChannelIds'] as List<String>?;
    final next = current.copyWith(
      hideFiltered: mode == null ? null : mode == 'hide',
      duplicates: _settings['duplicates'] as bool?,
      repeatSends: _settings['repeatSends'] as int?,
      repeatedCharacters: _settings['repeatedCharacters'] as bool?,
      excludedChannelIds: Set.unmodifiable({
        ...current.excludedChannelIds,
        ...?exclusions,
      }),
    );
    final changedSettings = [
      current.hideFiltered != next.hideFiltered,
      current.duplicates != next.duplicates,
      current.repeatSends != next.repeatSends,
      current.repeatedCharacters != next.repeatedCharacters,
      current.excludedChannelIds.length != next.excludedChannelIds.length,
    ].where((changed) => changed).length;
    (String, FilterRuleField, FilterRuleMatch) matchKey(FilterRule rule) =>
        (MessageFilterText.normalize(rule.pattern), rule.field, rule.match);
    final ids = {for (final rule in currentRules) rule.id};
    final matches = {for (final rule in currentRules) matchKey(rule)};
    final added = <FilterRule>[];
    for (final rule in rules) {
      final key = matchKey(rule);
      if (ids.contains(rule.id) || !matches.add(key)) continue;
      ids.add(rule.id);
      added.add(rule);
    }
    return BackupMessageFilterPreview._(
      baselineSettings: current,
      baselineRules: currentRules,
      settings: next,
      changedSettings: changedSettings,
      addedRules: List.unmodifiable(added),
    );
  }
}

class BackupMessageFilterPreview {
  const BackupMessageFilterPreview._({
    required this.baselineSettings,
    required this.baselineRules,
    required this.settings,
    required this.changedSettings,
    required this.addedRules,
  });

  final MessageFilterSettings baselineSettings;
  final List<FilterRule> baselineRules;
  final MessageFilterSettings settings;
  final int changedSettings;
  final List<FilterRule> addedRules;
  bool get isEmpty => changedSettings == 0 && addedRules.isEmpty;
}
