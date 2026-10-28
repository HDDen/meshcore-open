import 'package:flutter/foundation.dart';

import '../helpers/cli_history_writes.dart';
import '../models/companion_cli_entry.dart';
import 'message_history_storage.dart';

abstract class CompanionCliHistory {
  Future<List<CompanionCliEntry>> load();
  int revision(String nodeKey);
  Future<bool> save(CompanionCliEntry entry, {int? revision});
  Future<void> clear(String nodeKey);
}

/// Native — только SQL. Web пока не открывает SQLite: отдельная временная
/// память процесса, явно обозначенная в UI, без SharedPreferences/localStorage.
class CompanionCliStore implements CompanionCliHistory {
  static final _browserEntries = <String, CompanionCliEntry>{};
  String _scope(String nodeKey) => 'companion:$nodeKey';
  @override
  int revision(String nodeKey) => CliHistoryWrites.revision(_scope(nodeKey));

  @override
  Future<List<CompanionCliEntry>> load() => CliHistoryWrites.ordered(() async {
    if (!kIsWeb) {
      return MessageHistoryStorage.instance.readCompanionCliHistory();
    }
    return _browserEntries.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  });

  @override
  Future<bool> save(CompanionCliEntry entry, {int? revision}) => CliHistoryWrites.save(
    _scope(entry.nodeKey), revision ?? this.revision(entry.nodeKey), () async {
      if (kIsWeb) {
        _browserEntries['${entry.nodeKey}:${entry.id}'] = entry;
      } else {
        await MessageHistoryStorage.instance.writeCompanionCliEntry(entry);
      }
    });

  @override
  Future<void> clear(String nodeKey) => CliHistoryWrites.clear(_scope(nodeKey), () async {
    if (kIsWeb) {
      _browserEntries.removeWhere((_, entry) => entry.nodeKey == nodeKey);
    } else {
      await MessageHistoryStorage.instance.clearCompanionCliHistory(nodeKey);
    }
  });
}
