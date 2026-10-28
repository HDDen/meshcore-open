import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_group_helper.dart';
import 'package:meshcore_open/helpers/companion_cli_group_members.dart';
import 'package:meshcore_open/helpers/companion_cli_protocol.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_group.dart';

void main() {
  test('membership edit preserves position, avoids duplicates and can remove CLI', () {
    final previous = ['Alpha', companionCliOrderKey, 'Beta'];
    final saved = withCompanionCliGroupMember(
      ['Alpha', 'Beta', companionCliOrderKey], selected: true,
      previousOrder: previous,
    );
    expect(saved, previous);
    expect(withCompanionCliGroupMember(saved, selected: false), ['Alpha', 'Beta']);
    expect(withCompanionCliGroupMember(['Beta'], selected: true),
      [companionCliOrderKey, 'Beta']);
  });

  test('group JSON and normalization keep one service owner without a node channel', () {
    final original = ChannelGroup(name: 'Tools',
      channelNames: ['Alpha', companionCliOrderKey], allowOrderingInGroup: true);
    final decoded = ChannelGroup.fromJson(original.toJson());
    expect(decoded.channelNames, original.channelNames);
    final groups = normalizeChannelGroupsForPeers([
      decoded,
      const ChannelGroup(name: 'Other', channelNames: [companionCliOrderKey]),
    ]);
    expect(hasCompanionCliGroupMember(groups.first.channelNames), isTrue);
    expect(hasCompanionCliGroupMember(groups.last.channelNames), isFalse);
    final channels = [Channel(index: 7, name: 'Alpha', psk: Uint8List(16))];
    expect(manualChannelOrderForGroups(channels, groups), [7]);
    expect(channelsForGroup(decoded, channels), channels);
  });
}
