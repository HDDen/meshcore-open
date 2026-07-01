import 'dart:convert';

import '../models/channel.dart';

mixin ChannelNameKeyedStore {
  final Map<int, String> _channelNamesByIndex = {};
  bool _allowsLegacyIndexMigration = true;

  bool get allowsLegacyIndexMigration => _allowsLegacyIndexMigration;

  void beginLegacyIndexMigration() {
    _allowsLegacyIndexMigration = true;
  }

  void finishLegacyIndexMigration() {
    _allowsLegacyIndexMigration = false;
  }

  void replaceChannels(Iterable<Channel> channels) {
    _channelNamesByIndex
      ..clear()
      ..addEntries(
        channels
            .where(
              (channel) => !channel.isEmpty && channel.name.trim().isNotEmpty,
            )
            .map((channel) => MapEntry(channel.index, channel.name.trim())),
      );
  }

  void registerChannel(Channel channel) {
    if (channel.isEmpty || channel.name.trim().isEmpty) {
      _channelNamesByIndex.remove(channel.index);
      return;
    }
    _channelNamesByIndex[channel.index] = channel.name.trim();
  }

  String? channelNameForIndex(int channelIndex) {
    return _channelNamesByIndex[channelIndex];
  }

  String? channelStorageKey(String keyPrefix, int channelIndex) {
    final channelName = channelNameForIndex(channelIndex);
    if (channelName == null || channelName.isEmpty) return null;
    final encoded = base64Url
        .encode(utf8.encode(channelName))
        .replaceAll('=', '');
    return '${keyPrefix}name_$encoded';
  }
}
