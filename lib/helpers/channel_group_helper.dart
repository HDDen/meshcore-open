import 'dart:math';

import '../models/channel.dart';
import '../models/channel_group.dart';

final RegExp _legacyPeerGroupKeyPattern = RegExp(
  r'^(?:room|contact):([0-9a-f]{64})$',
  caseSensitive: false,
);

String normalizeChannelGroupItemKey(String value) {
  final trimmed = value.trim();
  final match = _legacyPeerGroupKeyPattern.firstMatch(trimmed);
  if (match == null) return trimmed;
  return 'peer:${match.group(1)!.toLowerCase()}';
}

List<ChannelGroup> normalizeChannelGroupsForPeers(List<ChannelGroup> groups) {
  final claimedItemKeys = <String>{};
  final normalizedGroups = <ChannelGroup>[];
  for (final group in orderedChannelGroups(groups)) {
    final normalizedNames = <String>[];
    for (final rawName in group.channelNames) {
      final normalizedName = normalizeChannelGroupItemKey(rawName);
      if (normalizedName.isEmpty) continue;
      if (claimedItemKeys.add(normalizedName.toLowerCase())) {
        normalizedNames.add(normalizedName);
      }
    }
    normalizedGroups.add(group.copyWith(channelNames: normalizedNames));
  }
  return normalizedGroups;
}

List<String> normalizeChannelScreenOrderForPeers(List<String> order) {
  final seenKeys = <String>{};
  final normalizedOrder = <String>[];
  for (final rawKey in order) {
    final normalizedKey = normalizeChannelGroupItemKey(rawKey);
    if (normalizedKey.isEmpty) continue;
    if (seenKeys.add(normalizedKey.toLowerCase())) {
      normalizedOrder.add(normalizedKey);
    }
  }
  return normalizedOrder;
}

class ChannelGroupListEntry {
  const ChannelGroupListEntry._({this.group, this.channel});

  const ChannelGroupListEntry.group(ChannelGroup group) : this._(group: group);

  const ChannelGroupListEntry.channel(Channel channel)
    : this._(channel: channel);

  final ChannelGroup? group;
  final Channel? channel;
}

List<ChannelGroupListEntry> buildManualChannelEntries(
  List<Channel> orderedChannels,
  List<ChannelGroup> groups,
) {
  final groupByChannel = channelGroupByChannelName(groups);
  final entries = <ChannelGroupListEntry>[];
  for (final channel in orderedChannels) {
    final group = groupByChannel[_channelNameKey(channelNameForGroup(channel))];
    if (group == null) {
      entries.add(ChannelGroupListEntry.channel(channel));
    }
  }

  for (final group in orderedChannelGroups(groups)) {
    final insertIndex = max(0, min(group.sortOrder, entries.length));
    entries.insert(insertIndex, ChannelGroupListEntry.group(group));
  }
  return entries;
}

List<ChannelGroup> channelGroupsFromManualEntries(
  List<ChannelGroupListEntry> entries,
) {
  return [
    for (var index = 0; index < entries.length; index++)
      if (entries[index].group != null)
        // Empty groups have no channel anchor, so keep their manual
        // top-level position explicitly.
        entries[index].group!.copyWith(sortOrder: index),
  ];
}

List<int> manualChannelOrderFromEntriesWithChannels(
  List<ChannelGroupListEntry> entries,
  List<Channel> channels,
) {
  final byName = _channelByGroupName(channels);
  final indexes = <int>[];
  for (final entry in entries) {
    final group = entry.group;
    if (group != null) {
      for (final name in group.channelNames) {
        final channel = byName[_channelNameKey(name)];
        if (channel != null) indexes.add(channel.index);
      }
      continue;
    }

    final channel = entry.channel;
    if (channel != null) indexes.add(channel.index);
  }
  return indexes;
}

List<ChannelGroup> orderedChannelGroups(List<ChannelGroup> groups) {
  final indexedGroups = [
    for (var index = 0; index < groups.length; index++)
      MapEntry(
        index,
        groups[index].sortOrder < 0
            ? groups[index].copyWith(sortOrder: index)
            : groups[index],
      ),
  ];
  indexedGroups.sort((a, b) {
    final sortCompare = a.value.sortOrder.compareTo(b.value.sortOrder);
    if (sortCompare != 0) return sortCompare;
    return a.key.compareTo(b.key);
  });
  return [for (final entry in indexedGroups) entry.value];
}

Map<String, ChannelGroup> channelGroupByChannelName(List<ChannelGroup> groups) {
  return {
    for (final group in groups)
      for (final name in group.channelNames) _channelNameKey(name): group,
  };
}

List<Channel> channelsForGroup(
  ChannelGroup group,
  List<Channel> filteredChannels,
) {
  final byName = _channelByGroupName(filteredChannels);
  return [
    for (final name in group.channelNames)
      if (byName[_channelNameKey(name)] != null) byName[_channelNameKey(name)]!,
  ];
}

List<String> reorderedChannelNamesInGroup(
  ChannelGroup group,
  int oldIndex,
  int newIndex,
) {
  final reorderedNames = List<String>.from(group.channelNames);
  if (oldIndex < 0 || oldIndex >= reorderedNames.length) {
    return reorderedNames;
  }
  final channelName = reorderedNames.removeAt(oldIndex);
  final insertIndex = max(0, min(newIndex, reorderedNames.length));
  reorderedNames.insert(insertIndex, channelName);
  return reorderedNames;
}

List<int> manualChannelOrderForGroups(
  List<Channel> orderedChannels,
  List<ChannelGroup> groups,
) {
  final groupByChannel = channelGroupByChannelName(groups);
  final emittedGroups = <String>{};
  final orderedIndexes = <int>[];
  for (final channel in orderedChannels) {
    final group = groupByChannel[_channelNameKey(channelNameForGroup(channel))];
    if (group == null) {
      orderedIndexes.add(channel.index);
    } else if (emittedGroups.add(group.name)) {
      orderedIndexes.addAll(
        channelsForGroup(
          group,
          orderedChannels,
        ).map((channel) => channel.index),
      );
    }
  }
  return orderedIndexes;
}

List<String> selectedChannelNamesForGroupEdit(
  ChannelGroup group,
  List<Channel> editableChannels,
  Set<String> selectedNames,
) {
  final orderedNames = <String>[
    // Preserve the current in-group order when editing membership/name.
    for (final name in group.channelNames)
      if (selectedNames.contains(_channelNameKey(name))) name,
  ];
  final existingNames = orderedNames.map(_channelNameKey).toSet();
  for (final channel in editableChannels) {
    final name = channelNameForGroup(channel);
    final key = _channelNameKey(name);
    if (selectedNames.contains(key) && !existingNames.contains(key)) {
      orderedNames.add(name);
    }
  }
  return orderedNames;
}

List<String> selectedChannelNamesForGroupEditSorted(
  List<Channel> editableChannels,
  Set<String> selectedNames,
  Comparator<Channel> compareChannels,
) {
  final selectedChannels = [
    for (final channel in editableChannels)
      if (selectedNames.contains(_channelNameKey(channelNameForGroup(channel))))
        channel,
  ]..sort(compareChannels);
  return [for (final channel in selectedChannels) channelNameForGroup(channel)];
}

String channelNameForGroup(Channel channel) => channel.name.trim();

String _channelNameKey(String name) => name.trim().toLowerCase();

Map<String, Channel> _channelByGroupName(List<Channel> channels) {
  return {
    for (final channel in channels)
      if (channelNameForGroup(channel).isNotEmpty)
        _channelNameKey(channelNameForGroup(channel)): channel,
  };
}
