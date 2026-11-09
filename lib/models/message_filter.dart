/// User-defined channel message rules and their persisted verdicts.
library;

enum FilterRuleField { text, sender, both }

enum FilterRuleMatch { contains, wholeWord, exact }

enum FilterReason {
  senderRule,
  textRule,
  manual,
  repeatedCharacters,
  duplicate,
  crossSenderDuplicate,
  learned,
}

FilterReason? filterReasonFromJson(Object? value) {
  if (value is! String) return null;
  for (final reason in FilterReason.values) {
    if (reason.name == value) return reason;
  }
  return null;
}

T _enumFromName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

class FilterRule {
  final String id;
  final String pattern;
  final FilterRuleField field;
  final FilterRuleMatch match;
  final bool enabled;

  const FilterRule({
    required this.id,
    required this.pattern,
    this.field = FilterRuleField.text,
    this.match = FilterRuleMatch.contains,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'pattern': pattern,
    'field': field.name,
    'match': match.name,
    'enabled': enabled,
  };

  factory FilterRule.fromJson(Map<String, dynamic> json) {
    return FilterRule(
      id: json['id'] as String? ?? '',
      pattern: json['pattern'] as String? ?? '',
      field: _enumFromName(
        FilterRuleField.values,
        json['field'],
        FilterRuleField.text,
      ),
      match: _enumFromName(
        FilterRuleMatch.values,
        json['match'],
        FilterRuleMatch.contains,
      ),
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FilterRule &&
      other.id == id &&
      other.pattern == pattern &&
      other.field == field &&
      other.match == match &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, pattern, field, match, enabled);
}

class FilterExample {
  const FilterExample({
    required this.sender,
    required this.text,
    required this.spam,
    this.sourceKey,
  });

  final String sender;
  final String text;
  final bool spam;

  /// For ordinary examples, the sender and text before normalization.
  final String? sourceKey;

  static String sourceKeyFor(String sender, String text) =>
      '${sender.length}:$sender$text';
}

class MessageFilterSettings {
  final bool enabled;
  final bool hideFiltered;
  final bool duplicates;
  final bool repeatedCharacters;
  final bool learning;
  final Set<String> excludedChannelIds;

  const MessageFilterSettings({
    this.enabled = false,
    this.hideFiltered = false,
    this.duplicates = false,
    this.repeatedCharacters = false,
    this.learning = false,
    this.excludedChannelIds = const <String>{},
  });

  MessageFilterSettings copyWith({
    bool? enabled,
    bool? hideFiltered,
    bool? duplicates,
    bool? repeatedCharacters,
    bool? learning,
    Set<String>? excludedChannelIds,
  }) => MessageFilterSettings(
    enabled: enabled ?? this.enabled,
    hideFiltered: hideFiltered ?? this.hideFiltered,
    duplicates: duplicates ?? this.duplicates,
    repeatedCharacters: repeatedCharacters ?? this.repeatedCharacters,
    learning: learning ?? this.learning,
    excludedChannelIds: excludedChannelIds ?? this.excludedChannelIds,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'displayMode': hideFiltered ? 'hide' : 'placeholder',
    'duplicates': duplicates,
    'repeatedCharacters': repeatedCharacters,
    'learning': learning,
    'excludedChannelIds': excludedChannelIds.toList()..sort(),
  };

  factory MessageFilterSettings.fromJson(Map<String, dynamic> json) {
    final excluded = json['excludedChannelIds'];
    return MessageFilterSettings(
      enabled: json['enabled'] == true,
      hideFiltered: json['displayMode'] == 'hide',
      duplicates: json['duplicates'] == true,
      repeatedCharacters: json['repeatedCharacters'] == true,
      learning: json['learning'] == true,
      excludedChannelIds: excluded is List
          ? Set<String>.unmodifiable(excluded.whereType<String>())
          : const <String>{},
    );
  }
}

/// Pending changes keyed by the concrete history storage key and message ID.
typedef ChannelRuleVerdictUpdates = Map<String, Map<String, FilterVerdict?>>;

/// The outcome of evaluating a message that should be filtered.
class FilterVerdict {
  final FilterReason reason;
  final String? detail;

  const FilterVerdict({required this.reason, this.detail});

  @override
  bool operator ==(Object other) =>
      other is FilterVerdict &&
      other.reason == reason &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(reason, detail);

  @override
  String toString() => 'FilterVerdict($reason, $detail)';
}
