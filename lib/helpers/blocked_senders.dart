import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/channel_message.dart';
import '../models/message.dart';
import '../storage/blocked_sender_store.dart';
import 'mcmp_app_codec.dart';

/// Channel senders the user has muted.
///
/// One table for the whole app, and a singleton rather than a provider: its
/// main caller is the connector, which consults it while parsing a frame, far
/// from any `BuildContext`.
///
/// A rule is asked two questions, and the difference between them is only
/// which clock the moment of blocking is compared against.
///
/// [isSenderBlocked] — "is this sender muted right now?" — is the receive-time
/// question. A rule that exists was created in the past, so a message arriving
/// now is always after it; comparing our own clock with our own clock would
/// add nothing and would misfire if the device clock stepped backwards. The
/// answer is stamped onto the message as [ChannelMessage.wasBlocked].
///
/// [hidesStoredMessage] — "should this stored message be hidden?" — is the
/// display-time question, and that one does compare dates, because it is asked
/// about messages the receive path never stamped: merged in from another
/// node's shared history, or stored by a path that did not consult this table.
/// A message counts as muted when EITHER of its dates is at or after the
/// moment of blocking. Only the packet timestamp can be forged, and both
/// directions of forgery are harmless: an old date still loses to a real
/// [ChannelMessage.receivedAt], and a future one can only hide the forger's
/// own messages.
///
/// Neither question ever drops a message on receipt or removes one from
/// history, and neither reaches messages that predate the block.
class BlockedSenders extends ChangeNotifier {
  BlockedSenders._();

  static final BlockedSenders instance = BlockedSenders._();

  /// Bumped on every change to the table.
  ///
  /// A listener is enough to trigger a rebuild, but not to invalidate a cache
  /// keyed on a value — the map holds its pins against a signature and would
  /// serve stale ones through a redraw. This is that value.
  int get revision => _revision;
  int _revision = 0;

  final BlockedSenderStore _store = BlockedSenderStore();
  Map<String, BlockedSenderRule>? _rules;

  /// Loaded lazily and kept in memory: the receive path asks for it once per
  /// incoming channel message.
  ///
  /// Rules written before blocks carried a moment are stamped with the load
  /// time and written straight back, so the stamp is decided once rather than
  /// drifting with every launch. That write is the one side effect this getter
  /// has, and it happens at most once in the table's life.
  Map<String, BlockedSenderRule> get rules {
    final cached = _rules;
    if (cached != null) return cached;
    final loaded = _store.load(migratedAt: DateTime.now());
    _rules = Map.unmodifiable(loaded.rules);
    if (loaded.migrated) unawaited(_store.save(loaded.rules));
    return _rules!;
  }

