import 'dart:convert';

import '../models/channel.dart';
import '../utils/app_logger.dart';
import 'channel_order_store.dart';
import 'channel_store.dart';
import 'prefs_manager.dart';

class ChannelIdentityReconcileHelper {
  // Keep channel stores index-based, but reconcile those indexes after sync.
  static bool enabled = true;

  static const List<String> _indexedPrefixes = [
    'channel_messages_',
    'channel_smaz_',
    'channel_mcmp_',
    'channel_cyr2lat_',
    'channel_sending_delay_',
    'channel_quick_answer_ids_',
    'channel_widget_color_',
    'channel_widget_text_color_',
    'channel_region_',
  ];

  _ChannelIdentitySyncSession? _activeSession;

  Future<ChannelIdentityReconcileResult?> reconcileChannelDuringSync({
    required String publicKeyHex,
    required List<Channel> previousChannelsCache,
    required List<Channel> currentChannels,
    required Channel receivedChannel,
    required ChannelStore channelStore,
  }) async {
    if (!enabled) return null;

    try {
      final session = await _ensureSession(
        publicKeyHex: publicKeyHex,
        previousChannelsCache: previousChannelsCache,
        channelStore: channelStore,
      );
      if (session == null) return null;

      final projectedChannels = [
        for (final channel in currentChannels)
          if (channel.index != receivedChannel.index) channel,
        if (!receivedChannel.isEmpty) receivedChannel,
      ];

      if (receivedChannel.isEmpty) {
        session.unmatchedNewIndexes.add(receivedChannel.index);
      } else {
        final oldChannel = _findPreviousMatch(
          session.previousChannels,
          receivedChannel,
        );
        if (oldChannel == null) {
          session.unmatchedNewIndexes.add(receivedChannel.index);
        } else {
          session.oldToNewIndex[oldChannel.index] = receivedChannel.index;
          session.unmatchedNewIndexes.remove(receivedChannel.index);
        }
      }

      return await _applySession(
        session,
        currentChannels: projectedChannels,
        finalized: false,
      );
    } catch (error, stackTrace) {
      appLogger.error(
        'Failed to reconcile received channel: $error\n$stackTrace',
        tag: 'ChannelReconcile',
      );
      return null;
    }
  }

  Future<ChannelIdentityReconcileResult?> reconcileAfterSync({
    required String publicKeyHex,
    required List<Channel> previousChannelsCache,
    required List<Channel> currentChannels,
    required ChannelStore channelStore,
    required ChannelOrderStore channelOrderStore,
  }) async {
    if (!enabled || currentChannels.isEmpty) return null;

    try {
      final session = await _ensureSession(
        publicKeyHex: publicKeyHex,
        previousChannelsCache: previousChannelsCache,
        channelStore: channelStore,
      );
      if (session == null) {
        final channelOrder = await channelOrderStore.loadChannelOrder();
        return ChannelIdentityReconcileResult(
          channels: List<Channel>.from(currentChannels),
          channelOrder: channelOrder,
          changed: false,
        );
      }

      session.oldToNewIndex
        ..clear()
        ..addAll(_buildIndexMapping(session.previousChannels, currentChannels));
      session.unmatchedNewIndexes
        ..clear()
        ..addAll(
          currentChannels
              .where((channel) => !channel.isEmpty)
              .map((channel) => channel.index)
              .where((index) => !session.oldToNewIndex.containsValue(index)),
        );

      final result = await _applySession(
        session,
        currentChannels: currentChannels,
        finalized: true,
      );
      _activeSession = null;
      return result;
    } catch (error, stackTrace) {
      _activeSession = null;
      appLogger.error(
        'Failed to reconcile channel identity after sync: $error\n$stackTrace',
        tag: 'ChannelReconcile',
      );
      return null;
    }
  }

