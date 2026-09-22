import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../models/direct_echo_observation.dart';
import '../models/message.dart';
import '../models/path_selection.dart';
import 'direct_echo_crypto.dart';
import 'direct_message_progress_helper.dart';

/// Recovering a direct message from its raw RX-log copy.
///
/// The companion logs every packet its radio hears before it decides what to
/// do with it, and a direct-routed packet whose next hop is somebody else is
/// then dropped. A TXT_MSG addressed to this node can therefore be heard
/// while it is still travelling through repeaters near us — the copy carries
/// the route it has left, and nothing else about the packet differs from the
/// one that will arrive at the end of that route. With the node's private key
/// in RAM the app can decrypt it as the node would, show it early, and answer
/// with the ACK the node would have sent.
///
/// The whole feature is opt-in (`AppSettings.directEchoRecovery`, off by
/// default) and reaches the connector in three narrow places: the key request
/// after SELF_INFO, a branch in `_handleLogRxData`, and the duplicate check of
/// `_processIncomingMessage`, where a repeat or the ordinary delivery merges
/// into the message the echo created.

/// The node's private key, in RAM and nowhere else, with the shared secrets
/// derived from it. Nothing in here is ever written to storage or to a log;
/// [clear] zero-fills every buffer and runs on disconnect, on a node change,
/// when the option is switched off and when the connector is disposed.
class DirectEchoKeyStore {
  Uint8List? _scalar;
  final Map<String, Uint8List> _secrets = {};

  bool get hasKey => _scalar != null;

  /// Keeps the X25519 scalar — the first 32 bytes of the 64-byte key the
  /// firmware exports — and forgets the rest at once.
  void setPrivateKey(Uint8List privateKey) {
    clear();
    _scalar = Uint8List.fromList(privateKey.sublist(0, 32));
    privateKey.fillRange(0, privateKey.length, 0);
  }

  /// The shared secret with [contact], computed once per key and cached, so
  /// a busy sender costs one exchange rather than one per heard packet.
  Uint8List? secretFor(Contact contact) {
    final scalar = _scalar;
    if (scalar == null) return null;
    if (contact.publicKey.length != DirectEchoCrypto.publicKeyLength) {
      return null;
    }
    final cached = _secrets[contact.publicKeyHex];
    if (cached != null) return cached;
    try {
      final secret = DirectEchoCrypto.sharedSecret(scalar, contact.publicKey);
      _secrets[contact.publicKeyHex] = secret;
      return secret;
    } catch (_) {
      return null;
    }
  }

  void clear() {
    _scalar?.fillRange(0, _scalar!.length, 0);
    _scalar = null;
    for (final secret in _secrets.values) {
      secret.fillRange(0, secret.length, 0);
    }
    _secrets.clear();
  }
}

/// A decrypted TXT_MSG body: `[timestamp u32][attempt | type << 2][text][NUL]`
/// followed by the block's zero padding, and in newer firmware an extended
/// attempt byte after the NUL.
class DirectEchoPlaintext {
  final Uint8List bytes;
  final int timestamp;
  final int flags;
  final int textLength;

  const DirectEchoPlaintext({
    required this.bytes,
    required this.timestamp,
    required this.flags,
    required this.textLength,
  });

  int get textType => flags >> 2;
  int get attempt => flags & 0x03;
  Uint8List get textBytes => bytes.sublist(5, 5 + textLength);
}

/// What the receive path needs to know about the echo a message came from:
/// who sent it, the plaintext the ACK is computed over, and the copy heard.
class DirectEchoContext {
  final Contact contact;
  final DirectEchoPlaintext plaintext;
  final DirectEchoObservation observation;

  const DirectEchoContext({
    required this.contact,
    required this.plaintext,
    required this.observation,
  });
}

abstract final class DirectEchoRecovery {
  static const int _routeTransportFlood = 0x00;
  static const int _routeFlood = 0x01;
  static const int _routeDirect = 0x02;
  static const int _ackPriority = 0; // routed traffic, as the node sends ACKs

