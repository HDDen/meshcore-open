import 'message_history_storage.dart';
import 'prefs_manager.dart';

/// The node's own name as last reported, per node: a `node_state` row named
/// `node_identity`, read through the cache `MessageHistoryStorage` fills at
/// startup, since the connector reads the name synchronously while naming
/// offline scopes; the preference key `node_identity_<node>` where there is
/// no database. Saved only when the name changed: the connector saves it at
/// every handshake.
class NodeIdentityStore {
  static const String _keyPrefix = 'node_identity_';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length >= 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';

  Future<void> saveName(String? name) async {
    if (publicKeyHex.isEmpty) return;
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    if (loadName() == trimmed) return;
    final storage = MessageHistoryStorage.instance;
    if (storage.hasDatabase) {
      await storage.saveNodeName(publicKeyHex, trimmed);
      return;
    }
    await PrefsManager.instance.setString(keyFor, trimmed);
  }

  String? loadName() {
    if (publicKeyHex.isEmpty) return null;
    final storage = MessageHistoryStorage.instance;
    final value = (storage.hasDatabase
            ? storage.nodeName(publicKeyHex)
            : PrefsManager.instance.getString(keyFor))
        ?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}
