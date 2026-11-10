import '../models/channel.dart';

enum BackupChannelAction {
  alreadyPresent,
  rename,
  add,
  duplicateInBackup,
  nameConflict,
  noFreeSlot,
  unconfirmedSlot,
}

typedef BackupChannelDecision = ({
  Channel source,
  BackupChannelAction action,
  Channel? destination,
});

/// Resolves source channels against the destination's confirmed inventory.
/// The backup's slot is a preference when adding a channel.
List<BackupChannelDecision> resolveBackupChannels(
  Iterable<Channel> backup, {
  required Iterable<Channel> destination,
  required int capacity,
  required Set<int> unconfirmedSlots,
}) {
  final live = destination.where((channel) => !channel.isEmpty).toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  final sources = backup.where((channel) => !channel.isEmpty).toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  final decisions = <BackupChannelDecision>[];
  final additions = <String, Channel>{};
  final duplicates = <Channel>[];
  final matches = <int, ({Channel current, List<Channel> sources})>{};
  final liveByKey = <String, List<Channel>>{};
  for (final channel in live) {
    (liveByKey[channel.pskHex] ??= []).add(channel);
  }

  for (final source in sources) {
    final key = source.pskHex;
    final name = _nameKey(source);
    final matching = liveByKey[key] ?? const <Channel>[];
    final existing =
        matching.where((channel) => channel.name == source.name).firstOrNull ??
        matching.where((channel) => _nameKey(channel) == name).firstOrNull ??
        matching.firstOrNull;
    if (existing != null) {
      final group = matches.putIfAbsent(
        existing.index,
        () => (current: existing, sources: []),
      );
      group.sources.add(source);
    } else if (additions.containsKey(key)) {
      duplicates.add(source);
    } else {
      additions[key] = source;
    }
  }

  final chosenMatches = [
    for (final group in matches.values)
      (
        current: group.current,
        source: group.sources.where((s) => s.name == group.current.name)
                .firstOrNull ??
            group.sources.first,
        sources: group.sources,
      ),
  ];
  // Histories are name-keyed. Reserve both the live names and the proposed
  // names so neither a rename nor an addition can collide with another PSK.
  final keysByName = <String, Set<String>>{};
  void reserveName(Channel channel) {
    (keysByName[_nameKey(channel)] ??= {}).add(channel.pskHex);
  }
  for (final channel in live) {
    reserveName(channel);
  }
  for (final match in chosenMatches) {
    reserveName(match.source);
  }
  for (final source in additions.values) {
    reserveName(source);
  }
  bool hasNameConflict(Channel source) {
    final name = _nameKey(source);
    return name.isNotEmpty && keysByName[name]!.length > 1;
  }

  for (final match in chosenMatches) {
    final current = match.current;
    final source = match.source;
    final BackupChannelAction action;
    if (current.name == source.name) {
      action = BackupChannelAction.alreadyPresent;
    } else if (unconfirmedSlots.contains(current.index)) {
      action = BackupChannelAction.unconfirmedSlot;
    } else if (hasNameConflict(source)) {
      action = BackupChannelAction.nameConflict;
    } else {
      action = BackupChannelAction.rename;
    }
    final target = switch (action) {
      BackupChannelAction.alreadyPresent => current,
      BackupChannelAction.rename => Channel(
        index: current.index,
        name: source.name,
        psk: current.psk,
        unreadCount: current.unreadCount,
      ),
      _ => null,
    };
    decisions.add((source: source, action: action, destination: target));
    decisions.addAll(
      match.sources.where((alias) => !identical(alias, source)).map(
        (alias) => (
          source: alias,
          action: target == null ? action : BackupChannelAction.duplicateInBackup,
          destination: target,
        ),
      ),
    );
  }

  final freeSlots = <int>{
    for (var index = 0; index < capacity; index++)
      if (!unconfirmedSlots.contains(index)) index,
  }..removeAll(live.map((channel) => channel.index));
  final displaced = <Channel>[];
  for (final source in additions.values) {
    if (hasNameConflict(source)) {
      decisions.add((
        source: source,
        action: BackupChannelAction.nameConflict,
        destination: null,
      ));
    } else if (freeSlots.remove(source.index)) {
      decisions.add(_addAt(source, source.index));
    } else {
      displaced.add(source);
    }
  }
  for (final source in displaced) {
    final slot = freeSlots.firstOrNull;
    if (slot == null) {
      decisions.add((
        source: source,
        action: BackupChannelAction.noFreeSlot,
        destination: null,
      ));
    } else {
      freeSlots.remove(slot);
      decisions.add(_addAt(source, slot));
    }
  }
  final byKey = {
    for (final decision in decisions) decision.source.pskHex: decision,
  };
  for (final source in duplicates) {
    final primary = byKey[source.pskHex]!;
    decisions.add((
      source: source,
      action: primary.action == BackupChannelAction.add
          ? BackupChannelAction.duplicateInBackup
          : primary.action,
      destination: primary.destination,
    ));
  }
  decisions.sort((a, b) => a.source.index.compareTo(b.source.index));
  return List.unmodifiable(decisions);
}

BackupChannelDecision _addAt(Channel source, int slot) => (
  source: source,
  action: BackupChannelAction.add,
  destination: Channel(index: slot, name: source.name, psk: source.psk),
);

String _nameKey(Channel channel) => channel.name.trim().toLowerCase();