  /// The author of a room post, as the table keys them: uppercase hex of the
  /// 4-byte prefix. Null for anything that carries none, which is every
  /// one-to-one message.
  ///
  /// Room authors share the one table with channel senders, keyed by this
  /// prefix where a channel sender is keyed by its name. The two key spaces
  /// could in principle collide — a channel sender literally named `AB12CD34`
  /// — and if they ever did, blocking one would block the other. That is the
  /// whole cost of not having a second table, and it is worth paying.
  static String? roomAuthorIdOf(Message message) {
    final prefix = message.fourByteRoomContactKey;
    if (prefix.isEmpty) return null;
    return prefix
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  /// [verifiedKeyOf] for a room post.
  static String? verifiedRoomKeyOf(Message message) =>
      message.mcmpSignatureStatus == McmpSignatureStatus.valid
      ? message.verifiedSenderKeyHex?.trim().toLowerCase()
      : null;

  /// The rule muting the author of [message], or null.
  ///
  /// Rooms are identified by the prefix rather than by a name, so there is no
  /// name to squat: the room server writes it, and a participant cannot choose
  /// somebody else's. A key on the rule works as it does for channels — an
  /// exemption, letting through only a post that provably verified to a
  /// different key.
  BlockedSenderRule? roomRuleFor(Message message) {
    if (message.isOutgoing || message.isCli) return null;
    final rules = this.rules;
    if (rules.isEmpty) return null;
    final id = roomAuthorIdOf(message);
    if (id == null) return null;
    final rule = rules[id];
    if (rule == null || rule.keyHex.isEmpty) return rule;
    final key = verifiedRoomKeyOf(message);
    if (key == null) return rule;
    return key == rule.keyHex ? rule : null;
  }

  /// True when a rule mutes this room author right now.
  ///
  /// The answer is stamped onto the message as [Message.wasBlocked], and that
  /// flag is what every display site reads.
  bool isRoomAuthorBlocked(Message message) => roomRuleFor(message) != null;

  /// Mutes the author of [message] across every room.
  Future<void> blockRoomAuthor(Message message) async {
    final id = roomAuthorIdOf(message);
    if (id == null) return;
    final existing = rules[id];
    final key = verifiedRoomKeyOf(message) ?? '';
    final keyHex = existing == null
        ? key
        : (existing.keyHex == key ? key : '');
    // Use the room timeline position so the history walk and the block anchor
    // share the same local ordering clock.
    final blockedAt = _blockedAtFor(existing?.blockedAt, message.receivedAt);
    if (existing != null &&
        existing.keyHex == keyHex &&
        !existing.blockedAt.isAfter(blockedAt)) {
      return;
    }
    await _write({
      ...rules,
      id: BlockedSenderRule(
        keyHex: keyHex,
        channels: existing?.channels ?? const [BlockedSenderRule.everyChannel],
        blockedAt: blockedAt,
      ),
    });
  }

  Future<void> unblockRoomAuthor(String authorId) async {
    if (!rules.containsKey(authorId)) return;
    await _write({...rules}..remove(authorId));
  }

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
  /// The key on a rule is an **exemption, not a requirement**: the rule mutes
  /// the name, and the only message it lets through is one that provably
  /// verified to a *different* key. That is the same reasoning blocking itself
  /// follows — an unsigned message proves nothing about who sent it — applied
  /// to the arriving side. Requiring the key instead meant the muted sender
  /// walked straight out of the rule by not signing, and, worse, by being
  /// deleted from contacts: with nobody left bearing that name a signature
  /// verifies to `unverifiable`, which reports no key at all. Muting somebody
  /// and then removing them from contacts is the natural pair of actions, and
  /// it used to switch the block off.
  BlockedSenderRule? ruleFor(ChannelMessage message, String channelName) {
    if (message.isOutgoing) return null;
    final rules = this.rules;
    if (rules.isEmpty) return null;
    final rule = rules[message.senderName.trim()];
    if (rule == null || !rule.coversChannel(channelName)) return null;
    if (rule.keyHex.isEmpty) return rule;
    final key = verifiedKeyOf(message);
    // No proven identity: the name is all anyone has, and the name is muted.
    if (key == null) return rule;
    return key == rule.keyHex ? rule : null;
  }

  /// True when a rule mutes this sender right now.
  ///
  /// Asked by the receive path, which stamps the answer onto the message, and
  /// by the block/unblock menu entry, which needs to know which half it is
  /// offering. What draws a message asks [hidesStoredMessage] instead, which
  /// adds the date boundary this question deliberately has no use for.
  bool isSenderBlocked(ChannelMessage message, String channelName) =>
      ruleFor(message, channelName) != null;

  /// True when a stored message falls inside its sender's block.
  ///
  /// The identity half is [ruleFor]; on top of it, the message must have
  /// reached us at or after [BlockedSenderRule.blockedAt].
  ///
  /// [ChannelMessage.receivedAt] and nothing else: the moment of blocking is
  /// known only to us, while the packet's own timestamp is chosen by the
  /// sender, so comparing the two would measure the wrong thing even before
  /// anyone forged anything. The one case where `receivedAt` is not our clock
  /// — the post-connect backlog drain writes the sender's send time into it —
  /// needs no date at all: those messages still pass through the receive path,
  /// which stamps [ChannelMessage.wasBlocked] without consulting any clock.
  ///
  /// Outgoing messages never match — [ruleFor] refuses them — so adopting our
  /// own name and getting us to block it cannot hide anything we wrote.
  bool hidesStoredMessage(ChannelMessage message, String channelName) {
    final rule = ruleFor(message, channelName);
    if (rule == null) return false;
    return !message.receivedAt.isBefore(rule.blockedAt);
  }

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
    final key = verifiedKeyOf(message) ?? '';
    // A second, different key under one name is more than a single-key rule
    // can tell apart, so the block widens to the bare name — and a name-only
    // rule is already the widest there is. Neither ever narrows here.
    final keyHex = existing == null
        ? key
        : (existing.keyHex == key ? key : '');
    final blockedAt = _blockedAtFor(existing?.blockedAt, message.receivedAt);
    // Blocking the same identity again is not always a no-op any more: it
    // still counts when the message points further back than the rule reaches.
    if (existing != null &&
        existing.keyHex == keyHex &&
        !existing.blockedAt.isAfter(blockedAt)) {
      return;
    }
    await _write({
      ...rules,
      name: BlockedSenderRule(
        keyHex: keyHex,
        channels: existing?.channels ?? const [BlockedSenderRule.everyChannel],
        blockedAt: blockedAt,
      ),
    });
  }

  /// Where a block created from a message starts.
  ///
  /// The message the user pointed at, not the tap: by the time somebody
  /// long-presses a post, that sender has usually put several more on the
  /// screen above it, and leaving those visible was the whole complaint. So
  /// the boundary is that message's own arrival, and everything the sender has
  /// posted since — here and in history merged from other nodes — falls inside
  /// the block. What sits above it in the conversation stays readable.
  ///
  /// Clamped to now, because `receivedAt` is our own clock in every case but
  /// one: the post-connect backlog drain writes the sender's send time into
  /// it, and a forged future date there would otherwise push the boundary out
  /// of reach.
  static DateTime _anchorAt(DateTime? receivedAt) {
    final now = DateTime.now();
    if (receivedAt == null || receivedAt.isAfter(now)) return now;
    return receivedAt;
  }

  /// The moment a rule starts at, given the message it is being created from
  /// and whatever the rule already had.
  ///
  /// The earlier of the two, always. Blocking again from an older message
  /// reaches further back and strengthens the rule; blocking from a newer one
  /// must not move the boundary forward, or everything already hidden between
  /// the two blocks would surface again. So a rule's moment only ever travels
  /// in one direction, and only a fresh rule starts where it was made.
  static DateTime _blockedAtFor(DateTime? existing, DateTime? receivedAt) {
    final anchor = _anchorAt(receivedAt);
    if (existing == null) return anchor;
    return existing.isBefore(anchor) ? existing : anchor;
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
    // No message to point at, so there is nothing that could reach further
    // back: an existing block keeps its moment, a new one starts now.
    await _write({
      ...rules,
      name: BlockedSenderRule(
        blockedAt: _blockedAtFor(existing?.blockedAt, null),
      ),
    });
  }

  Future<void> unblock(String senderName) async {
    final name = senderName.trim();
    if (!rules.containsKey(name)) return;
    await _write({...rules}..remove(name));
  }

  Future<void> _write(Map<String, BlockedSenderRule> updated) async {
    _rules = Map.unmodifiable(updated);
    _revision++;
    // Before the await: what draws a message now asks this table directly, so
    // the redraw must not wait on a preferences write.
    notifyListeners();
    await _store.save(updated);
  }
}
