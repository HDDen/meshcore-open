import '../models/channel_message.dart';
import '../storage/blocked_sender_store.dart';
import 'mcmp_app_codec.dart';

/// Channel senders the user has muted.
///
/// One table for the whole app, and a singleton rather than a provider: its
/// main caller is the connector, which consults it while parsing a frame, far
/// from any `BuildContext`.
///
/// A rule is asked exactly one question, and only on the receive path: is this
/// sender muted right now? The answer is stamped onto the message as
/// [ChannelMessage.wasBlocked] and that flag alone decides what is shown and
/// acted on afterwards. So a block reaches forward only — what already sits in
/// history is left alone, and what arrived during a block stays hidden after
/// it is lifted. Nothing is ever dropped on receipt or removed from history.
class BlockedSenders {
  BlockedSenders._();

  static final BlockedSenders instance = BlockedSenders._();

  final BlockedSenderStore _store = BlockedSenderStore();
  Map<String, BlockedSenderRule>? _rules;

  /// Loaded lazily and kept in memory: the receive path asks for it once per
  /// incoming channel message.
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

  /// True when a rule mutes this sender right now.
  ///
  /// Asked by the receive path, which stamps the answer onto the message, and
  /// by the block/unblock menu entry, which needs to know which half it is
  /// offering. Nothing that draws a message asks it — that reads
  /// [ChannelMessage.wasBlocked].
  bool isSenderBlocked(ChannelMessage message, String channelName) =>
      ruleFor(message, channelName) != null;

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
    await _store.save(updated);
  }
}
