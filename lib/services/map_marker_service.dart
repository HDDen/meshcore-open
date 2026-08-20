import '../storage/prefs_manager.dart';

class MapMarkerService {
  static const String _removedKey = 'map_removed_marker_ids';

  /// Marker ids the user removed from their own map, each with the moment it
  /// was removed.
  ///
  /// The moment matters because a marker id carries no position: the same
  /// caption shared to the same place later produces the same id. A removal
  /// therefore covers markers **older than itself** — the rule a `del:`
  /// command already follows — instead of suppressing every future pin that
  /// happens to reuse the caption.
  Future<Map<String, DateTime>> loadRemovedIds() async {
    final prefs = PrefsManager.instance;
    final items = prefs.getStringList(_removedKey) ?? const [];
    final result = <String, DateTime>{};
    // Entries written before removals carried a time are bare ids. They are
    // read as removed just now, so they keep hiding what is already on the map
    // without reaching anything shared after this load.
    final legacyAt = DateTime.now();
    for (final item in items) {
      final separator = item.indexOf('|');
      final millis = separator < 0
          ? null
          : int.tryParse(item.substring(0, separator));
      if (millis == null) {
        result[item] = legacyAt;
      } else {
        result[item.substring(separator + 1)] =
            DateTime.fromMillisecondsSinceEpoch(millis);
      }
    }
    return result;
  }

  Future<void> saveRemovedIds(Map<String, DateTime> removed) async {
    final prefs = PrefsManager.instance;
    await prefs.setStringList(_removedKey, [
      for (final entry in removed.entries)
        '${entry.value.millisecondsSinceEpoch}|${entry.key}',
    ]);
  }
}
