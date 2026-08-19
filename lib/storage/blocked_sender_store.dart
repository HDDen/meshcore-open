import 'dart:convert';

import '../utils/app_logger.dart';
import 'prefs_manager.dart';

/// One muted channel sender, stored under the sender's name.
///
/// [keyHex] pins the rule to a single identity and is only ever set from a
/// message whose MCMP v3 signature verified; empty means the name is blocked
/// whoever sends under it.
class BlockedSenderRule {
  /// The [channels] entry standing for "every channel".
  static const String everyChannel = '*';

  const BlockedSenderRule({
    this.keyHex = '',
    this.channels = const [everyChannel],
  });

  final String keyHex;

  /// Channel names this rule covers, or a single [everyChannel]. Blocking
  /// always writes the wildcard today; the list exists so a per-channel block
  /// can be added later without migrating stored rules. Note that names are
  /// matched as the caller spells them — the day a rule stops being a
  /// wildcard, callers have to agree on what an unnamed channel is called.
  final List<String> channels;

  bool coversChannel(String channelName) {
    if (channels.contains(everyChannel)) return true;
    final wanted = normalizeChannel(channelName);
    return channels.any((c) => normalizeChannel(c) == wanted);
  }

  static String normalizeChannel(String name) => name.trim().toLowerCase();

  factory BlockedSenderRule.fromJson(Map<String, dynamic> json) {
    final channels = (json['channels'] as List?)
        ?.map((c) => c.toString())
        .where((c) => c.isNotEmpty)
        .toList();
    return BlockedSenderRule(
      keyHex: (json['key'] as String? ?? '').trim().toLowerCase(),
      channels: (channels == null || channels.isEmpty)
          ? const [everyChannel]
          : List.unmodifiable(channels),
    );
  }

  Map<String, dynamic> toJson() => {'key': keyHex, 'channels': channels};
}

/// Muted channel senders, kept as one JSON blob for the whole app.
///
/// Deliberately not scoped by node public key, unlike most stores here: a
/// sender worth muting is worth muting from every radio this phone connects
/// to, and channels are matched by name across nodes anyway.
class BlockedSenderStore {
  static const String _key = 'blocked_channel_senders';

  Map<String, BlockedSenderRule> load() {
    final raw = PrefsManager.instance.getString(_key);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          entry.key: BlockedSenderRule.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      };
    } catch (e) {
      appLogger.warn('Failed to read blocked senders: $e');
      return const {};
    }
  }

  Future<void> save(Map<String, BlockedSenderRule> rules) async {
    if (rules.isEmpty) {
      await PrefsManager.instance.remove(_key);
      return;
    }
    final persisted = <String, dynamic>{
      for (final entry in rules.entries) entry.key: entry.value.toJson(),
    };
    await PrefsManager.instance.setString(_key, jsonEncode(persisted));
  }
}
