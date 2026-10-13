import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../utils/app_logger.dart';
import 'message_history_database.dart' show ChannelIdentityRow;
import 'message_history_storage.dart';
import 'prefs_manager.dart';

/// One pair of key and name a channel was seen under: the storage ID of its
/// PSK ([Channel.storageIdForPsk]) and its name as the storage keys use it,
/// trimmed. A radio slot is never part of it: the same channel sits in
/// different slots on different nodes, and another app may move it.
@immutable
class ChannelIdentity {
  final String pskId;
  final String name;

  const ChannelIdentity(this.pskId, this.name);

  /// The identity of [channel], or null for an empty slot or a nameless one.
  static ChannelIdentity? of(Channel channel) {
    final pskId = channel.storageId;
    final name = channel.name.trim();
    if (pskId == null || name.isEmpty) return null;
    return ChannelIdentity(pskId, name);
  }

  @override
  bool operator ==(Object other) =>
      other is ChannelIdentity && other.pskId == pskId && other.name == name;

  @override
  int get hashCode => Object.hash(pskId, name);

  @override
  String toString() => '$name@$pskId';
}

/// Which pairs of key and name are one channel.
///
/// Per-channel data is keyed by the channel's name, so a channel renamed
/// under the same key, or rekeyed under the same name, used to start over:
/// its history, settings and region stayed under the old name. This table
/// records every pair a channel went through, in groups: a group is one
/// logical channel, its rows the aliases. A pair with no row is a group of
/// itself. The stores read a channel's data under every name of its group,
/// in this node's scope and in the other nodes', and write under the current
/// name.
///
/// A link is recorded only when exactly one of the two parameters changed:
/// by the edit sheet and the link import through `setChannel`, and by the
/// channel sync comparing the node's list before and after as sets (see
/// `ChannelIdentityReconciler`). Both changed is a new channel.
///
/// App-wide, like the discovered contacts: a channel is the same channel on
/// every node of one owner, which is what the name keying is for.
class ChannelIdentities extends ChangeNotifier {
  ChannelIdentities._();

  static final ChannelIdentities instance = ChannelIdentities._();

  /// The preference form, for the web build and a process without the
  /// database: the rows as one JSON array.
  static const String preferenceKey = 'channel_identities_v1';

  final Map<ChannelIdentity, int> _groupOf = {};
  final Map<int, Set<ChannelIdentity>> _members = {};
  int _nextGroupId = 1;
  int _revision = 0;
  bool _loaded = false;

  /// Moves on every change, for caches keyed on what a channel's history
  /// consists of.
  int get revision => _revision;

  bool get isLoaded => _loaded;

  bool get isEmpty => _groupOf.isEmpty;

