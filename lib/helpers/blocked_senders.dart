import '../models/channel_message.dart';
import '../storage/blocked_sender_store.dart';
import 'mcmp_app_codec.dart';

/// Channel senders the user has muted.
///
/// One table for the whole app, so the chat that hides a body, the map that
/// must ignore that body's pins and the connector that must not notify about
/// it all reach the same answer. A singleton rather than a provider: the
/// connector consults it while parsing a frame, far from any `BuildContext`.
///
/// The rule is deliberately narrow — it decides what is *shown and acted on*,
/// never what is received or stored. Blocked messages still arrive, still sit
/// in history, and come back in full the moment the block is lifted.
class BlockedSenders {
  BlockedSenders._();

  static final BlockedSenders instance = BlockedSenders._();

  final BlockedSenderStore _store = BlockedSenderStore();
  Map<String, BlockedSenderRule>? _rules;
  int _revision = 0;

  /// Bumped on every change.
  ///
  /// Caches keyed on message content — the map's marker signature — know
  /// nothing about this table, so they have to mix this in or a block leaves
  /// them showing the pins it was meant to remove.
  int get revision => _revision;

  /// Loaded lazily and kept in memory: [hides] is asked once per message per
  /// frame while the map builds its markers.
  Map<String, BlockedSenderRule> get rules => _rules ??= _store.load();

  /// The key that actually authenticated [message], or null.
  ///
  /// A key is an identity only when the signature checked out: a failed
  /// verification still reports the single candidate it tried, which is
  /// diagnostic information rather than the sender.
  static String? verifiedKeyOf(ChannelMessage message) =>
      message.mcmpSignatureStatus == McmpSignatureStatus.valid
      ? message.verifiedSenderKeyHex?.trim().toLowerCase()
      : null;

  /// The rule muting [message] in the channel named [channelName], or null.
  ///
  /// A rule carrying a key matches only messages that verified against it, so
  /// blocking a signed sender leaves anyone else using that name visible.
  BlockedSenderRule? ruleFor(ChannelMessage message, String channelName) {
    if (message.isOutgoing) return null;
    final rules = this.rules;
    if (rules.isEmpty) return null;
    final rule = rules[message.senderName.trim()];
    if (rule == null || !rule.coversChannel(channelName)) return null;
    if (rule.keyHex.isEmpty) return rule;
    return rule.keyHex == verifiedKeyOf(message) ? rule : null;
  }

  /// True when a rule mutes this sender right now, whatever the message
  /// itself remembers. Only the receive path asks this, to stamp
  /// [ChannelMessage.wasBlocked]; everything else asks [hides].
  bool isSenderBlocked(ChannelMessage message, String channelName) =>
      ruleFor(message, channelName) != null;

  /// True when [message] must be neither shown nor acted on.
  ///
  /// Either its sender is muted now, or it arrived while they were. The stored
  /// flag never expires: lifting a block must not resurrect a marker or a
  /// `del:` command from the muted period, and revealing the text by hand must
  /// not either.
  bool hides(ChannelMessage message, String channelName) =>
      message.wasBlocked || isSenderBlocked(message, channelName);

  /// Mutes the sender of [message] in every channel.
  ///
  /// A verified MCMP v3 message blocks that exact identity — the name plus the
  /// key that verified it. Anything else blocks the name alone, since an
  /// unsigned message proves nothing about who sent it.
  ///
  /// Blocking a name that already has a rule never narrows it. A name-only
  /// rule is already the widest there is, so a keyed block on top of it does
  /// nothing at all; narrowing is a deliberate act, done by deleting the rule
  /// and blocking again.
  Future<void> block(ChannelMessage message) async {
    final name = message.senderName.trim();
    if (name.isEmpty) return;
    final existing = rules[name];
    if (existing != null && existing.keyHex.isEmpty) return;
    final key = verifiedKeyOf(message) ?? '';
    if (existing != null && existing.keyHex == key) return;
    await _write({
      ...rules,
      // A second, different key under one name is more than a single-key rule
      // can tell apart, so the block widens to the bare name.
      name: BlockedSenderRule(
        keyHex: existing == null ? key : '',
        channels: existing?.channels ?? const [BlockedSenderRule.everyChannel],
      ),
    });
  }

  /// Mutes a name typed by hand, with no key and across every channel.
  ///
  /// That is the widest rule a name can carry, so it replaces a keyed one and
  /// does nothing when such a rule already exists.
  Future<void> blockName(String senderName) async {
    final name = senderName.trim();
    if (name.isEmpty) return;
    final existing = rules[name];
    if (existing != null &&
        existing.keyHex.isEmpty &&
        existing.channels.contains(BlockedSenderRule.everyChannel)) {
      return;
    }
    await _write({...rules, name: const BlockedSenderRule()});
  }

  Future<void> unblock(String senderName) async {
    final name = senderName.trim();
    if (!rules.containsKey(name)) return;
    await _write({...rules}..remove(name));
  }

  Future<void> _write(Map<String, BlockedSenderRule> updated) async {
    _rules = Map.unmodifiable(updated);
    _revision++;
    await _store.save(updated);
  }
}
