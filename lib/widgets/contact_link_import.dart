import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/contact_link.dart';
import '../helpers/contact_ui.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';

/// Adds the contact a `meshcore://` link describes, tapped in a message or
/// pasted from the clipboard, the way the shared contact card adds its
/// contact: after a question naming the contact, with a second line when the
/// node holds the key already.
class ContactLinkImport {
  ContactLinkImport._();

  static Future<void> confirmAndAdd(
    BuildContext context,
    ContactLink link,
  ) async {
    final connector = context.read<MeshCoreConnector>();
    if (connector.isOfflineMode) {
      _warn(context, context.l10n.app_offline_unableToMessage);
      return;
    }
    if (!connector.isConnected) {
      _warn(context, context.l10n.scanner_notConnected);
      return;
    }
    final selfKeyHex = connector.selfPublicKeyHex;
    if (selfKeyHex.isNotEmpty && selfKeyHex.toLowerCase() == link.publicKeyHex) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.chat_contactIsYou),
      );
      return;
    }
    final replaces = connector.getContactByPubKeyHex(link.publicKeyHex) != null;
    if (!await _confirm(context, link, replaces: replaces)) return;
    if (!context.mounted) return;
    try {
      switch (link) {
        // The app's own link carries no signature: the contact is written
        // as from a shared contact card.
        case ContactAddLink():
          await connector.addOrUpdateSharedContact(
            publicKey: link.publicKey,
            type: link.type,
            name: link.name,
          );
        // The advert packet goes to the node, which verifies and keeps it,
        // as the contacts screen hands one over from the clipboard.
        case ContactAdvertLink():
          await connector.sendFrame(
            buildImportContactFrame(link.packet),
            expectsGenericAck: true,
            waitForGenericAck: true,
          );
      }
      if (!context.mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.contacts_contactImported),
      );
    } catch (_) {
      if (!context.mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.contacts_contactImportFailed),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  static void _warn(BuildContext context, String message) {
    showDismissibleSnackBar(
      context,
      content: Text(message),
      backgroundColor: MeshPalette.warn,
    );
  }

  static Future<bool> _confirm(
    BuildContext context,
    ContactLink link, {
    required bool replaces,
  }) async {
    final l10n = context.l10n;
    final typeLabel = switch (link.type) {
      advTypeRepeater => l10n.chat_contactTypeRepeater,
      advTypeRoom => l10n.chat_contactTypeRoom,
      advTypeSensor => l10n.chat_contactTypeSensor,
      _ => l10n.chat_contactTypeNode,
    };
    final typeColor = contactTypeColor(link.type);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.chat_addContact),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(contactTypeIcon(link.type), size: 18, color: typeColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      link.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.chat_contactType(typeLabel),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: typeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                link.shortPublicKey,
                style: MeshTheme.mono(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (replaces) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.chat_sureToReplaceContact,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.common_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.common_add),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }
}