  Future<ChannelIdentityReconcileResult> reconcile({
    required String publicKeyHex,
    required List<Channel> previousChannels,
    required List<Channel> currentChannels,
  }) async {
    final scopedKey = _publicKeyPrefix(publicKeyHex);
    if (!enabled || scopedKey.isEmpty || currentChannels.isEmpty) {
      return ChannelIdentityReconcileResult(
        channels: List<Channel>.from(currentChannels),
        channelOrder: const [],
        changed: false,
      );
    }

    final session = _createSession(
      scopedKey: scopedKey,
      previousChannels: previousChannels,
    );
    session.oldToNewIndex.addAll(
      _buildIndexMapping(session.previousChannels, currentChannels),
    );
    session.unmatchedNewIndexes.addAll(
      currentChannels
          .where((channel) => !channel.isEmpty)
          .map((channel) => channel.index)
          .where((index) => !session.oldToNewIndex.containsValue(index)),
    );
    return _applySession(
      session,
      currentChannels: currentChannels,
      finalized: true,
    );
  }

  void resetSyncSession() {
    _activeSession = null;
  }

  Future<_ChannelIdentitySyncSession?> _ensureSession({
    required String publicKeyHex,
    required List<Channel> previousChannelsCache,
    required ChannelStore channelStore,
  }) async {
    final scopedKey = _publicKeyPrefix(publicKeyHex);
    if (scopedKey.isEmpty) return null;

    final existing = _activeSession;
    if (existing != null && existing.scopedKey == scopedKey) {
      return existing;
    }

    final previousChannels = await channelStore.loadChannels();
    final fallbackPrevious = previousChannels.isNotEmpty
        ? previousChannels
        : previousChannelsCache;
    final session = _createSession(
      scopedKey: scopedKey,
      previousChannels: fallbackPrevious,
    );
    _activeSession = session;
    return session;
  }

  _ChannelIdentitySyncSession _createSession({
    required String scopedKey,
    required List<Channel> previousChannels,
  }) {
    final prefs = PrefsManager.instance;
    final allIndexedIndexes = _findIndexedIndexes(scopedKey);
    final snapshots = <int, List<_IndexedPrefSnapshot>>{};
    for (final index in {
      ...allIndexedIndexes,
      ...previousChannels.map((channel) => channel.index),
    }) {
      snapshots[index] = _readIndexedPrefs(scopedKey, index);
    }

    return _ChannelIdentitySyncSession(
      scopedKey: scopedKey,
      previousChannels: previousChannels.where((c) => !c.isEmpty).toList(),
      allIndexedIndexes: allIndexedIndexes,
      snapshots: snapshots,
      originalChannelOrder: prefs.getString(_channelOrderKey(scopedKey)),
      originalChannelGroups: prefs.getString(_channelGroupsKey(scopedKey)),
    );
  }

  Future<ChannelIdentityReconcileResult> _applySession(
    _ChannelIdentitySyncSession session, {
    required List<Channel> currentChannels,
    required bool finalized,
  }) async {
    final remapChanged = await _remapIndexedPrefs(
      session,
      currentChannels.where((c) => !c.isEmpty).toList(),
      finalized: finalized,
    );
    final orderChanged = await _remapChannelOrder(session, finalized);
    final groupsChanged = await _remapChannelGroups(session, finalized);
    final remappedIndexesChanged = session.oldToNewIndex.entries.any(
      (entry) => entry.key != entry.value,
    );
    final changed =
        remapChanged ||
        orderChanged ||
        groupsChanged ||
        remappedIndexesChanged ||
        session.unmatchedNewIndexes.isNotEmpty ||
        (finalized &&
            session.oldToNewIndex.length != session.previousChannels.length);

    if (remappedIndexesChanged) {
      appLogger.info(
        'Reconciled channel-index settings after channel sync: ${session.oldToNewIndex}',
        tag: 'ChannelReconcile',
      );
    }

    final oldByIndex = {
      for (final channel in session.previousChannels) channel.index: channel,
    };
    final channels = [
      for (final channel in currentChannels)
        Channel(
          index: channel.index,
          name: channel.name,
          psk: channel.psk,
          unreadCount:
              oldByIndex[_oldIndexForNew(session.oldToNewIndex, channel.index)]
                  ?.unreadCount ??
              0,
        ),
    ];

    return ChannelIdentityReconcileResult(
      channels: channels,
      channelOrder: _remapChannelOrderValues(session, finalized),
      changed: changed,
    );
  }

