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

/// A heard copy tied to a message, and whether it belongs to the message's
/// latest attempt: only those copies count, since every attempt is a packet
/// of its own and the relay counter starts over with each.
typedef DirectFloodHit = ({DirectFloodTarget target, bool currentAttempt});

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
///   the sender timestamp) and its attempt number, and binds only to the
///   message and attempt with that identity;
/// * otherwise an outgoing message binds the first unclaimed copy going from
///   our one-byte hash to its recipient's once the node has confirmed a flood
///   send, and a delivered incoming message binds the earliest unclaimed copy
///   from its sender's hash to ours that took as many hops as the node
///   reported, since the node hands messages over in the order it heard
///   them. Two different outgoing messages waiting on the same pair of hashes
///   are refused rather than guessed between.
///
/// Every attempt of a message is a packet of its own, and the count belongs
/// to the latest one: a copy of an earlier attempt still says which route it
/// took, but is not counted. An outgoing message counts every copy heard: our
/// own transmission never reaches the RX log, so each copy is a relay's. An
/// incoming one counts the copies after the first, which is the one the node
/// delivered; the sender's retry, once delivered, becomes the latest attempt.
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

  /// The latest attempt of each message: the one the node confirmed last for
  /// an outgoing message, the packet bound last for an incoming one.
  final Map<DirectFloodTarget, int> _latestAttempt = {};

  /// What a decrypted copy and its message have in common: the other party's
  /// key and the sender timestamp in seconds.
  static String identityOf(String peerKeyHex, int timestampSeconds) =>
      '$peerKeyHex:$timestampSeconds';

  /// A new attempt of [target] has been planned, numbered [attempt], and is
  /// not on the air yet: from this moment the copies of every earlier
  /// attempt stop counting, so the counter the retry shows from the start
  /// is its own and not the last attempt's.
  void planAttempt({required DirectFloodTarget target, required int attempt}) {
    _rememberAttempt(target, attempt);
  }

  /// The node confirmed a flood send of [target], its attempt number
  /// [attempt], to the peer whose key starts with [destinationHash]; ours
  /// starts with [sourceHash]. A new attempt takes the place of the older
  /// ones still waiting: had their copies been heard, they would have
  /// arrived within seconds of the send.
  void expectOutgoing({
    required DirectFloodTarget target,
    required int destinationHash,
    required int sourceHash,
    required String identity,
    required int attempt,
    required DateTime at,
  }) {
    _prune(at);
    _expected.removeWhere((expectation) => expectation.target == target);
    _rememberAttempt(target, attempt);
    _expected.add(
      _OutgoingExpectation(
        target: target,
        destinationHash: destinationHash,
        sourceHash: sourceHash,
        identity: identity,
        attempt: attempt,
        armedAt: at,
      ),
    );
  }

  /// A flood TXT_MSG copy from the RX log: its payload, `[dest][src][mac]
  /// [ciphertext]`, the hops it had taken, its first transport code, null
  /// for a plain flood, and the [copy] itself, route and signal. [identity]
  /// and [attempt] are set when the connector could decrypt it. Returns the
  /// message the copy belongs to, or null.
  DirectFloodHit? observe({
    required Uint8List payload,
    required int hopCount,
    required DateTime at,
    required DirectFloodCopy copy,
    int? transportCode,
    String? identity,
    int? attempt,
  }) {
    if (payload.length < 4) return null;
    _prune(at);
    final key = String.fromCharCodes(payload);
    final known = _packets[key];
    if (known != null) {
      known.copies.add(copy);
      known.identity ??= identity;
      return _hitOf(known);
    }
    final packet = _FloodPacket(
      payload: Uint8List.fromList(payload),
      hopCount: hopCount,
      transportCode: transportCode,
      firstHeardAt: at,
      firstCopy: copy,
      identity: identity,
      decryptedAttempt: attempt,
    );
    _packets[key] = packet;
    if (_packets.length > maxPackets) _packets.remove(_packets.keys.first);
    final expectation = _expectationFor(packet);
    if (expectation == null) return null;
    _expected.remove(expectation);
    packet.target = expectation.target;
    packet.attempt = expectation.attempt;
    return _hitOf(packet);
  }

  /// A message the node delivered by flood after [hopCount] hops, sent from
  /// the peer whose key starts with [sourceHash] to ours, [destinationHash].
  /// Returns the copy it was tied to, with the retransmissions of it already
  /// heard, or null when no heard copy could be tied to it. The bound packet
  /// becomes the message's latest attempt.
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
    final attempt = (_latestAttempt[target] ?? -1) + 1;
    chosen.attempt = attempt;
    _rememberAttempt(target, attempt);
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
    _latestAttempt.clear();
  }

  DirectFloodHit? _hitOf(_FloodPacket packet) {
    final target = packet.target;
    if (target == null) return null;
    return (target: target, currentAttempt: !packet.superseded);
  }

  /// Makes [attempt] the latest of [target]. The packets bound to any other
  /// attempt of it stay for their routes but are superseded for good: a
  /// later restart at the same number must not revive them.
  void _rememberAttempt(DirectFloodTarget target, int attempt) {
    _latestAttempt.remove(target);
    _latestAttempt[target] = attempt;
    if (_latestAttempt.length > maxPackets) {
      _latestAttempt.remove(_latestAttempt.keys.first);
    }
    for (final packet in _packets.values) {
      if (packet.target == target && packet.attempt != attempt) {
        packet.superseded = true;
      }
    }
  }

  /// The expectation [packet] answers: the only message waiting on its pair
  /// of hashes, narrowed by identity and attempt when the copy could be read.
  _OutgoingExpectation? _expectationFor(_FloodPacket packet) {
    final candidates = [
      for (final expectation in _expected)
        if (expectation.destinationHash == packet.destinationHash &&
            expectation.sourceHash == packet.sourceHash &&
            (packet.identity == null ||
                packet.identity == expectation.identity) &&
            (packet.decryptedAttempt == null ||
                packet.decryptedAttempt == expectation.attempt))
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
    this.decryptedAttempt,
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

  /// The attempt number read out of a decrypted copy, null otherwise.
  final int? decryptedAttempt;

  /// Every copy heard, in that order.
  final List<DirectFloodCopy> copies;
  DirectFloodTarget? target;

  /// The attempt this packet is, once tied to a message: the confirmed
  /// attempt for an outgoing one, the binding order for an incoming one.
  int? attempt;

  /// Set once a later attempt of the same message was planned or bound;
  /// the packet's copies then add routes but no longer count.
  bool superseded = false;
}

class _OutgoingExpectation {
  _OutgoingExpectation({
    required this.target,
    required this.destinationHash,
    required this.sourceHash,
    required this.identity,
    required this.attempt,
    required this.armedAt,
  });

  final DirectFloodTarget target;
  final int destinationHash;
  final int sourceHash;
  final String identity;
  final int attempt;
  final DateTime armedAt;
}
