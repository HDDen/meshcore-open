import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../connector/pending_command_replies.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../utils/app_logger.dart';

/// The node's own copy of [contact], asking first to write it into the node's
/// memory when only the app knows it. A login, a request, a share or a
/// message needs the node to hold the contact, and whether to spend a slot of
/// its table on it is the user's call, so nothing is added without asking.
///
/// Returns null when the user declines or the node refuses, a full table
/// above all. Without a connection there is no node to ask, and [contact]
/// comes back as it is, for the screens' own offline guards to handle.
Future<Contact?> ensureContactOnNode(
  BuildContext context,
  MeshCoreConnector connector,
  Contact contact,
) async {
  final stored = connector.getContactByPubKeyHex(contact.publicKeyHex);
  if (stored != null) return stored;
  if (!connector.isConnected) return contact;

  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.contacts_addToNodeTitle),
      content: Text(l10n.contacts_addToNodeMessage(contact.name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.common_cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.common_add),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return null;

  String? failure;
  try {
    if (!await connector.importDiscoveredContact(contact)) {
      failure = l10n.contacts_addToNodeFailed;
    }
  } catch (error) {
    appLogger.warn(
      'Adding ${contact.name} to the node failed: $error',
      tag: 'Contacts',
    );
    failure =
        error is CommandFailedException && error.errCode == errCodeTableFull
        ? l10n.contacts_addToNodeFull
        : l10n.contacts_addToNodeFailed;
  }
  if (!context.mounted) return null;
  if (failure != null) {
    showDismissibleSnackBar(context, content: Text(failure));
    return null;
  }
  return connector.getContactByPubKeyHex(contact.publicKeyHex) ?? contact;
}

/// Runs [action] with the node's copy of [contact] once the node holds it;
/// see [ensureContactOnNode].
Future<void> runWithContactOnNode(
  BuildContext context,
  MeshCoreConnector connector,
  Contact contact,
  void Function(Contact contact) action,
) async {
  final stored = await ensureContactOnNode(context, connector, contact);
  if (stored != null && context.mounted) action(stored);
}
