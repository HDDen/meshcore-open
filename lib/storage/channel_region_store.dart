import '../utils/app_logger.dart';
import 'channel_name_keyed_store.dart';
import 'prefs_manager.dart';

class ChannelRegionStore with ChannelNameKeyedStore {
  static const String _keyPrefix = 'channel_region_';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length >= 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';

  /// Reads and never writes: the connector loads every channel's region at
  /// the handshake and again per synced channel, and on Windows and Linux
  /// each write rewrites the whole preferences file, so a load that tidied
  /// the stored value cost several full rewrites per named channel and
  /// connection. A value stored under the slot number of the time before
  /// the keys carried the channel name is read as it is; [saveRegion] moves
  /// it, and a stored value that only needs trimming is trimmed on the way
  /// out.
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
      region = prefs.getString('$keyFor$channelIndex');
    }
    // The channel's other names here, then the other nodes (see
    // ChannelSettingsStore): a region is the channel's, not the node's.
    if (region == null) {
      for (final inheritedKey in channelInheritedKeys(
        keyPrefix: keyFor,
        scope: publicKeyHex,
        channelIndex: channelIndex,
      )) {
        region = prefs.getString(inheritedKey);
        if (region != null) break;
      }
    }
    return region?.trim() ?? '';
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
    final legacyKey = '$keyFor$channelIndex';
    if (prefs.containsKey(legacyKey)) await prefs.remove(legacyKey);
    return normalized;
  }

  Future<void> clearRegion(int channelIndex) async {
    final prefs = PrefsManager.instance;
    // A removal of a key that is not there still rewrites the whole file.
    for (final key in channelStorageKeys(keyFor, channelIndex)) {
      if (prefs.containsKey(key)) await prefs.remove(key);
    }
    final legacyKey = '$keyFor$channelIndex';
    if (prefs.containsKey(legacyKey)) await prefs.remove(legacyKey);
  }

  /// Removes, in this scope, the region stored under each of [names]: what
  /// a deletion reaching every node does in the other nodes' scopes.
  Future<void> clearRegionsForNames(Iterable<String> names) async {
    if (publicKeyHex.isEmpty) return;
    final prefs = PrefsManager.instance;
    for (final name in names) {
      final key = ChannelNameKeyedStore.nameStorageKey(keyFor, name);
      if (prefs.containsKey(key)) await prefs.remove(key);
    }
  }
}
