import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';
import 'message_history_storage.dart';
import 'prefs_manager.dart';

/// The region a contact's flood sends are scoped with, per node. A row of
/// the `contact_settings` table of the message-history database, under
/// [settingName]; no row means the node's own default scope. The web build
/// has no database and keeps the same values in preferences.
class ContactRegionStore {
  static const String settingName = 'flood_region';
  static const String _webKeyPrefix = 'contact_flood_region_';

  /// The stored value that asks for no scope at all: the packet leaves as a
  /// plain flood, the node's default scope set aside.
  static const String unscoped = '*';

  static bool isUnscoped(String region) => region.trim() == unscoped;

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length >= 10 ? value.substring(0, 10) : '';

  /// Every contact's region under this node, keyed by contact key.
  Future<Map<String, String>> loadRegions() async {
    if (publicKeyHex.isEmpty) return const {};
    if (kIsWeb) {
      final prefs = PrefsManager.instance;
      final prefix = '$_webKeyPrefix$publicKeyHex';
      return {
        for (final key in prefs.getKeys())
          if (key.startsWith(prefix))
            key.substring(prefix.length): prefs.getString(key)?.trim() ?? '',
      }..removeWhere((_, region) => region.isEmpty);
    }
    try {
      return await MessageHistoryStorage.instance.loadContactSettings(
        publicKeyHex,
        settingName,
      );
    } on StateError {
      return const {};
    }
  }

  /// Stores [region] for [contactKeyHex], or removes it when empty. Returns
  /// what was stored.
  Future<String> saveRegion(String contactKeyHex, String region) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot save contact region.');
      return '';
    }
    final normalized = region.trim();
    if (normalized.isEmpty) {
      await clearRegion(contactKeyHex);
      return '';
    }
    if (kIsWeb) {
      await PrefsManager.instance.setString(
        '$_webKeyPrefix$publicKeyHex$contactKeyHex',
        normalized,
      );
      return normalized;
    }
    try {
      await MessageHistoryStorage.instance.saveContactSetting(
        nodeKey: publicKeyHex,
        contactKey: contactKeyHex,
        name: settingName,
        value: normalized,
      );
    } on StateError {
      return '';
    }
    return normalized;
  }

  Future<void> clearRegion(String contactKeyHex) async {
    if (publicKeyHex.isEmpty) return;
    if (kIsWeb) {
      await PrefsManager.instance.remove(
        '$_webKeyPrefix$publicKeyHex$contactKeyHex',
      );
      return;
    }
    try {
      await MessageHistoryStorage.instance.deleteContactSetting(
        nodeKey: publicKeyHex,
        contactKey: contactKeyHex,
        name: settingName,
      );
    } on StateError {
      return;
    }
  }
}
