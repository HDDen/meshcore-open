import 'dart:convert';
import 'dart:typed_data';

import '../models/channel.dart';
import '../utils/app_logger.dart';
import 'message_history_storage.dart';
import 'node_state.dart';
import 'prefs_manager.dart';

/// The channels a node holds. They live in the `node_channels` table of the
/// database, one row per slot holding the JSON [_toJson] writes; the web
/// build, and a process that never opened the database such as a unit test,
/// keep the whole list in preferences under `channels<node>` as before.
class ChannelStore {
  static const String _keyPrefix = 'channels';
  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length >= 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';

  /// Per node, the rows the database holds, as the JSON last loaded or
  /// written per slot. The connector saves its whole list on every incoming
  /// channel message, for the unread count, which changes a channel in
  /// place, so the comparison is by content rather than identity: a save
  /// writes only the slots whose JSON differs and deletes only against a
  /// list a load had seen.
  final Map<String, Map<int, String>> _stored = {};

  /// Database writes run one after another, each measured against what the
  /// one before it left.
  Future<void> _writes = Future.value();

  Future<List<Channel>> loadChannels({bool allowLegacyMigration = true}) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot load channels.');
      return [];
    }
    final storage = MessageHistoryStorage.instance;
    if (!storage.hasDatabase) {
      return _loadFromPreferences(allowLegacyMigration: allowLegacyMigration);
    }
    final node = publicKeyHex;
    await _writes;
    final channels = <Channel>[];
    final stored = <int, String>{};
    for (final row in await storage.loadNodeChannels(node)) {
      try {
        final channel = _fromJson(jsonDecode(row) as Map<String, dynamic>);
        channels.add(channel);
        stored[channel.index] = row;
      } catch (e) {
        appLogger.warn('Skipping malformed stored channel: $e');
      }
    }
    _stored[node] = stored;
    return channels;
  }

  Future<void> saveChannels(List<Channel> channels) {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot save channels.');
      return Future.value();
    }
    if (!MessageHistoryStorage.instance.hasDatabase) {
      final jsonList = channels.map(_toJson).toList();
      return PrefsManager.instance.setString(keyFor, jsonEncode(jsonList));
    }
    // Encoded now: the unread count changes in place, and the node may
    // change before this write gets its turn.
    final node = publicKeyHex;
    final next = {
      for (final channel in channels) channel.index: jsonEncode(_toJson(channel)),
    };
    final write = _writes.then((_) => _writeRows(node, next));
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<void> _writeRows(String node, Map<int, String> next) async {
    final stored = _stored[node];
    await MessageHistoryStorage.instance.writeNodeChannels(
      nodeKey: node,
      upserts: {
        for (final entry in next.entries)
          if (stored?[entry.key] != entry.value) entry.key: entry.value,
      },
      deleteIndexes: [
        if (stored != null)
          for (final index in stored.keys)
            if (!next.containsKey(index)) index,
      ],
    );
    _stored[node] = next;
  }

  Future<List<Channel>> _loadFromPreferences({
    required bool allowLegacyMigration,
  }) async {
    final prefs = PrefsManager.instance;
    String? jsonString = prefs.getString(keyFor);
    if ((jsonString == null || jsonString.isEmpty) && allowLegacyMigration) {
      jsonString = await NodeState.takeOverLegacyPreference(
        legacyKey: _keyPrefix,
        preferenceKey: keyFor,
      );
    }
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList
          .map((entry) => _fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _toJson(Channel channel) {
    return {
      'index': channel.index,
      'name': channel.name,
      'psk': base64Encode(channel.psk),
      'unreadCount': channel.unreadCount,
    };
  }

  Channel _fromJson(Map<String, dynamic> json) {
    return Channel(
      index: json['index'] as int,
      name: json['name'] as String? ?? '',
      psk: json['psk'] != null
          ? Uint8List.fromList(base64Decode(json['psk'] as String))
          : Uint8List(16),
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }
}
