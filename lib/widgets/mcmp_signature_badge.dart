import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import '../helpers/mcmp_app_codec.dart';
import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';

/// Compact signature-status badge for message bubbles.
///
/// Outgoing MCMP v3 messages show "sent signed / unsigned". Incoming messages
/// show the verification result; for a valid signature the fingerprint of the
/// key that actually verified is displayed («404654...AF4322») so trust is
/// anchored to the key, not the display name. A warning badge is added when
/// the sender name belonged to several contacts at verification time.
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
    if (isOutgoing) return wasMcmpV3;
    switch (status) {
      case McmpSignatureStatus.valid:
      case McmpSignatureStatus.invalid:
      case McmpSignatureStatus.unverifiable:
      case McmpSignatureStatus.transportAuthenticated:
        return true;
      case McmpSignatureStatus.none:
      case McmpSignatureStatus.unsigned:
        return false;
    }
  }

  bool get _visible => isVisible(
    status: status,
    isOutgoing: isOutgoing,
    wasMcmpV3: wasMcmpV3,
  );

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final l10n = context.l10n;
    final iconSize = 12.0 * textScale;

    if (isOutgoing) {
      // Outgoing MCMP v3 messages show a textual badge instead of a shield
      // icon: "signed" / "no signature".
      return Text(
        isSigned ? l10n.settings_mcmp_signed : l10n.settings_mcmp_noSign,
        style: MeshTheme.mono(fontSize: 10 * textScale, color: color),
      );
    }

    final IconData icon;
    final String tooltip;
    Color iconColor = color;

    switch (status) {
      case McmpSignatureStatus.valid:
        // Closed green lock: signature verified.
        icon = Icons.lock_outlined;
        tooltip = l10n.settings_mcmp_signed;
        iconColor = MeshPalette.signal;
        break;
      case McmpSignatureStatus.invalid:
        // Open red lock with the shackle turned aside: signature invalid.
        icon = Symbols.lock_open_right;
        tooltip = l10n.chat_mcmpSignatureInvalid;
        iconColor = errorColor;
        break;
      case McmpSignatureStatus.unverifiable:
        // Crossed-out grey lock: signature cannot be checked.
        icon = Icons.no_encryption_outlined;
        tooltip = l10n.chat_mcmpSignatureUnverifiable;
        break;
      case McmpSignatureStatus.transportAuthenticated:
        icon = Icons.enhanced_encryption_outlined;
        tooltip = l10n.chat_mcmpSignatureTransport;
        break;
      case McmpSignatureStatus.none:
      case McmpSignatureStatus.unsigned:
        return const SizedBox.shrink();
    }

    final fingerprint =
        showFingerprint &&
            status == McmpSignatureStatus.valid &&
            verifiedSenderKeyHex != null
        ? formatFingerprint(verifiedSenderKeyHex!)
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Tooltip(
          message: tooltip,
          child: Icon(icon, size: iconSize, color: iconColor),
        ),
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