  /// Reads the table; the lookups are synchronous afterwards.
  Future<void> load() async {
    _groupOf.clear();
    _members.clear();
    _nextGroupId = 1;
    try {
      final rows = MessageHistoryStorage.instance.hasDatabase
          ? await MessageHistoryStorage.instance.readChannelIdentities()
          : _rowsFromPreferences();
      for (final row in rows) {
        _add(row.groupId, ChannelIdentity(row.pskId, row.name));
      }
    } catch (e) {
      appLogger.warn(
        'Channel identities could not be read: $e',
        tag: 'ChannelIdentity',
      );
    }
    _loaded = true;
    _revision++;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTesting() {
    _groupOf.clear();
    _members.clear();
    _nextGroupId = 1;
    _loaded = false;
    _revision++;
  }

  int? groupIdOf(ChannelIdentity identity) => _groupOf[identity];

  /// The pairs of [identity]'s group, [identity] included.
  Set<ChannelIdentity> membersOf(ChannelIdentity identity) {
    final group = _groupOf[identity];
    if (group == null) return {identity};
    return Set.unmodifiable(_members[group]!);
  }

  /// Every name the channel [identity] belongs to has had, its own first.
  List<String> namesOf(ChannelIdentity identity) {
    final names = <String>[identity.name];
    for (final member in membersOf(identity)) {
      if (!names.contains(member.name)) names.add(member.name);
    }
    return names;
  }

  /// The names linked to [name] through any channel that carried it, [name]
  /// first. For what is kept by the name alone (marker styles, mutes) and
  /// so cannot tell which key the name belonged to.
  List<String> namesLinkedTo(String name) {
    final trimmed = name.trim();
    final names = <String>[trimmed];
    for (final entry in _groupOf.entries) {
      if (entry.key.name != trimmed) continue;
      for (final member in _members[entry.value]!) {
        if (!names.contains(member.name)) names.add(member.name);
      }
    }
    return names;
  }

  bool sameChannel(ChannelIdentity a, ChannelIdentity b) {
    if (a == b) return true;
    final group = _groupOf[a];
    return group != null && group == _groupOf[b];
  }

  /// The channel among [channels] that is [identity]'s channel: the one
  /// carrying the pair itself, else one carrying another pair of its group.
  Channel? findInGroup(Iterable<Channel> channels, ChannelIdentity identity) {
    final members = membersOf(identity);
    Channel? inGroup;
    for (final channel in channels) {
      final candidate = ChannelIdentity.of(channel);
      if (candidate == null) continue;
      if (candidate == identity) return channel;
      if (inGroup == null && members.contains(candidate)) inGroup = channel;
    }
    return inGroup;
  }

  /// Records that [a] and [b] are one channel. Returns false when the table
  /// already said so.
  Future<bool> link(ChannelIdentity a, ChannelIdentity b) async {
    if (a == b) return false;
    final groupA = _groupOf[a];
    final groupB = _groupOf[b];
    if (groupA != null && groupA == groupB) return false;
    if (groupA == null && groupB == null) {
      final id = _nextGroupId++;
      _add(id, a);
      _add(id, b);
    } else if (groupA == null) {
      _add(groupB!, a);
    } else if (groupB == null) {
      _add(groupA, b);
    } else {
      // Two groups meet: the smaller one joins the larger.
      final (keep, drop) = _members[groupA]!.length >= _members[groupB]!.length
          ? (groupA, groupB)
          : (groupB, groupA);
      for (final member in _members.remove(drop)!) {
        _add(keep, member);
      }
    }
    appLogger.info('Channel $a is now also $b', tag: 'ChannelIdentity');
    await _persist();
    return true;
  }

  /// Forgets the whole group of [identity]; nothing to do for a pair of
  /// itself.
  Future<void> forget(ChannelIdentity identity) async {
    final group = _groupOf[identity];
    if (group == null) return;
    for (final member in _members.remove(group)!) {
      _groupOf.remove(member);
    }
    await _persist();
  }

  List<ChannelIdentityRow> get rows => [
    for (final entry in _groupOf.entries)
      (groupId: entry.value, pskId: entry.key.pskId, name: entry.key.name),
  ];

  void _add(int groupId, ChannelIdentity identity) {
    _groupOf[identity] = groupId;
    (_members[groupId] ??= <ChannelIdentity>{}).add(identity);
    if (groupId >= _nextGroupId) _nextGroupId = groupId + 1;
  }

  Future<void> _persist() async {
    _revision++;
    notifyListeners();
    try {
      final rows = this.rows;
      if (MessageHistoryStorage.instance.hasDatabase) {
        await MessageHistoryStorage.instance.replaceChannelIdentities(rows);
      } else {
        await PrefsManager.instance.setString(
          preferenceKey,
          jsonEncode([
            for (final row in rows)
              {'g': row.groupId, 'p': row.pskId, 'n': row.name},
          ]),
        );
      }
    } catch (e) {
      appLogger.warn(
        'Channel identities could not be written: $e',
        tag: 'ChannelIdentity',
      );
    }
  }

  List<ChannelIdentityRow> _rowsFromPreferences() {
    final raw = PrefsManager.instance.getString(preferenceKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded)
        if (entry is Map &&
            entry['g'] is int &&
            entry['p'] is String &&
            entry['n'] is String)
          (
            groupId: entry['g'] as int,
            pskId: entry['p'] as String,
            name: entry['n'] as String,
          ),
    ];
  }
}
