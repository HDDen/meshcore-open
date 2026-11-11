import 'dart:convert';

import '../models/message_filter.dart';
import '../services/message_filter/message_filter_text.dart';

class BackupFilterTraining {
  static const section = 'mcoaFilterTraining';

  BackupFilterTraining(Iterable<FilterTrainingRow> rows)
    : rows = List.unmodifiable(rows);

  factory BackupFilterTraining.fromPreferences(
    Map<String, Object?> preferences, {
    required bool upstream,
  }) {
    final entries = <({FilterTrainingRow row, int time, int position})>[];
    final newestLabels = <String, (int, FilterTrainingKind?)>{};
    for (final kind in FilterTrainingKind.values) {
      String? previousKey;
      for (final entry in _readExamples(preferences[_key(kind)])) {
        final rawText = entry['text'];
        final sender = entry['sender'];
        if (rawText is! String || sender is! String) continue;
        final text = rawText.trim();
        if (text.isEmpty || MessageFilterText.isStructuredPayload(text)) continue;
        final sample = text.length > MessageFilterText.trainingTextLimit
            ? text.substring(0, MessageFilterText.trainingTextLimit)
            : text;
        final ordinary = kind == FilterTrainingKind.ordinary;
        final storedKey = entry['sourceKey'];
        final sourceKey = !ordinary ? null :
            !upstream && storedKey is String && storedKey.length <= 4096
            ? storedKey
            : FilterExample.sourceKeyFor(sender, sample);
        final example = MessageFilterText.trainingExample(
          sender, sample, spam: kind == FilterTrainingKind.spam,
        );
        if (example.text.isEmpty || (ordinary && upstream && sourceKey == previousKey)) {
          continue;
        }
        previousKey = sourceKey;
        final rank = entry[upstream ? 'addedAtMs' : 'position'];
        final time = rank is int ? rank : 0;
        if (!ordinary) {
          final previous = newestLabels[example.text];
          if (previous == null || previous.$1 < time) {
            newestLabels[example.text] = (time, kind);
          } else if (previous.$1 == time && previous.$2 != kind) {
            newestLabels[example.text] = (time, null);
          }
        }
        entries.add((
          row: (sender: example.sender, text: example.text, kind: kind, sourceKey: sourceKey),
          time: time,
          position: entries.length,
        ));
      }
    }
    entries.sort((a, b) {
      final time = a.time.compareTo(b.time);
      return time == 0 ? a.position.compareTo(b.position) : time;
    });
    final counts = <FilterTrainingKind, int>{};
    final seenManual = <(String, String)>{};
    final rows = <FilterTrainingRow>[];
    for (final entry in entries.reversed) {
      final row = entry.row;
      final count = counts[row.kind] ?? 0;
      if (count == row.kind.capacity) continue;
      if (row.kind != FilterTrainingKind.ordinary &&
          (newestLabels[row.text]?.$2 != row.kind ||
              !seenManual.add((row.text, row.sender)))) continue;
      rows.add(row);
      counts[row.kind] = count + 1;
    }
    return BackupFilterTraining(rows.reversed);
  }

  final List<FilterTrainingRow> rows;
  bool get isEmpty => rows.isEmpty;
  int count(FilterTrainingKind kind) => rows.where((row) => row.kind == kind).length;

  static String _key(FilterTrainingKind kind) => switch (kind) {
    FilterTrainingKind.ordinary => 'message_filter_recent_clean',
    FilterTrainingKind.notSpam => 'message_filter_ham_examples',
    FilterTrainingKind.spam => 'message_filter_spam_examples',
  };

  static Iterable<Map<String, Object?>> _readExamples(Object? raw) {
    if (raw == null) return const [];
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is List<Object?>) return decoded.whereType<Map<String, Object?>>();
    } on FormatException {
      throw const FormatException('Invalid backup training examples');
    }
    throw const FormatException('Invalid backup training examples');
  }

  Map<String, Object> toPreferences() => {
    for (final kind in FilterTrainingKind.values)
      _key(kind): [
        for (final (position, row) in rows.indexed)
          if (row.kind == kind) {
            'sender': row.sender,
            'text': row.text,
            'position': position,
            'sourceKey': ?row.sourceKey,
          },
      ],
  };
}
