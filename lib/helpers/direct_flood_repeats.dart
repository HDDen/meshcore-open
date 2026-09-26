import 'dart:typed_data';

/// The conversation and message a counted retransmission belongs to.
typedef DirectFloodTarget = ({String conversationKey, String messageId});

/// One heard copy of a flood packet: the route it had travelled, sender
/// first, the hash width that route is written in, and the signal of our
/// reception.
typedef DirectFloodCopy = ({
  Uint8List pathBytes,
  int pathHashWidth,
  double? snr,
  int? rssi,
});

/// A delivered message tied to a heard packet: how many retransmissions of
/// it were already heard, the packet itself and every copy of it heard so
/// far, the first being the one the node delivered. The transport code, the
/// first of the two in front of the path, names the region the packet was
/// scoped to and is null for a plain flood; the payload is what that code
/// was computed over.
typedef DirectFloodBinding = ({
  int relays,
  Uint8List payload,
  int? transportCode,
  List<DirectFloodCopy> copies,
});

/// Retransmissions of direct messages sent or received by flood, counted from
/// the RX log the way channel repeats are.
///
/// A flood copy of a TXT_MSG keeps its payload byte for byte at every hop;
/// only the path grows. Once a message is tied to a payload, every further
/// copy carrying that payload is one more retransmission of it, whoever
/// relayed it. Tying the two is the whole difficulty, because the payload is
/// encrypted:
///
/// * a copy the connector could decrypt, with the node's key that direct echo
///   recovery keeps in RAM, carries an identity (the other party's key and
///   the sender timestamp) and binds only to the message with that identity;
/// * otherwise an outgoing message binds the first unclaimed copy going from
///   our one-byte hash to its recipient's once the node has confirmed a flood
///   send, and a delivered incoming message binds the earliest unclaimed copy
///   from its sender's hash to ours that took as many hops as the node
///   reported, since the node hands messages over in the order it heard
///   them. Two different outgoing messages waiting on the same pair of hashes
///   are refused rather than guessed between.
///
/// An outgoing message counts every copy heard: our own transmission never
/// reaches the RX log, so each copy is a relay's. An incoming one counts the
/// copies after the first, which is the one the node delivered.
class DirectFloodRepeats {
  /// How long a heard packet is remembered. Relays finish within seconds; the
  /// margin covers a message that waits in the node's queue before the app
  /// fetches it.
  static const Duration packetLifetime = Duration(minutes: 10);

  /// How long a flood send waits for its first relayed copy.
  static const Duration expectationLifetime = Duration(minutes: 2);

  static const int maxPackets = 256;

  // Insertion order is the order the packets were first heard.
  final Map<String, _FloodPacket> _packets = {};
  final List<_OutgoingExpectation> _expected = [];

  /// What a decrypted copy and its message have in common: the other party's
  /// key and the sender timestamp in seconds.
  static String identityOf(String peerKeyHex, int timestampSeconds) =>
      '$peerKeyHex:$timestampSeconds';

  /// The node confirmed a flood send of [target] to the peer whose key starts
  /// with [destinationHash]; ours starts with [sourceHash]. Each attempt of a
  /// message is expected separately, as each is a packet of its own.
  void expectOutgoing({
    required DirectFloodTarget target,
    required int destinationHash,
    required int sourceHash,
    required String identity,
    required DateTime at,
  }) {
    _prune(at);
    _expected.add(
      _OutgoingExpectation(
        target: target,
        destinationHash: destinationHash,
        sourceHash: sourceHash,
        identity: identity,
        armedAt: at,
      ),
    );
  }

