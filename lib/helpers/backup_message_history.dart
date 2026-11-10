import 'dart:convert';

import '../models/channel.dart';
import '../models/channel_message.dart';
import '../models/message.dart';
import '../storage/channel_identity_store.dart';
import '../storage/channel_message_store.dart';
import '../storage/channel_name_keyed_store.dart';
import '../storage/contact_identity_store.dart';
import '../storage/message_history_database.dart' show HistoryBackupBatch;
import '../storage/message_history_storage.dart';
import '../storage/message_store.dart';

class BackupMessageHistory {
  BackupMessageHistory._(this.nodeKey, this.direct, this.channels);

  static final _contactKey = RegExp(r'^[0-9a-f]{64}$');
  static final _channelId = RegExp(r'^[0-9a-f]{16}$');
  static const _invalid = FormatException('Invalid backup message history');

  final String nodeKey;
  final Map<String, List<Map<String, dynamic>>> direct;
  final Map<String, List<Map<String, dynamic>>> channels;

  static BackupMessageHistory? read(
    Map<String, Object?> payload,
    String? nodeKey,
  ) {
    final items = payload['items'] as List<Object?>;
    if (!items.contains('contactHistory') && !items.contains('channelHistory')) {
      return null;
    }
    if (nodeKey == null) throw _invalid;
    final scope = nodeKey.substring(0, 10);
    final sections = payload['sections'] as Map<String, Object?>;
    final direct = items.contains('contactHistory')
        ? _readHistories(sections['contacts'], 'messages_$scope', _contactKey)
        : const <String, List<Map<String, dynamic>>>{};
    final channels = items.contains('channelHistory')
        ? _readHistories(
            sections['channels'],
            'channel_messages_${scope}_',
            _channelId,
            channel: true,
          )
        : const <String, List<Map<String, dynamic>>>{};
    if (direct.isEmpty && channels.isEmpty) return null;
    return BackupMessageHistory._(nodeKey, direct, channels);
  }

  static Map<String, List<Map<String, dynamic>>> _readHistories(
    Object? section,
    String prefix,
    RegExp identity, {
    bool channel = false,
  }) {
    if (section == null) return const {};
    if (section is! Map<String, Object?>) throw _invalid;
    final preferences = section['preferences'];
    if (preferences == null) return const {};
    if (preferences is! Map<String, Object?>) throw _invalid;
    final histories = <String, List<Map<String, dynamic>>>{};
    for (final entry in preferences.entries) {
      final key = entry.key.toLowerCase();
      if (!key.startsWith(prefix)) continue;
      final id = key.substring(prefix.length);
      if (!identity.hasMatch(id)) continue;
      if (histories.containsKey(id)) throw _invalid;
      final value = entry.value;
      final decoded = value is String ? jsonDecode(value) : value;
      if (decoded is! List<Object?>) throw _invalid;
      histories[id] = List.unmodifiable([
        for (final row in decoded) _readMessage(row, channel: channel),
      ]);
    }
    histories.removeWhere((_, rows) => rows.isEmpty);
    return Map.unmodifiable(histories);
  }

  static Map<String, dynamic> _readMessage(Object? raw, {required bool channel}) {
    if (raw is! Map<String, dynamic>) throw _invalid;
    final row = Map<String, dynamic>.of(raw);
    try {
      row['isOutgoing'] ??= false;
      if (channel) {
        row['senderName'] ??= 'Unknown';
        row['status'] ??= ChannelMessageStatus.failed.index;
        if (row['status'] == ChannelMessageStatus.pending.index) {
          row['status'] = ChannelMessageStatus.failed.index;
        }
        ChannelMessageStore.decodeStoredMessage(row);
      } else {
        row['status'] ??= MessageStatus.failed.index;
        if (row['status'] == MessageStatus.pending.index) {
          row['status'] = MessageStatus.failed.index;
        }
        MessageStore.decodeStoredMessage(row);
      }
    } on Object {
      throw _invalid;
    }
    return Map.unmodifiable(row);
  }

  BackupMessageHistoryPreview preview({
    required Iterable<Channel> destination,
    required Object session,
  }) {
    final scope = nodeKey.substring(0, 10);
    final batches = <HistoryBackupBatch>[
      for (final entry in direct.entries)
        (
          kind: MessageHistoryKind.direct.index,
          key: 'messages_$scope${entry.key}',
          aliases: [
            for (final alias in ContactIdentities.instance.keysOf(entry.key).skip(1))
              'messages_$scope$alias',
          ],
          messages: entry.value,
        ),
    ];
    final candidates = <String, List<Channel>>{};
    final nameOwners = <String, Set<String>>{};
    for (final channel in destination) {
      final identity = ChannelIdentity.of(channel);
      if (identity == null) continue;
      (candidates[identity.pskId] ??= []).add(channel);
      for (final name in ChannelIdentities.instance.namesOf(identity)) {
        (nameOwners[name] ??= {}).add(identity.pskId);
      }
    }
    final targets = <int, ChannelIdentity>{};
    var skipped = 0;
    final prefix = 'channel_messages_$scope';
    for (final entry in channels.entries) {
      final matches = candidates[entry.key];
      if (matches == null || matches.length != 1) {
        skipped += entry.value.length;
        continue;
      }
      final target = matches.single;
      final identity = ChannelIdentity.of(target)!;
      if (nameOwners[identity.name]!.length != 1) {
        skipped += entry.value.length;
        continue;
      }
      targets[target.index] = identity;
      batches.add((
        kind: MessageHistoryKind.channel.index,
        key: ChannelNameKeyedStore.nameStorageKey(prefix, identity.name),
        aliases: [
          for (final name in ChannelIdentities.instance.namesOf(identity).skip(1))
            if (nameOwners[name]!.length == 1)
              ChannelNameKeyedStore.nameStorageKey(prefix, name),
        ],
        messages: entry.value,
      ));
    }
    return BackupMessageHistoryPreview._(
      source: this,
      session: session,
      batches: List.unmodifiable(batches),
      channelTargets: Map.unmodifiable(targets),
      skipped: skipped,
    );
  }
}

class BackupMessageHistoryPreview {
  BackupMessageHistoryPreview._({
    required this.source,
    required this.session,
    required this.batches,
    required this.channelTargets,
    required this.skipped,
  });

  final BackupMessageHistory source;
  final Object session;
  final List<HistoryBackupBatch> batches;
  final Map<int, ChannelIdentity> channelTargets;
  final int skipped;
  int get count => batches.fold(0, (sum, batch) => sum + batch.messages.length);
}
