import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/contact.dart';
import 'mcmp_app_codec.dart';

/// Result of verifying an inbound MCMP v3 signature.
class McmpVerificationResult {
  final McmpSignatureStatus status;

  /// Hex of the contact key that successfully verified the signature
  /// (only set for [McmpSignatureStatus.valid]).
  final String? verifiedSenderKeyHex;

  /// True when the sender name belonged to more than one contact at the time
  /// of the check.
  final bool nameCollision;

  const McmpVerificationResult({
    required this.status,
    this.verifiedSenderKeyHex,
    this.nameCollision = false,
  });
}

/// App-side Ed25519 verification of MCMP v3 signatures. The node firmware
/// only exposes signing (CMD_SIGN_*); verification always happens here.
class McmpSignatureVerifier {
  McmpSignatureVerifier._();

  static final Ed25519 _ed25519 = Ed25519();

  static String _normalizeName(String name) => name.trim();

  static bool _namesMatch(String a, String b) =>
      _normalizeName(a) == _normalizeName(b);

  static List<Contact> _contactsNamed(List<Contact> contacts, String name) {
    return contacts
        .where((contact) => _namesMatch(contact.name, name))
        .toList(growable: false);
  }

  static Future<bool> _verify({
    required Uint8List canonical,
    required Uint8List signature,
    required Uint8List publicKey,
  }) async {
    try {
      return await _ed25519.verify(
        canonical,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Channel semantics: the claimed identity is [senderName] (from the binary
  /// envelope or the outer "Name: text" layer). Candidate keys are strictly
  /// the contacts bearing that name — verifying against arbitrary keys would
  /// let an attacker validate a spoofed name with their own signature. Any
  /// candidate whose key verifies -> valid.
  static Future<McmpVerificationResult> verifyChannelMessage({
    required DecodedMcmpAppMessage message,
    required String senderName,
    required Uint8List channelPsk,
    required List<Contact> contacts,
  }) async {
    final signature = message.signature;
    if (signature == null) {
      return const McmpVerificationResult(
        status: McmpSignatureStatus.unsigned,
      );
    }

    final candidates = _contactsNamed(contacts, senderName);
    final collision = candidates.length > 1;
    if (candidates.isEmpty) {
      return const McmpVerificationResult(
        status: McmpSignatureStatus.unverifiable,
      );
    }

    final canonical = McmpAppCodec.canonicalSigningBytes(
      context: McmpSigningContext.channel,
      binding: McmpAppCodec.channelSigningBinding(channelPsk),
      senderName: senderName,
      timestamp: message.timestamp,
      flags: McmpAppCodec.packFlags(
        hasReply: message.isReply,
        isSigned: true,
        hasSenderName: message.senderName != null,
      ),
      text: message.text,
      replyAuthorName: message.replyAuthorName,
      replyTimestamp: message.replyTimestamp,
    );

    for (final candidate in candidates) {
      if (await _verify(
        canonical: canonical,
        signature: signature,
        publicKey: candidate.publicKey,
      )) {
        return McmpVerificationResult(
          status: McmpSignatureStatus.valid,
          verifiedSenderKeyHex: candidate.publicKeyHex,
          nameCollision: collision,
        );
      }
    }
    return McmpVerificationResult(
      status: McmpSignatureStatus.invalid,
      nameCollision: collision,
    );
  }

  /// Room semantics: the author is located by the 4-byte pubkey prefix the
  /// room server transmits; the signed sender name embedded in the body must
  /// additionally match the local contact name, otherwise the message is
  /// treated as impersonation (invalid). This also intentionally makes a
  /// legitimately renamed author invalid until their fresh advert updates the
  /// local contact.
  static Future<McmpVerificationResult> verifyRoomMessage({
    required DecodedMcmpAppMessage message,
    required Uint8List authorPrefix,
    required Uint8List roomPublicKey,
    required List<Contact> contacts,
  }) async {
    final signature = message.signature;
    if (signature == null) {
      return const McmpVerificationResult(
        status: McmpSignatureStatus.unsigned,
      );
    }

    final signedName = message.senderName;
    if (signedName == null) {
      // A signed room body without an embedded name cannot be reconstructed
      // for verification.
      return const McmpVerificationResult(
        status: McmpSignatureStatus.invalid,
      );
    }

    final collision = _contactsNamed(contacts, signedName).length > 1;
    final candidates = contacts
        .where((contact) => _matchesPrefix(contact.publicKey, authorPrefix))
        .toList(growable: false);
    if (candidates.isEmpty) {
      return McmpVerificationResult(
        status: McmpSignatureStatus.unverifiable,
        nameCollision: collision,
      );
    }

    final canonical = McmpAppCodec.canonicalSigningBytes(
      context: McmpSigningContext.room,
      binding: McmpAppCodec.roomSigningBinding(roomPublicKey),
      senderName: signedName,
      timestamp: message.timestamp,
      flags: McmpAppCodec.packFlags(
        hasReply: message.isReply,
        isSigned: true,
        hasSenderName: true,
      ),
      text: message.text,
      replyAuthorName: message.replyAuthorName,
      replyTimestamp: message.replyTimestamp,
    );

    for (final candidate in candidates) {
      if (await _verify(
        canonical: canonical,
        signature: signature,
        publicKey: candidate.publicKey,
      )) {
        if (!_namesMatch(candidate.name, signedName)) {
          // The key is genuine but the signed name does not match the local
          // contact name: rename or deliberate impersonation.
          return McmpVerificationResult(
            status: McmpSignatureStatus.invalid,
            nameCollision: collision,
          );
        }
        return McmpVerificationResult(
          status: McmpSignatureStatus.valid,
          verifiedSenderKeyHex: candidate.publicKeyHex,
          nameCollision: collision,
        );
      }
    }
    return McmpVerificationResult(
      status: McmpSignatureStatus.invalid,
      nameCollision: collision,
    );
  }

  static bool _matchesPrefix(Uint8List fullKey, Uint8List prefix) {
    if (prefix.isEmpty || fullKey.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (fullKey[i] != prefix[i]) return false;
    }
    return true;
  }
}
