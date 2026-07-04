import '../utils/app_logger.dart';
import 'channel_name_keyed_store.dart';
import 'prefs_manager.dart';

class ChannelRegionStore with ChannelNameKeyedStore {
  static const String _keyPrefix = 'channel_region_';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length >= 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';

  Future<String> loadRegion(int channelIndex) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot load channel settings.',
      );
      return '';
    }
    final prefs = PrefsManager.instance;
    final key = channelStorageKey(keyFor, channelIndex);
    if (key == null) return '';
    String? region = prefs.getString(key);
    if (region == null && allowsLegacyIndexMigration) {
      final legacyKey = '$keyFor$channelIndex';
      region = prefs.getString(legacyKey);
      if (region != null) {
        await prefs.setString(key, region);
        await prefs.remove(legacyKey);
      }
    }
    final normalized = region?.trim() ?? '';
    if (normalized.isEmpty) {
      await clearRegion(channelIndex);
      return '';
    }
    if (normalized != region) {
      await prefs.setString(key, normalized);
    }
    return normalized;
  }

  Future<String> saveRegion(int channelIndex, String region) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn(
        'Public key hex is not set. Cannot save channel settings.',
      );
      return '';
    }

    final normalized = region.trim();
    if (normalized.isEmpty) {
      await clearRegion(channelIndex);
      return '';
    }

    final prefs = PrefsManager.instance;
    final key = channelStorageKey(keyFor, channelIndex);
    if (key == null) return '';
    await prefs.setString(key, normalized);
    return normalized;
  }

  Future<void> clearRegion(int channelIndex) async {
    final prefs = PrefsManager.instance;
    final key = channelStorageKey(keyFor, channelIndex);
    if (key != null) await prefs.remove(key);
    await prefs.remove('$keyFor$channelIndex');
  }
}
