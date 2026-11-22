import 'dart:convert';

import '../models/channel_message.dart';

/// Display-only denylist; the empty region identifies explicitly unscoped posts.
abstract final class ChannelRegionFilter {
  static const unknown = '!unknown';
  static String normalize(String value) {
    final region = value.trim();
    if (region == '!unscoped') return '';
    return region.startsWith('#') ? region.substring(1) : region;
  }

  static Set<String> normalized(Iterable<String> regions) =>
      Set.unmodifiable(regions.map(normalize));

  static String encode(Iterable<String> regions) {
    final values = normalized(regions).toList()..sort();
    return jsonEncode(values);
  }

  static String? canonical(Object? raw) {
    try {
      final value = raw is String ? jsonDecode(raw) : raw;
      if (value is! List || value.any((item) => item is! String)) return null;
      return encode(value.cast<String>());
    } on FormatException {
      return null;
    }
  }

  static Set<String> decode(String? raw) {
    final encoded = canonical(raw);
    if (encoded == null) return const {};
    return normalized((jsonDecode(encoded) as List).cast<String>());
  }

  static List<String> choices(Iterable<String> known, Set<String> hidden) {
    final regions = {...known.map(normalize), ...hidden}
      ..remove('')
      ..remove(unknown);
    return ['', unknown, ...(regions.toList()..sort())];
  }

  static bool allows(ChannelMessage message, Set<String> hidden) {
    if (hidden.isEmpty) return true;
    final region = normalize(message.packetRegion ?? '');
    final key = message.packetRegionNotMatched ||
        (region.isEmpty && !message.packetRegionInfoAvailable)
        ? unknown : region;
    return !hidden.contains(key);
  }
}

/// A stable list identity keeps the transcript Selector idle on unrelated updates.
class ChannelRegionFilterTimeline {
  List<ChannelMessage>? _source;
  Set<String> _hidden = const {};
  List<ChannelMessage> _result = const [];

  List<ChannelMessage> resolve(List<ChannelMessage> messages, Set<String> hidden) {
    if (identical(messages, _source) && _hidden.length == hidden.length &&
        _hidden.containsAll(hidden)) {
      return _result;
    }
    _source = messages;
    _hidden = Set.unmodifiable(hidden);
    return _result = hidden.isEmpty ? messages : List.unmodifiable(
      messages.where((message) => ChannelRegionFilter.allows(message, hidden)),
    );
  }
}
