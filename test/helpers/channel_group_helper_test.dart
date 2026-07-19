import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_group_helper.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_group.dart';

void main() {
  Channel channel(int index, String name) {
    return Channel(index: index, name: name, psk: Uint8List(16));
  }

  int compareByName(Channel a, Channel b) {
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  group('ChannelGroupHelper', () {
    test('keeps empty groups at their manual top-level position', () {
      final entries = buildManualChannelEntries(
        [channel(1, 'Alpha'), channel(2, 'Beta')],
        const [ChannelGroup(name: 'Empty', channelNames: [], sortOrder: 1)],
      );

      expect(entries[0].channel?.index, 1);
      expect(entries[1].group?.name, 'Empty');
      expect(entries[2].channel?.index, 2);
    });

    test('updates group sort order from manually reordered entries', () {
      final first = ChannelGroup(name: 'First', channelNames: ['Alpha']);
      final second = ChannelGroup(name: 'Second', channelNames: ['Beta']);

      final groups = channelGroupsFromManualEntries([
        ChannelGroupListEntry.group(second),
        ChannelGroupListEntry.group(first),
      ]);

      expect(groups[0].name, 'Second');
      expect(groups[0].sortOrder, 0);
      expect(groups[1].name, 'First');
      expect(groups[1].sortOrder, 1);
    });

    test('places non-empty group by manual sort order', () {
      final entries = buildManualChannelEntries(
        [channel(1, 'Alpha'), channel(2, 'Public')],
        const [
          ChannelGroup(name: 'Group', channelNames: ['Alpha'], sortOrder: 1),
        ],
      );

      expect(entries[0].channel?.name, 'Public');
      expect(entries[1].group?.name, 'Group');
    });

    test('builds device channel order from groups and standalone channels', () {
      final public = channel(2, 'Public');
      final alpha = channel(1, 'Alpha');
      final entries = [
        ChannelGroupListEntry.channel(public),
        const ChannelGroupListEntry.group(
          ChannelGroup(name: 'Group', channelNames: ['Alpha']),
        ),
      ];

      final order = manualChannelOrderFromEntriesWithChannels(entries, [
        alpha,
        public,
      ]);

      expect(order, [2, 1]);
    });

    test(
      'preserves selected in-group order when manual ordering is enabled',
      () {
        final group = ChannelGroup(
          name: 'Group',
          channelNames: ['Alpha', 'Beta', 'Gamma'],
        );
        final editableChannels = [
          channel(1, 'Beta'),
          channel(2, 'Gamma'),
          channel(3, 'Alpha'),
        ];

        final selected = selectedChannelNamesForGroupEdit(
          group,
          editableChannels,
          {'alpha', 'beta', 'gamma'},
        );

        expect(selected, ['Alpha', 'Beta', 'Gamma']);
      },
    );

    test(
      'sorts selected channels by name when manual ordering is disabled',
      () {
        final selected = selectedChannelNamesForGroupEditSorted(
          [channel(1, 'Beta'), channel(2, 'Gamma'), channel(3, 'Alpha')],
          {'alpha', 'beta', 'gamma'},
          compareByName,
        );

        expect(selected, ['Alpha', 'Beta', 'Gamma']);
      },
    );

    test('reorders channels using the adjusted onReorderItem index', () {
      final group = ChannelGroup(
        name: 'Group',
        channelNames: ['Alpha', 'Beta', 'Gamma'],
      );

      final reordered = reorderedChannelNamesInGroup(group, 0, 2);

      expect(reordered, ['Beta', 'Gamma', 'Alpha']);
    });

    test('migrates legacy room and contact keys to one peer identity', () {
      final publicKey = List.filled(32, 'ab').join();
      final groups = normalizeChannelGroupsForPeers([
        ChannelGroup(name: 'First', channelNames: ['room:$publicKey', 'Alpha']),
        ChannelGroup(
          name: 'Second',
          channelNames: ['contact:${publicKey.toUpperCase()}', 'Beta'],
        ),
      ]);

      expect(groups[0].channelNames, ['peer:$publicKey', 'Alpha']);
      expect(groups[1].channelNames, ['Beta']);
    });

    test('migrates and deduplicates persisted manual screen order', () {
      final publicKey = List.filled(32, 'cd').join();

      final order = normalizeChannelScreenOrderForPeers([
        'room:$publicKey',
        'contact:${publicKey.toUpperCase()}',
        'channel:2',
        'channel:2',
      ]);

      expect(order, ['peer:$publicKey', 'channel:2']);
    });
  });
}
