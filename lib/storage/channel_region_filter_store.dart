import 'package:flutter/foundation.dart' show kIsWeb;

import '../helpers/channel_region_filter.dart';
import 'message_history_storage.dart';
import 'prefs_manager.dart';

/// Native: SQL, keyed by node scope and channel PSK ID, independent of radio slot.
class ChannelRegionFilterStore {
  static String _key(String node, String channel) => 'channel_region_filter:$node:$channel';

  Future<String?> read(String node, String channel) async {
    if (node.isEmpty || channel.isEmpty) return null;
    final value = kIsWeb
        ? PrefsManager.instance.getString(_key(node, channel))
        : await MessageHistoryStorage.instance.readChannelRegionFilter(node, channel);
    return ChannelRegionFilter.canonical(value);
  }

  Future<bool> importIfMissing(String node, String channel, String encoded) async {
    if (kIsWeb) {
      if (await read(node, channel) != null) return false;
      await write(node, channel, ChannelRegionFilter.decode(encoded));
      return true;
    }
    return MessageHistoryStorage.instance.importChannelRegionFilter(node, channel, encoded);
  }

  Future<void> write(String node, String channel, Iterable<String> hidden) async {
    final encoded = ChannelRegionFilter.encode(hidden);
    if (kIsWeb) {
      if (!await PrefsManager.instance.setString(_key(node, channel), encoded)) {
        throw StateError('Could not save channel region filter');
      }
    } else {
      await MessageHistoryStorage.instance.writeChannelRegionFilter(node, channel, encoded);
    }
  }
}