  Channel? _findPreviousMatch(List<Channel> previous, Channel current) {
    final byExact = _uniqueCurrentMap(
      previous,
      (channel) => '${_nameKey(channel)}|${_pskKey(channel)}',
    );
    final byPsk = _uniqueCurrentMap(previous, _pskKey);
    final byName = _uniqueCurrentMap(previous, _nameKey);
    return byExact['${_nameKey(current)}|${_pskKey(current)}'] ??
        byPsk[_pskKey(current)] ??
        byName[_nameKey(current)];
  }

  Map<int, int> _buildIndexMapping(
    List<Channel> previous,
    List<Channel> current,
  ) {
    final byExact = _uniqueCurrentMap(
      current,
      (channel) => '${_nameKey(channel)}|${_pskKey(channel)}',
    );
    final byPsk = _uniqueCurrentMap(current, _pskKey);
    final byName = _uniqueCurrentMap(current, _nameKey);
    final usedCurrentIndexes = <int>{};
    final mapping = <int, int>{};

    for (final oldChannel in previous) {
      // Name-only matching is intentional for legacy slots; duplicate names are
      // ignored by _uniqueCurrentMap so we do not pick a random channel.
      final candidates = [
        byExact['${_nameKey(oldChannel)}|${_pskKey(oldChannel)}'],
        byPsk[_pskKey(oldChannel)],
        byName[_nameKey(oldChannel)],
      ];
      for (final candidate in candidates) {
        if (candidate == null) continue;
        if (usedCurrentIndexes.contains(candidate.index)) continue;
        mapping[oldChannel.index] = candidate.index;
        usedCurrentIndexes.add(candidate.index);
        break;
      }
    }
    return mapping;
  }

  Map<String, Channel> _uniqueCurrentMap(
    List<Channel> channels,
    String Function(Channel channel) keyOf,
  ) {
    final result = <String, Channel>{};
    final duplicates = <String>{};
    for (final channel in channels) {
      final key = keyOf(channel);
      if (key.isEmpty) continue;
      if (result.containsKey(key)) {
        duplicates.add(key);
      } else {
        result[key] = channel;
      }
    }
    for (final key in duplicates) {
      result.remove(key);
    }
    return result;
  }

  Future<bool> _remapIndexedPrefs(
    _ChannelIdentitySyncSession session,
    List<Channel> currentChannels, {
    required bool finalized,
  }) async {
    var changed = false;
    final targetKeys = <String>{};
    for (final entry in session.oldToNewIndex.entries) {
      final values =
          session.snapshots[entry.key] ?? const <_IndexedPrefSnapshot>[];
      for (final value in values) {
        final key = value.keyFor(session.scopedKey, entry.value);
        final nextValue = _valueForNewIndex(value, entry.value);
        targetKeys.add(key);
        changed = await _writePrefIfChanged(key, nextValue) || changed;
      }
    }

    final impactedIndexes = finalized
        ? <int>{
            ...session.allIndexedIndexes,
            ...session.previousChannels.map((channel) => channel.index),
            ...currentChannels.map((channel) => channel.index),
          }
        : <int>{
            ...session.oldToNewIndex.values,
            ...session.unmatchedNewIndexes,
          };
    changed =
        await _clearIndexedData(
          session.scopedKey,
          impactedIndexes,
          keepKeys: targetKeys,
        ) ||
        changed;
    return changed;
  }

