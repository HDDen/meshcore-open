import 'message_history_storage.dart';
import 'prefs_manager.dart';

/// One JSON value per node and name: a row of the `node_state` table of the
/// database, or, where there is no database (the web build, a process that
/// never opened it such as a unit test), the preference key the value always
/// had. App-wide values use the empty node key. The small per-node
/// collections (channel order and groups, contact groups, communities) and
/// the app-wide maps of `StorageService` go through here, so each store
/// keeps its JSON and its preference key and gains the database for free.
class NodeState {
  NodeState._();

  static bool get usesDatabase => MessageHistoryStorage.instance.hasDatabase;

  static Future<String?> read({
    required String nodeKey,
    required String name,
    required String preferenceKey,
  }) async {
    if (!usesDatabase) return PrefsManager.instance.getString(preferenceKey);
    return MessageHistoryStorage.instance.readNodeState(nodeKey, name);
  }

  static Future<void> write({
    required String nodeKey,
    required String name,
    required String preferenceKey,
    required String value,
  }) async {
    if (!usesDatabase) {
      await PrefsManager.instance.setString(preferenceKey, value);
      return;
    }
    await MessageHistoryStorage.instance.writeNodeState(
      nodeKey: nodeKey,
      name: name,
      value: value,
    );
  }

  static Future<void> remove({
    required String nodeKey,
    required String name,
    required String preferenceKey,
  }) async {
    if (!usesDatabase) {
      final prefs = PrefsManager.instance;
      // Removing a key that is not there still rewrites the whole file on
      // Windows and Linux.
      if (prefs.containsKey(preferenceKey)) await prefs.remove(preferenceKey);
      return;
    }
    await MessageHistoryStorage.instance.deleteNodeState(nodeKey, name);
  }

  /// The preference form only: a value stored under the key of the time
  /// before the keys carried a node is moved under [preferenceKey] and
  /// returned; with none there, nothing is written and null comes back. The
  /// database never sees those keys: the move at startup leaves them alone.
  static Future<String?> takeOverLegacyPreference({
    required String legacyKey,
    required String preferenceKey,
  }) async {
    if (usesDatabase) return null;
    final prefs = PrefsManager.instance;
    final value = prefs.getString(legacyKey);
    if (value == null || value.isEmpty) return null;
    await prefs.setString(preferenceKey, value);
    await prefs.remove(legacyKey);
    return value;
  }
}