  /// An echo worth decrypting: addressed to our one-byte hash and still with
  /// hops to go. A copy with none left is the packet the node itself receives
  /// and hands over through the ordinary queue, so decoding it here would
  /// only duplicate that work.
  static bool isCandidate(DirectMessageEcho echo, Uint8List selfPublicKey) {
    if (selfPublicKey.isEmpty) return false;
    return echo.destinationHash == selfPublicKey[0] &&
        echo.remainingHopCount > 0 &&
        echo.payload.length > 2 + 2;
  }

  /// Contacts whose key starts with the packet's one-byte source hash. Several
  /// can match; the caller tries each secret until the MAC verifies, which is
  /// what the firmware's `searchPeersByHash` loop does.
  static List<Contact> candidateSenders(
    Iterable<Contact> contacts,
    int sourceHash,
  ) => [
    for (final contact in contacts)
      if (contact.publicKey.isNotEmpty && contact.publicKey[0] == sourceHash)
        contact,
  ];

  /// The MAC and ciphertext behind the two hash bytes.
  static Uint8List macAndCiphertext(DirectMessageEcho echo) =>
      Uint8List.fromList(echo.payload.sublist(2));

  /// Accepts only an ordinary text message: CLI replies and room posts are
  /// the node's business, and an empty text is nothing to show.
  static DirectEchoPlaintext? parsePlaintext(Uint8List plaintext) {
    if (plaintext.length < 6) return null;
    final flags = plaintext[4];
    if ((flags >> 2) != txtTypePlain) return null;
    final textLength = DirectEchoCrypto.textLength(plaintext);
    if (textLength == 0) return null;
    final timestamp =
        plaintext[0] |
        (plaintext[1] << 8) |
        (plaintext[2] << 16) |
        (plaintext[3] << 24);
    return DirectEchoPlaintext(
      bytes: plaintext,
      timestamp: timestamp,
      flags: flags,
      textLength: textLength,
    );
  }

  /// The CONTACT_MSG_RECV_V3 frame the companion would have queued had the
  /// packet completed its route, so the ordinary receive path decodes,
  /// verifies, stores and notifies exactly as it does for that frame. The
  /// path byte is the direct sentinel, as the firmware writes it.
  static Uint8List buildContactMessageFrame(
    Uint8List senderPublicKey,
    DirectEchoPlaintext plaintext, {
    required double snr,
  }) {
    final text = plaintext.textBytes;
    final frame = Uint8List(4 + 6 + 1 + 1 + 4 + text.length);
    var i = 0;
    frame[i++] = respCodeContactMsgRecvV3;
    frame[i++] = (snr * 4).round().clamp(-128, 127).toInt() & 0xFF;
    frame[i++] = 0;
    frame[i++] = 0;
    frame.setRange(i, i + 6, senderPublicKey);
    i += 6;
    frame[i++] = 0xFF;
    frame[i++] = plaintext.textType;
    frame[i++] = plaintext.timestamp & 0xFF;
    frame[i++] = (plaintext.timestamp >> 8) & 0xFF;
    frame[i++] = (plaintext.timestamp >> 16) & 0xFF;
    frame[i++] = (plaintext.timestamp >> 24) & 0xFF;
    frame.setRange(i, i + text.length, text);
    return frame;
  }

  /// A message created from its first echo: the bar runs over the hops the
  /// packet still had ahead of it plus the final leg to us, none done yet.
  static Message stampFirstEcho(
    Message message,
    DirectEchoObservation observation,
  ) {
    return message.copyWith(
      deliveryProgressTotalSteps: observation.remainingHopCount + 1,
      deliveryProgressCompletedSteps: 0,
      directEchoObservations: [observation],
    );
  }

