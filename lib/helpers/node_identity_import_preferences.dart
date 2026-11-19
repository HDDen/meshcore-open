import '../storage/prefs_manager.dart';

abstract final class NodeIdentityImportPreferences {
  static Future<void> clearBlockedNodes() async {
    final prefs = PrefsManager.instance;
    // The full public-key suffix excludes similarly named global settings.
    final pattern = RegExp(r'^node_identity_import_prompt_[0-9a-fA-F]{64}$');
    final keys = prefs.getKeys().where(pattern.hasMatch).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