  /// A flood TXT_MSG copy from the RX log: its payload, `[dest][src][mac]
  /// [ciphertext]`, the hops it had taken, its first transport code, null
  /// for a plain flood, and the [copy] itself, route and signal. [identity]
  /// is set when the connector could decrypt it. Returns the message that
  /// just gained one retransmission, or null.
  DirectFloodTarget? observe({
    required Uint8List payload,
    required int hopCount,
    required DateTime at,
    required DirectFloodCopy copy,
    int? transportCode,
    String? identity,
  }) {
    if (payload.length < 4) return null;
    _prune(at);
    final key = String.fromCharCodes(payload);
    final known = _packets[key];
    if (known != null) {
      known.copies.add(copy);
      known.identity ??= identity;
      return known.target;
    }
    final packet = _FloodPacket(
      payload: Uint8List.fromList(payload),
      hopCount: hopCount,
      transportCode: transportCode,
      firstHeardAt: at,
      firstCopy: copy,
      identity: identity,
    );
    _packets[key] = packet;
    if (_packets.length > maxPackets) _packets.remove(_packets.keys.first);
    final expectation = _expectationFor(packet);
    if (expectation == null) return null;
    _expected.remove(expectation);
    packet.target = expectation.target;
    return packet.target;
  }

  /// A message the node delivered by flood after [hopCount] hops, sent from
  /// the peer whose key starts with [sourceHash] to ours, [destinationHash].
  /// Returns the copy it was tied to, with the retransmissions of it already
  /// heard, or null when no heard copy could be tied to it.
  DirectFloodBinding? bindIncoming({
    required DirectFloodTarget target,
    required int sourceHash,
    required int destinationHash,
    required int hopCount,
    required String identity,
    required DateTime at,
  }) {
    _prune(at);
    final candidates = [
      for (final packet in _packets.values)
        if (packet.target == null &&
            packet.sourceHash == sourceHash &&
            packet.destinationHash == destinationHash)
          packet,
    ];
    // A decrypted copy names its message; only a copy that could not be read
    // falls back to the hop count, the earliest heard first.
    final chosen =
        _firstWhereOrNull(candidates, (p) => p.identity == identity) ??
        _firstWhereOrNull(
          candidates,
          (p) => p.identity == null && p.hopCount == hopCount,
        );
    if (chosen == null) return null;
    chosen.target = target;
    return (
      relays: chosen.copies.length - 1,
      payload: chosen.payload,
      transportCode: chosen.transportCode,
      copies: List.unmodifiable(chosen.copies),
    );
  }

  void clear() {
    _packets.clear();
    _expected.clear();
  }

  /// The expectation [packet] answers: the only message waiting on its pair
  /// of hashes, narrowed by identity when the copy could be read. Several
  /// attempts of one message count as one candidate.
  _OutgoingExpectation? _expectationFor(_FloodPacket packet) {
    final candidates = [
      for (final expectation in _expected)
        if (expectation.destinationHash == packet.destinationHash &&
            expectation.sourceHash == packet.sourceHash &&
            (packet.identity == null ||
                packet.identity == expectation.identity))
          expectation,
    ];
    if (candidates.isEmpty) return null;
    final targets = {for (final candidate in candidates) candidate.target};
    return targets.length == 1 ? candidates.first : null;
  }

  void _prune(DateTime now) {
    _packets.removeWhere(
      (_, packet) => now.difference(packet.firstHeardAt) > packetLifetime,
    );
    _expected.removeWhere(
      (expectation) =>
          now.difference(expectation.armedAt) > expectationLifetime,
    );
  }

  static _FloodPacket? _firstWhereOrNull(
    List<_FloodPacket> packets,
    bool Function(_FloodPacket packet) test,
  ) {
    for (final packet in packets) {
      if (test(packet)) return packet;
    }
    return null;
  }
}

class _FloodPacket {
  _FloodPacket({
    required this.payload,
    required this.hopCount,
    required this.transportCode,
    required this.firstHeardAt,
    required DirectFloodCopy firstCopy,
    this.identity,
  }) : copies = [firstCopy];

  final Uint8List payload;
  int get destinationHash => payload[0];
  int get sourceHash => payload[1];

  /// Hops taken by the first copy heard; for an incoming message that is the
  /// copy the node delivered.
  final int hopCount;
  final int? transportCode;
  final DateTime firstHeardAt;
  String? identity;

  /// Every copy heard, in that order.
  final List<DirectFloodCopy> copies;
  DirectFloodTarget? target;
}

class _OutgoingExpectation {
  _OutgoingExpectation({
    required this.target,
    required this.destinationHash,
    required this.sourceHash,
    required this.identity,
    required this.armedAt,
  });

  final DirectFloodTarget target;
  final int destinationHash;
  final int sourceHash;
  final String identity;
  final DateTime armedAt;
}
