import 'dart:convert';

import '../models/message_filter.dart';
import 'message_history_storage.dart';
import 'prefs_manager.dart';

/// Filter preferences and the shared SQL corpus in the current data folder.
class MessageFilterStore {
  static const settingsKey = 'message_filter_settings';
  static const rulesKey = 'message_filter_rules';

  Object? _read(String key) {
    final raw = PrefsManager.instance.get(key);
    if (raw is! String || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  MessageFilterSettings loadSettings() {
    final raw = _read(settingsKey);
    return raw is Map<String, dynamic>
        ? MessageFilterSettings.fromJson(raw)
        : const MessageFilterSettings();
  }

  List<FilterRule> loadRules() {
    final raw = _read(rulesKey);
    if (raw is! List) return const [];
    final rules = <FilterRule>[];
    for (final entry in raw.whereType<Map<String, dynamic>>()) {
      if (entry['id'] is! String ||
          entry['pattern'] is! String ||
          (entry['enabled'] != null && entry['enabled'] is! bool)) {
        continue;
      }
      final rule = FilterRule.fromJson(entry);
      if (rule.id.isNotEmpty && rule.pattern.trim().isNotEmpty) rules.add(rule);
    }
    return rules;
  }

  Future<void> saveSettings(MessageFilterSettings settings) =>
      _write(settingsKey, settings.toJson());

  Future<void> saveRules(List<FilterRule> rules) =>
      _write(rulesKey, [for (final rule in rules) rule.toJson()]);

  Future<({int spam, int notSpam})> loadTrainingLabelCounts() =>
      MessageHistoryStorage.instance.filterTrainingLabelCounts();

  Future<List<FilterExample>> loadTrainingExamples() =>
      MessageHistoryStorage.instance.readFilterTrainingExamples();

  Future<void> saveTrainingExamples(
    Iterable<FilterExample> examples, {
    required bool manual,
  }) => MessageHistoryStorage.instance.writeFilterTrainingExamples(
    examples,
    manual: manual,
  );

  Future<void> clearTrainingExamples() =>
      MessageHistoryStorage.instance.clearFilterTrainingExamples();

  Future<void> _write(String key, Object value) async {
    if (!await PrefsManager.instance.setString(key, jsonEncode(value))) {
      throw StateError('Could not save $key');
    }
  }
}
