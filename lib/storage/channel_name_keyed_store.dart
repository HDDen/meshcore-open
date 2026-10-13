import 'dart:convert';

import '../models/channel.dart';
import 'channel_identity_store.dart';
import 'prefs_manager.dart';

/// The per-channel stores key their data by the channel's name, never by its
/// radio slot: a slot is reused for other channels, and the same channel
/// sits in different slots on different nodes. The connector registers each
/// slot's channel here, and the stores turn a slot into the key of the name
/// it holds.
///
/// A channel renamed under the same key, or rekeyed under the same name,
/// keeps its data through [ChannelIdentities]: [channelStorageKeys] lists the
/// keys of every name the channel has had, its own first, and
/// [channelInheritedKeys] the keys a setting may be read from when the
/// channel's own holds none, the other names in this scope and then every
/// node's scopes, so a node that never set anything for a channel takes the
/// settings another node keeps for it.
mixin ChannelNameKeyedStore {
  final Map<int, String> _channelNamesByIndex = {};
  final Map<int, String> _channelPskIdsByIndex = {};
  bool _allowsLegacyIndexMigration = true;

  bool get allowsLegacyIndexMigration => _allowsLegacyIndexMigration;

  void beginLegacyIndexMigration() {
    _allowsLegacyIndexMigration = true;
  }

  void finishLegacyIndexMigration() {
    _allowsLegacyIndexMigration = false;
  }

  void replaceChannels(Iterable<Channel> channels) {
    _channelNamesByIndex.clear();
    _channelPskIdsByIndex.clear();
    for (final channel in channels) {
      registerChannel(channel);
    }
  }

  void registerChannel(Channel channel) {
    if (channel.isEmpty || channel.name.trim().isEmpty) {
      _channelNamesByIndex.remove(channel.index);
      _channelPskIdsByIndex.remove(channel.index);
      return;
    }
    _channelNamesByIndex[channel.index] = channel.name.trim();
    final pskId = channel.storageId;
    if (pskId == null) {
      _channelPskIdsByIndex.remove(channel.index);
    } else {
      _channelPskIdsByIndex[channel.index] = pskId;
    }
  }

  String? channelNameForIndex(int channelIndex) {
    return _channelNamesByIndex[channelIndex];
  }

  /// The key-and-name pair of the channel in [channelIndex], or null when the
  /// slot is empty or its channel has no name.
  ChannelIdentity? channelIdentityForIndex(int channelIndex) {
    final name = _channelNamesByIndex[channelIndex];
    final pskId = _channelPskIdsByIndex[channelIndex];
    if (name == null || pskId == null) return null;
    return ChannelIdentity(pskId, name);
  }

  /// The names the channel in [channelIndex] is read under, its own first.
  List<String> channelNamesForIndex(int channelIndex) {
    final identity = channelIdentityForIndex(channelIndex);
    if (identity != null) return ChannelIdentities.instance.namesOf(identity);
    final name = _channelNamesByIndex[channelIndex];
    return name == null ? const [] : [name];
  }

  static String encodeChannelName(String channelName) =>
      base64Url.encode(utf8.encode(channelName)).replaceAll('=', '');

  /// The key [keyPrefix] gives a channel named [channelName].
  static String nameStorageKey(String keyPrefix, String channelName) =>
      '${keyPrefix}name_${encodeChannelName(channelName)}';

  String? channelStorageKey(String keyPrefix, int channelIndex) {
    final channelName = channelNameForIndex(channelIndex);
    if (channelName == null || channelName.isEmpty) return null;
    return nameStorageKey(keyPrefix, channelName);
  }

  /// Every key the channel in [channelIndex] may keep data under in this
  /// scope: its own name's key first, then the keys of the other names its
  /// channel has had. Empty for an empty slot.
  List<String> channelStorageKeys(String keyPrefix, int channelIndex) => [
    for (final name in channelNamesForIndex(channelIndex))
      nameStorageKey(keyPrefix, name),
  ];

  /// Keys a value for the channel in [channelIndex] may be read from when
  /// its own key holds none: the other names of its channel in this scope,
  /// then the channel's names in every other node's scope, in a fixed order.
  /// [keyPrefix] carries [scope] (the node's ten hex characters) where the
  /// store puts it, which is how the other scopes' keys are found among the
  /// stored preference keys.
  List<String> channelInheritedKeys({
    required String keyPrefix,
    required String scope,
    required int channelIndex,
  }) {
    final names = channelNamesForIndex(channelIndex);
    if (names.isEmpty) return const [];
    final keys = <String>[
      for (final name in names.skip(1)) nameStorageKey(keyPrefix, name),
    ];
    final at = scope.isEmpty ? -1 : keyPrefix.indexOf(scope);
    if (at < 0) return keys;
    final pattern = RegExp(
      '^${RegExp.escape(keyPrefix.substring(0, at))}'
      '([0-9a-fA-F]{${scope.length}})'
      '${RegExp.escape(keyPrefix.substring(at + scope.length))}'
      r'name_([A-Za-z0-9_-]+)$',
    );
    final encodedNames = {for (final name in names) encodeChannelName(name)};
    final foreign = <String>[];
    for (final key in PrefsManager.instance.getKeys()) {
      final match = pattern.firstMatch(key);
      if (match == null) continue;
      if (match.group(1)!.toLowerCase() == scope.toLowerCase()) continue;
      if (!encodedNames.contains(match.group(2))) continue;
      foreign.add(key);
    }
    foreign.sort();
    return [...keys, ...foreign];
  }
}
