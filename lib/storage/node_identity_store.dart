import 'prefs_manager.dart';

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
    await PrefsManager.instance.setString(keyFor, trimmed);
  }

  String? loadName() {
    if (publicKeyHex.isEmpty) return null;
    final value = PrefsManager.instance.getString(keyFor)?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}