  List<_IndexedPrefSnapshot> _readIndexedPrefs(String scopedKey, int index) {
    final prefs = PrefsManager.instance;
    final snapshots = <_IndexedPrefSnapshot>[];
    for (final prefix in _indexedPrefixes) {
      final key = '$prefix$scopedKey$index';
      final value = prefs.get(key);
      if (value != null) {
        snapshots.add(_IndexedPrefSnapshot(prefix, value));
      }
    }

    final profileKey = _cyr2LatProfileKey(scopedKey, index);
    final profileValue = prefs.get(profileKey);
    if (profileValue != null) {
      snapshots.add(_IndexedPrefSnapshot._profile(profileValue));
    }
    return snapshots;
  }

  Future<bool> _clearIndexedData(
    String scopedKey,
    Set<int> indexes, {
    Set<String> keepKeys = const {},
  }) async {
    final prefs = PrefsManager.instance;
    var changed = false;
    for (final index in indexes) {
      for (final key in _indexedKeysForIndex(scopedKey, index)) {
        if (keepKeys.contains(key) || !prefs.containsKey(key)) continue;
        await prefs.remove(key);
        changed = true;
      }
    }
    return changed;
  }

  Future<bool> _remapChannelOrder(
    _ChannelIdentitySyncSession session,
    bool finalized,
  ) async {
    final prefs = PrefsManager.instance;
    final raw = session.originalChannelOrder;
    if (raw == null || raw.isEmpty) return false;

    final remapped = _remapChannelOrderValues(session, finalized);
    final currentRaw = prefs.getString(_channelOrderKey(session.scopedKey));
    if (_prefValueEquals(_parseIndexList(currentRaw ?? ''), remapped)) {
      return false;
    }

    await prefs.setString(
      _channelOrderKey(session.scopedKey),
      jsonEncode(remapped),
    );
    return true;
  }

  List<int> _remapChannelOrderValues(
    _ChannelIdentitySyncSession session,
    bool finalized,
  ) {
    final raw = session.originalChannelOrder;
    if (raw == null || raw.isEmpty) return const [];
    return _remapIndexList(_parseIndexList(raw), session, finalized);
  }

  Future<bool> _remapChannelGroups(
    _ChannelIdentitySyncSession session,
    bool finalized,
  ) async {
    final prefs = PrefsManager.instance;
    final raw = session.originalChannelGroups;
    if (raw == null || raw.isEmpty) return false;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return false;
      final remappedGroups = <dynamic>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final group = Map<String, dynamic>.from(item);
        final channels =
            (group['channels'] as List?)
                ?.map((value) => int.tryParse(value.toString()))
                .whereType<int>()
                .toList() ??
            const <int>[];
        group['channels'] = _remapIndexList(channels, session, finalized);
        remappedGroups.add(group);
      }

