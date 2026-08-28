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
    required this.blockedAt,
    this.keyHex = '',
    this.channels = const [everyChannel],
    this.hideMessageWidgets = false,
  });

  final String keyHex;

  /// When the block was created. A stored message counts as muted when its
  /// `receivedAt` is at or after this moment — see
  /// `BlockedSenders.hidesStoredMessage`.
  ///
  /// Widening an existing rule keeps the original moment: re-blocking a name
  /// to drop its key must not move the boundary forward, or everything hidden
  /// under the keyed rule would surface again. Only a rule that did not exist
  /// before gets the current time.
  final DateTime blockedAt;

  /// Channel names this rule covers, or a single [everyChannel]. Blocking
  /// always writes the wildcard today; the list exists so a per-channel block
  /// can be added later without migrating stored rules. Note that names are
  /// matched as the caller spells them — the day a rule stops being a
  /// wildcard, callers have to agree on what an unnamed channel is called.
  final List<String> channels;

  /// Whether channel message rows covered by this rule are omitted entirely.
  final bool hideMessageWidgets;

  bool coversChannel(String channelName) {
    if (channels.contains(everyChannel)) return true;
    final wanted = normalizeChannel(channelName);
    return channels.any((c) => normalizeChannel(c) == wanted);
  }

  static String normalizeChannel(String name) => name.trim().toLowerCase();

  BlockedSenderRule copyWith({
    String? keyHex,
    List<String>? channels,
    DateTime? blockedAt,
    bool? hideMessageWidgets,
  }) => BlockedSenderRule(
    keyHex: keyHex ?? this.keyHex,
    channels: channels ?? this.channels,
    blockedAt: blockedAt ?? this.blockedAt,
    hideMessageWidgets: hideMessageWidgets ?? this.hideMessageWidgets,
  );

  /// Null for a rule written before blocks carried a moment — the caller
  /// stamps those once, rather than guessing a date here.
  static DateTime? blockedAtOf(Map<String, dynamic> json) {
    final millis = json['blockedAtMs'];
    return millis is int ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  factory BlockedSenderRule.fromJson(
    Map<String, dynamic> json, {
    required DateTime blockedAt,
  }) {
    final channels = (json['channels'] as List?)
        ?.map((c) => c.toString())
        .where((c) => c.isNotEmpty)
        .toList();
    return BlockedSenderRule(
      keyHex: (json['key'] as String? ?? '').trim().toLowerCase(),
      channels: (channels == null || channels.isEmpty)
          ? const [everyChannel]
          : List.unmodifiable(channels),
      blockedAt: blockedAt,
      hideMessageWidgets: json['hideMessageWidgets'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': keyHex,
    'channels': channels,
    'blockedAtMs': blockedAt.millisecondsSinceEpoch,
    'hideMessageWidgets': hideMessageWidgets,
  };
}

/// Muted channel senders, kept as one JSON blob for the whole app.
///
/// Deliberately not scoped by node public key, unlike most stores here: a
/// sender worth muting is worth muting from every radio this phone connects
/// to, and channels are matched by name across nodes anyway.
class BlockedSenderStore {
  static const String _key = 'blocked_channel_senders';

  /// Reads the table, stamping any rule written before blocks carried a
  /// moment with [migratedAt].
  ///
  /// That is the load time rather than the epoch on purpose: an epoch would
  /// make the date half of the check reach back over the whole conversation
  /// and hide everything that sender ever wrote, which is exactly the
  /// behaviour blocking was built not to have. Stamping "now" leaves those
  /// rules acting as they always did — through the `wasBlocked` flag alone —
  /// while everything from here on gets the boundary too. [migrated] reports
  /// whether anything was stamped, so the caller can write the table back once
  /// and stop re-stamping on every launch.
  ({Map<String, BlockedSenderRule> rules, bool migrated}) load({
    required DateTime migratedAt,
  }) {
    final raw = PrefsManager.instance.getString(_key);
    if (raw == null || raw.isEmpty) return (rules: const {}, migrated: false);
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      var migrated = false;
      final rules = <String, BlockedSenderRule>{};
      for (final entry in decoded.entries) {
        final json = entry.value as Map<String, dynamic>;
        final stored = BlockedSenderRule.blockedAtOf(json);
        if (stored == null) migrated = true;
        rules[entry.key] = BlockedSenderRule.fromJson(
          json,
          blockedAt: stored ?? migratedAt,
        );
      }
      return (rules: rules, migrated: migrated);
    } catch (e) {
      appLogger.warn('Failed to read blocked senders: $e');
      return (rules: const {}, migrated: false);
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
