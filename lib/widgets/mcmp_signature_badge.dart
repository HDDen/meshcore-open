import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import '../helpers/mcmp_app_codec.dart';
import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';

/// Compact signature-status badge for message bubbles.
///
/// Outgoing MCMP v3 messages show "sent signed / unsigned". Incoming messages
/// show the verification result; for any signed message (valid or invalid) the
/// fingerprint of the associated key is displayed («404654...AF4322») so trust
/// is anchored to the key, not the display name. The exception is
/// "unverifiable", where no contact bears the name and there is no key to show.
/// A warning badge is added when the sender name belonged to several contacts
/// at verification time.
class McmpSignatureBadge extends StatelessWidget {
  final McmpSignatureStatus status;
  final bool isOutgoing;

  /// Signed flag exactly as transmitted (used for own outgoing messages).
  final bool isSigned;

  /// True when the message traveled as an MCMP v3 container at all.
  final bool wasMcmpV3;
  final String? verifiedSenderKeyHex;
  final bool nameCollision;

  /// Direct messages never show a fingerprint.
  final bool showFingerprint;
  final double textScale;
  final Color color;
  final Color errorColor;

  const McmpSignatureBadge({
    super.key,
    required this.status,
    required this.isOutgoing,
    required this.isSigned,
    required this.wasMcmpV3,
    this.verifiedSenderKeyHex,
    this.nameCollision = false,
    this.showFingerprint = true,
    required this.textScale,
    required this.color,
    required this.errorColor,
  });

  static String formatFingerprint(String keyHex) {
    final normalized = keyHex.toUpperCase();
    if (normalized.length <= 12) return normalized;
    return '${normalized.substring(0, 6)}...'
        '${normalized.substring(normalized.length - 6)}';
  }

  /// Human-readable label for a verification status (used by the manual
  /// re-check snackbar and tooltips).
  static String statusLabel(BuildContext context, McmpSignatureStatus status) {
    final l10n = context.l10n;
    switch (status) {
      case McmpSignatureStatus.valid:
        return l10n.settings_mcmp_signed;
      case McmpSignatureStatus.invalid:
        return l10n.chat_mcmpSignatureInvalid;
      case McmpSignatureStatus.unverifiable:
        return l10n.chat_mcmpSignatureUnverifiable;
      case McmpSignatureStatus.transportAuthenticated:
        return l10n.chat_mcmpSignatureTransport;
      case McmpSignatureStatus.none:
      case McmpSignatureStatus.unsigned:
        return l10n.settings_mcmp_noSign;
    }
  }

  static bool isVisible({
    required McmpSignatureStatus status,
    required bool isOutgoing,
    required bool wasMcmpV3,
  }) {
    // A message still waiting in the send queue carries the format version but
    // no signature result yet — its status is still "none". Showing the badge
    // then would claim it was sent unsigned, which the real send may well
    // disprove a few seconds later.
    if (isOutgoing) {
      return wasMcmpV3 && status != McmpSignatureStatus.none;
    }
    switch (status) {
      case McmpSignatureStatus.valid:
      case McmpSignatureStatus.invalid:
      case McmpSignatureStatus.unverifiable:
      case McmpSignatureStatus.transportAuthenticated:
        return true;
      // Incoming MCMP v3 messages sent without a signature still show the
      // crossed-out grey lock.
      case McmpSignatureStatus.unsigned:
        return wasMcmpV3;
      case McmpSignatureStatus.none:
        return false;
    }
  }

  bool get _visible =>
      isVisible(status: status, isOutgoing: isOutgoing, wasMcmpV3: wasMcmpV3);

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final l10n = context.l10n;
    final iconSize = 12.0 * textScale;

    if (isOutgoing) {
      // Textual badge, kept commented in case it comes back:
      // return Text(
      //   isSigned ? l10n.settings_mcmp_signed : l10n.settings_mcmp_noSign,
      //   style: MeshTheme.mono(fontSize: 10 * textScale, color: color),
      // );
      // Outgoing messages use the same lock icons as incoming ones: closed
      // green when sent signed, crossed-out grey when sent unsigned.
      return Tooltip(
        message: isSigned
            ? l10n.settings_mcmp_signed
            : l10n.settings_mcmp_noSign,
        child: Icon(
          isSigned ? Icons.lock_outlined : Icons.no_encryption_outlined,
          size: iconSize,
          color: isSigned ? MeshPalette.signal : color,
        ),
      );
    }

    final IconData icon;
    final String tooltip;
    Color iconColor = color;
    // Unverifiable renders a grey lock with a small "?" overlay.
    var questionOverlay = false;

    switch (status) {
      case McmpSignatureStatus.valid:
        // Closed lock: signature verified. Green normally, amber when the
        // sender name is shared by several contacts (verified key, ambiguous
        // name).
        icon = Icons.lock_outlined;
        tooltip = l10n.settings_mcmp_signed;
        iconColor = nameCollision ? MeshPalette.warn : MeshPalette.signal;
        break;
      case McmpSignatureStatus.invalid:
        // Open red lock with the shackle turned aside: signature invalid.
        icon = Symbols.lock_open_right;
        tooltip = l10n.chat_mcmpSignatureInvalid;
        iconColor = errorColor;
        break;
      case McmpSignatureStatus.unverifiable:
        // Grey lock with a question mark: signed, but there is no matching
        // contact key to check against.
        icon = Icons.lock_outlined;
        tooltip = l10n.chat_mcmpSignatureUnverifiable;
        questionOverlay = true;
        break;
      case McmpSignatureStatus.transportAuthenticated:
        icon = Icons.enhanced_encryption_outlined;
        tooltip = l10n.chat_mcmpSignatureTransport;
        break;
      case McmpSignatureStatus.unsigned:
        // Crossed-out grey lock: the message was sent without a signature.
        icon = Icons.no_encryption_outlined;
        tooltip = l10n.settings_mcmp_noSign;
        break;
      case McmpSignatureStatus.none:
        return const SizedBox.shrink();
    }

    // Any signed message shows the public key fingerprint, anchoring trust to
    // the key rather than the display name. The exception is "unverifiable"
    // (no contact with that name), where there is no key to show.
    final fingerprint =
        showFingerprint &&
            (status == McmpSignatureStatus.valid ||
                status == McmpSignatureStatus.invalid) &&
            verifiedSenderKeyHex != null
        ? formatFingerprint(verifiedSenderKeyHex!)
        : null;

    Widget iconWidget = Icon(icon, size: iconSize, color: iconColor);
    if (questionOverlay) {
      iconWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(
            right: -2,
            bottom: -2,
            child: Text(
              '?',
              style: TextStyle(
                fontSize: iconSize * 0.7,
                fontWeight: FontWeight.w800,
                height: 1,
                color: iconColor,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Tooltip(message: tooltip, child: iconWidget),
        if (fingerprint != null) ...[
          SizedBox(width: 3 * textScale),
          Text(
            fingerprint,
            style: MeshTheme.mono(fontSize: 10 * textScale, color: color),
          ),
        ],
        if (nameCollision) ...[
          SizedBox(width: 3 * textScale),
          Tooltip(
            message: l10n.settings_mcmp_senderNameCollision,
            child: Icon(
              Icons.people_alt_outlined,
              size: iconSize,
              color: errorColor,
            ),
          ),
        ],
      ],
    );
  }
}