  /// Folds another heard copy into [existing]. A route already listed only
  /// fills the signal reading it lacks; a new one is appended. Progress moves
  /// with the freshest copy but never backwards: a copy with more hops left
  /// than the bar was sized for widens the bar and keeps what was done, one
  /// heard from further along advances it. A message the node delivered
  /// before any echo was heard keeps its bar off — there is nothing left to
  /// wait for — and only records the route. Returns null when nothing changed.
  static Message? mergeRepeat(
    Message existing,
    DirectEchoObservation observation,
  ) {
    final observations = _includeObservation(
      existing.directEchoObservations,
      observation,
    );
    var total = existing.deliveryProgressTotalSteps;
    var completed = existing.deliveryProgressCompletedSteps;
    if (total > 0) {
      final ahead = observation.remainingHopCount + 1;
      if (ahead > total) total = ahead;
      final done = total - ahead;
      if (done > completed) completed = done;
    }
    if (observations == null &&
        total == existing.deliveryProgressTotalSteps &&
        completed == existing.deliveryProgressCompletedSteps) {
      return null;
    }
    return existing.copyWith(
      deliveryProgressTotalSteps: total,
      deliveryProgressCompletedSteps: completed,
      directEchoObservations: observations,
    );
  }

  /// The ordinary delivery of a message the echo already showed: the route is
  /// complete, so the bar fills and goes away. Null when there was no bar.
  static Message? completeOnDelivery(Message existing) {
    final total = existing.deliveryProgressTotalSteps;
    if (total <= 0 || existing.deliveryProgressCompletedSteps >= total) {
      return null;
    }
    return existing.copyWith(deliveryProgressCompletedSteps: total);
  }

  static List<DirectEchoObservation>? _includeObservation(
    List<DirectEchoObservation> existing,
    DirectEchoObservation observation,
  ) {
    for (var i = 0; i < existing.length; i++) {
      final current = existing[i];
      if (!current.hasSamePath(observation)) continue;
      if ((current.snr != null || observation.snr == null) &&
          (current.rssi != null || observation.rssi == null)) {
        return null;
      }
      return [
        ...existing.sublist(0, i),
        DirectEchoObservation(
          remainingPath: current.remainingPath,
          pathHashWidth: current.pathHashWidth,
          snr: current.snr ?? observation.snr,
          rssi: current.rssi ?? observation.rssi,
        ),
        ...existing.sublist(i + 1),
      ];
    }
    return [...existing, observation];
  }

  /// The raw packet for CMD_SEND_RAW_PACKET that carries the ACK back the
  /// way `BaseChatMesh::sendAckTo` would send it: direct along our route to
  /// the sender when we have one, else a flood — scoped with [transportCode]
  /// when the node has a default flood scope, plain otherwise. The path byte
  /// packs the hash width and the hop count as the firmware encodes it.
  static Uint8List buildAckPacket({
    required Uint8List ack,
    required PathSelection route,
    required int pathHashWidth,
    int? transportCode,
  }) {
    final flood = route.useFlood || route.hopCount < 0;
    final pathBytes = flood ? const <int>[] : route.pathBytes;
    final hopCount = flood ? 0 : route.hopCount;
    var width = pathHashWidth.clamp(1, 4).toInt();
    if (hopCount > 0 &&
        pathBytes.length % hopCount == 0 &&
        pathBytes.length ~/ hopCount >= 1 &&
        pathBytes.length ~/ hopCount <= 4) {
      width = pathBytes.length ~/ hopCount;
    }
    final routeType = flood
        ? (transportCode != null ? _routeTransportFlood : _routeFlood)
        : _routeDirect;
    final transport = flood && transportCode != null;
    final packet = <int>[
      (payloadTypeACK << 2) | routeType,
      if (transport) ...[
        transportCode & 0xFF,
        (transportCode >> 8) & 0xFF,
        0,
        0,
      ],
      ((width - 1) << 6) | (hopCount & 0x3F),
      ...pathBytes,
      ...ack,
    ];
    return Uint8List.fromList(packet);
  }

  /// `[CMD_SEND_RAW_PACKET][priority][packet]`.
  static Uint8List buildSendRawPacketFrame(Uint8List packet) =>
      Uint8List.fromList([cmdSendRawPacket, _ackPriority, ...packet]);
}
