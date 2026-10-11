import '../utils/app_logger.dart';
import 'prefs_manager.dart';

class ChannelRegionStore {
  static const String _keyPrefix = 'channel_region_';
  static const String _defaultKeyPrefix = 'default_region_';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length >= 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';

  String get _defaultKey => '$_defaultKeyPrefix$publicKeyHex';

  /// Clears every channel and default region assignment equal to [region],
  /// across all radios. The region list is app-wide, so a deleted region must
  /// not stay assigned on radios other than the connected one.
  static Future<void> clearRegionEverywhere(String region) async {
    final prefs = PrefsManager.instance;
    final keys = prefs
        .getKeys()
        .where(
          (key) =>
              key.startsWith(_keyPrefix) || key.startsWith(_defaultKeyPrefix),
        )
        .toList();
    for (final key in keys) {
      final value = prefs.get(key);
      if (value is String && value == region) {
        await prefs.setString(key, '');
      }
    }
  }

  String loadDefaultRegion() {
    if (publicKeyHex.isEmpty) return '';
    return PrefsManager.instance.getString(_defaultKey) ?? '';
  }

  Future<void> saveDefaultRegion(String region) async {
    if (publicKeyHex.isEmpty) return;
    await PrefsManager.instance.setString(_defaultKey, region);
  }

  Future<String> loadRegion(int channelIndex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load channel settings.',
      );
      return '';
    }
    final prefs = PrefsManager.instance;
    final key = '$keyFor$channelIndex';
    String? region = prefs.getString(key);
    return region ?? '';
  }

  Future<String> saveRegion(int channelIndex, String region) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save channel settings.',
      );
      return '';
    }

    final prefs = PrefsManager.instance;
    final key = '$keyFor$channelIndex';
    await prefs.setString(key, region);
    return region;
  }
}
