import 'package:flutter/foundation.dart';

import '../helpers/cli_history_writes.dart';
import '../models/repeater_cli_entry.dart';
import 'message_history_storage.dart';

class RepeaterCliStore {
  static final _browserEntries = <String, RepeaterCliEntry>{};
  String _scope(String nodeKey, String repeaterKey) => 'repeater:$nodeKey:$repeaterKey';
  int revision(String nodeKey, String repeaterKey) => CliHistoryWrites.revision(_scope(nodeKey, repeaterKey));

  Future<List<RepeaterCliEntry>> load(String nodeKey, String repeaterKey) =>
      CliHistoryWrites.ordered(() async {
        if (!kIsWeb) {
          return MessageHistoryStorage.instance.readRepeaterCliHistory(nodeKey, repeaterKey);
        }
        return _browserEntries.values.where((entry) =>
          entry.nodeKey == nodeKey && entry.repeaterKey == repeaterKey).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      });

  Future<bool> save(RepeaterCliEntry entry, {int? revision}) => CliHistoryWrites.save(
    _scope(entry.nodeKey, entry.repeaterKey), revision ?? this.revision(entry.nodeKey, entry.repeaterKey), () async {
      if (kIsWeb) {
        _browserEntries['${entry.nodeKey}:${entry.repeaterKey}:${entry.id}'] = entry;
      } else {
        await MessageHistoryStorage.instance.writeRepeaterCliEntry(entry);
      }
    });

  Future<void> clear(String nodeKey, String repeaterKey) =>
      CliHistoryWrites.clear(_scope(nodeKey, repeaterKey), () async {
        if (kIsWeb) {
          _browserEntries.removeWhere((_, entry) => entry.nodeKey == nodeKey && entry.repeaterKey == repeaterKey);
        } else {
          await MessageHistoryStorage.instance.clearRepeaterCliHistory(nodeKey, repeaterKey);
        }
      });
}
