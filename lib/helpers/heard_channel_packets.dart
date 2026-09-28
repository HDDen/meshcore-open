import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// What became of a channel packet the app has already processed, so a later
/// copy of it can be folded in without processing the packet again.
sealed class HeardChannelPacket {
  const HeardChannelPacket();
}

/// The packet was stored as the message with [messageId], or merged into it.
final class HeardAsMessage extends HeardChannelPacket {
  const HeardAsMessage(this.messageId);

  final String messageId;
}

/// The packet was a reaction that was applied to its target, or a duplicate
/// of one, and nothing was stored: a copy has nothing to add.
final class HeardAsReaction extends HeardChannelPacket {
  const HeardAsReaction();
}

/// The channel packets heard in the last [ttl], by the identity every copy of
/// one packet shares, and what each became.
///
/// The radio hears a channel packet once per route it travels. The node logs
/// every copy, its own reception included, and delivers the packet as a frame
/// on top, so a message reaches the connector at least twice and once more
/// per repeater in range. The copies carry the same bytes; only the route,
/// the reading and the region can differ between them. Before this map every
/// copy went through the whole receive path, decoding, verification, quote
/// resolution, the history sort and write included, and was recognised as a
/// repeat only at the end, by the processed text. Here a copy is recognised
/// before any of it, by what can be read without decoding: the channel, the
/// packet timestamp, the sender name and the text as it travelled for a text
/// packet; the channel, the data type and the payload for a data packet.
///
/// A packet is claimed when its first copy starts processing and settled when
/// that copy has been stored or applied, so a copy arriving meanwhile waits
/// for the outcome instead of processing the packet again; an abandoned claim
/// frees the key, and a wait that outlasts [processingTimeout] counts as
/// abandoned. A packet the app sent itself is recorded at the send, so its
/// first echo is a copy too. Entries live [ttl], the self-echo window of the
/// connector's own repeat detection, and at most [maxEntries] are kept.
class HeardChannelPackets {
  HeardChannelPackets({
    this.ttl = const Duration(minutes: 10),
    this.maxEntries = 4096,
    this.processingTimeout = const Duration(seconds: 5),
  });

  final Duration ttl;
  final int maxEntries;
  final Duration processingTimeout;

  final LinkedHashMap<String, _Entry> _entries = LinkedHashMap<String, _Entry>();

  int get length => _entries.length;

  /// Packets claimed and not yet settled.
  int get pendingCount =>
      _entries.values.where((entry) => entry.pending != null).length;

  /// The key of a text packet: the channel, the packet timestamp and the
  /// sender name and text as they travelled, before any decoding.
  static String textKey({
    required int channelIndex,
    required int timestampSeconds,
    required String senderName,
    required String rawText,
  }) {
    final input = utf8.encode(
      '$channelIndex\u0000$timestampSeconds\u0000$senderName\u0000$rawText',
    );
    return 't:${_hex(crypto.sha256.convert(input).bytes)}';
  }

  /// A data packet is keyed by the hash the connector already computes over
  /// its channel, data type and payload, so the send and every copy agree.

  static String _hex(List<int> bytes) => bytes
      .take(12)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  /// Claims [key] for a copy about to be processed. Returns null when no copy
  /// of the packet is known: the caller processes it and then calls [settle]
  /// or [abandon]. Otherwise returns what the packet became, or a future of
  /// it while the first copy is still being processed, which resolves to null
  /// when that processing was abandoned or took longer than
  /// [processingTimeout].
  Future<HeardChannelPacket?>? claim(String key, {DateTime? now}) {
    final at = now ?? DateTime.now();
    _prune(at);
    final entry = _entries[key];
    if (entry == null) {
      _entries[key] = _Entry(at, pending: Completer<HeardChannelPacket?>());
      _trim();
      return null;
    }
    final pending = entry.pending;
    if (pending == null) {
      return Future<HeardChannelPacket?>.value(entry.outcome);
    }
    return pending.future.timeout(processingTimeout, onTimeout: () => null);
  }

  /// Records what the packet claimed under [key] became and releases the
  /// copies waiting for it. A key no longer claimed, pruned or trimmed
  /// meanwhile, is recorded anew.
  void settle(String key, HeardChannelPacket outcome, {DateTime? now}) {
    final entry = _entries[key];
    if (entry == null) {
      _entries[key] = _Entry(now ?? DateTime.now(), outcome: outcome);
      _trim();
      return;
    }
    entry.outcome = outcome;
    final pending = entry.pending;
    entry.pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(outcome);
  }

  /// Drops the claim on [key]: the copy was neither stored nor applied, and
  /// the next copy processes the packet anew. Copies waiting for it get
  /// nothing.
  void abandon(String key) => _drop(key);

  /// Records a packet this app sent itself, under the key its copies carry.
  void record(String key, HeardChannelPacket outcome, {DateTime? now}) =>
      settle(key, outcome, now: now);

  void clear() {
    for (final entry in _entries.values) {
      _release(entry);
    }
    _entries.clear();
  }

  void _prune(DateTime now) {
    while (_entries.isNotEmpty) {
      final oldest = _entries.entries.first;
      if (now.difference(oldest.value.heardAt) <= ttl) break;
      _drop(oldest.key);
    }
  }

  void _trim() {
    while (_entries.length > maxEntries) {
      _drop(_entries.keys.first);
    }
  }

  void _drop(String key) {
    final entry = _entries.remove(key);
    if (entry != null) _release(entry);
  }

  static void _release(_Entry entry) {
    final pending = entry.pending;
    entry.pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }
}

class _Entry {
  _Entry(this.heardAt, {this.pending, this.outcome});

  final DateTime heardAt;
  Completer<HeardChannelPacket?>? pending;
  HeardChannelPacket? outcome;
}

/// The claim on a packet's [key] held while its first copy is processed:
/// settled once with what the packet became, or abandoned when the copy is
/// neither stored nor applied, whichever comes first. A claim left open at
/// the end of processing, after a failure above all, is abandoned by
/// [abandonIfOpen], so the copies waiting for it are released.
class HeardChannelClaim {
  HeardChannelClaim(this._packets, this.key);

  final HeardChannelPackets _packets;
  final String key;
  bool _open = true;

  bool get isOpen => _open;

  void settle(HeardChannelPacket outcome) {
    if (!_open) return;
    _open = false;
    _packets.settle(key, outcome);
  }

  void abandonIfOpen() {
    if (!_open) return;
    _open = false;
    _packets.abandon(key);
  }
}
