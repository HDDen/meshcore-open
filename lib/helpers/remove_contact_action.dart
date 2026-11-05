import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../utils/app_logger.dart';
import 'snack_bar_builder.dart';

/// Shared feedback for the contact list, map and discovery undo action.
/// Discovered-only contacts still follow the connector's local deletion path.
Future<void> deleteContactWithFeedback(
  BuildContext context,
  MeshCoreConnector connector,
  Contact contact, {
  bool keepMessages = false,
}) async {
  try {
    await connector.deleteContact(
      contact,
      waitForAck: true,
      keepMessages: keepMessages,
    );
  } catch (error) {
    appLogger.warn('Remove contact failed: $error', tag: 'Contacts');
    if (!context.mounted) return;
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.contacts_removeFailed),
    );
  }
}
