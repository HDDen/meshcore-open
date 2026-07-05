import '../models/channel.dart';

class ChannelIdentityMatcher {
  const ChannelIdentityMatcher._();

  static Channel? findMatchingChannel(
    List<Channel> channels, {
    required String name,
    String? pskHex,
  }) {
    final normalizedName = _nameKey(name);
    final normalizedPsk = _pskKey(pskHex);
    if (normalizedName.isEmpty && normalizedPsk == null) return null;

    if (normalizedPsk != null) {
      final exact = _uniqueMap(
        channels,
        (channel) => '${_nameKey(channel.name)}|${_pskKey(channel.pskHex)}',
      )['$normalizedName|$normalizedPsk'];
      if (exact != null) return exact;

      final byPsk = _uniqueMap(channels, (channel) => _pskKey(channel.pskHex));
      final pskMatch = byPsk[normalizedPsk];
      if (pskMatch != null) return pskMatch;
    }

    final byName = _uniqueMap(channels, (channel) => _nameKey(channel.name));
    return byName[normalizedName];
  }

  static int? findMatchingChannelIndex(
    List<Channel> channels, {
    required String name,
    String? pskHex,
  }) {
    return findMatchingChannel(channels, name: name, pskHex: pskHex)?.index;
  }

  static Map<String, Channel> _uniqueMap(
    List<Channel> channels,
    String? Function(Channel channel) keyOf,
  ) {
    final result = <String, Channel>{};
    final duplicates = <String>{};
    for (final channel in channels) {
      if (channel.isEmpty) continue;
      final key = keyOf(channel);
      if (key == null || key.isEmpty) continue;
      if (duplicates.contains(key)) continue;
      if (result.containsKey(key)) {
        result.remove(key);
        duplicates.add(key);
      } else {
        result[key] = channel;
      }
    }
    return result;
  }

  static String _nameKey(String name) => name.trim().toLowerCase();

  static String? _pskKey(String? pskHex) {
    final value = pskHex?.trim().toLowerCase();
    return value == null || value.isEmpty ? null : value;
  }
}