      final encoded = jsonEncode(remappedGroups);
      if (prefs.getString(_channelGroupsKey(session.scopedKey)) == encoded) {
        return false;
      }
      await prefs.setString(_channelGroupsKey(session.scopedKey), encoded);
      return true;
    } catch (_) {
      // Bad group JSON should not block channel sync.
      return false;
    }
  }

  List<int> _parseIndexList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((value) => value is int ? value : int.tryParse('$value'))
            .whereType<int>()
            .toList();
      }
    } catch (_) {
      // Fall back to legacy comma-separated format below.
    }
    return raw
        .split(',')
        .map((value) => int.tryParse(value))
        .whereType<int>()
        .toList();
  }

  List<int> _remapIndexList(
    List<int> indexes,
    _ChannelIdentitySyncSession session,
    bool finalized,
  ) {
    final seen = <int>{};
    final remapped = <int>[];
    for (final index in indexes) {
      final next = session.oldToNewIndex[index];
      if (next != null) {
        if (seen.add(next)) remapped.add(next);
        continue;
      }
      if (finalized || session.unmatchedNewIndexes.contains(index)) {
        continue;
      }
      if (seen.add(index)) remapped.add(index);
    }
    return remapped;
  }

  Future<bool> _writePrefIfChanged(String key, Object value) async {
    final prefs = PrefsManager.instance;
    if (_prefValueEquals(prefs.get(key), value)) return false;

    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is List) {
      await prefs.setStringList(key, value.whereType<String>().toList());
    }
    return true;
  }

  Object _valueForNewIndex(_IndexedPrefSnapshot snapshot, int newIndex) {
    if (snapshot.prefix != 'channel_messages_' || snapshot.value is! String) {
      return snapshot.value;
    }

    try {
      final decoded = jsonDecode(snapshot.value as String);
      if (decoded is! List) return snapshot.value;
      final updated = decoded.map((entry) {
        if (entry is! Map) return entry;
        final message = Map<String, dynamic>.from(entry);
        message['channelIndex'] = newIndex;
        return message;
      }).toList();
      return jsonEncode(updated);
    } catch (_) {
      return snapshot.value;
    }
  }

  Set<int> _findIndexedIndexes(String scopedKey) {
    final prefs = PrefsManager.instance;
    final indexes = <int>{};
    for (final key in prefs.getKeys()) {
      for (final prefix in _indexedPrefixes) {
        if (!key.startsWith('$prefix$scopedKey')) continue;
        final suffix = key.substring(prefix.length + scopedKey.length);
        final index = int.tryParse(suffix);
        if (index != null) indexes.add(index);
      }

      final profilePrefix = 'channel_cyr2lat_${scopedKey}profile_';
      if (key.startsWith(profilePrefix)) {
        final index = int.tryParse(key.substring(profilePrefix.length));
        if (index != null) indexes.add(index);
      }
    }
    return indexes;
  }

  Iterable<String> _indexedKeysForIndex(String scopedKey, int index) sync* {
    for (final prefix in _indexedPrefixes) {
      yield '$prefix$scopedKey$index';
    }
    yield _cyr2LatProfileKey(scopedKey, index);
  }

  bool _prefValueEquals(Object? left, Object right) {
    if (left is List && right is List) {
      return _listEquals(left, right);
    }
    return left == right;
  }

  bool _listEquals(List<Object?> left, List<Object?> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  int? _oldIndexForNew(Map<int, int> mapping, int newIndex) {
    for (final entry in mapping.entries) {
      if (entry.value == newIndex) return entry.key;
    }
    return null;
  }

  String _publicKeyPrefix(String value) =>
      value.length >= 10 ? value.substring(0, 10) : '';

  String _nameKey(Channel channel) => channel.name.trim().toLowerCase();

  String _pskKey(Channel channel) => channel.pskHex.toLowerCase();

  String _cyr2LatProfileKey(String scopedKey, int index) =>
      'channel_cyr2lat_${scopedKey}profile_$index';

  String _channelOrderKey(String scopedKey) => 'channel_order_$scopedKey';

  String _channelGroupsKey(String scopedKey) => 'channel_groups$scopedKey';
}

class ChannelIdentityReconcileResult {
  final List<Channel> channels;
  final List<int> channelOrder;
  final bool changed;

  const ChannelIdentityReconcileResult({
    required this.channels,
    required this.channelOrder,
    required this.changed,
  });
}

class _ChannelIdentitySyncSession {
  final String scopedKey;
  final List<Channel> previousChannels;
  final Set<int> allIndexedIndexes;
  final Map<int, List<_IndexedPrefSnapshot>> snapshots;
  final String? originalChannelOrder;
  final String? originalChannelGroups;
  final Map<int, int> oldToNewIndex = {};
  final Set<int> unmatchedNewIndexes = {};

  _ChannelIdentitySyncSession({
    required this.scopedKey,
    required this.previousChannels,
    required this.allIndexedIndexes,
    required this.snapshots,
    required this.originalChannelOrder,
    required this.originalChannelGroups,
  });
}

class _IndexedPrefSnapshot {
  final String prefix;
  final Object value;
  final bool isProfile;

  const _IndexedPrefSnapshot(this.prefix, this.value) : isProfile = false;

  const _IndexedPrefSnapshot._profile(this.value)
    : prefix = '',
      isProfile = true;

  String keyFor(String scopedKey, int index) {
    if (isProfile) {
      return 'channel_cyr2lat_${scopedKey}profile_$index';
    }
    return '$prefix$scopedKey$index';
  }
}
