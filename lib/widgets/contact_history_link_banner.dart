import 'package:flutter/material.dart';

import '../helpers/contact_history_candidates.dart';
import '../l10n/l10n.dart';

/// Tells the reader of a chat that a history exists for a contact of the
/// same name under another key, and offers to attach it. The attaching
/// itself goes through [showContactHistoryLinkDialog], which says in plain
/// words that the name proves nothing.
class ContactHistoryLinkBanner extends StatelessWidget {
  final List<ContactHistoryCandidate> candidates;
  final ValueChanged<ContactHistoryCandidate> onAttach;
  final VoidCallback onDismiss;

  const ContactHistoryLinkBanner({
    super.key,
    required this.candidates,
    required this.onAttach,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            Icon(Icons.history, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.chat_historyLinkBanner,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            TextButton(
              onPressed: () => onAttach(candidates.first),
              child: Text(l10n.chat_historyLinkAttach),
            ),
            IconButton(
              tooltip: l10n.common_close,
              icon: const Icon(Icons.close, size: 20),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks before a history is attached: which contact and key it belongs to,
/// and that the user must be sure it is the same person, not a namesake.
/// Resolves to true only when the user chooses to attach.
Future<bool> showContactHistoryLinkDialog(
  BuildContext context, {
  required ContactHistoryCandidate candidate,
}) async {
  final l10n = context.l10n;
  final shortKey = candidate.publicKeyHex.length >= 8
      ? candidate.publicKeyHex.substring(0, 8)
      : candidate.publicKeyHex;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.chat_historyLinkTitle),
      content: Text(l10n.chat_historyLinkBody(candidate.name, shortKey)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.common_cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.chat_historyLinkAttach),
        ),
      ],
    ),
  );
  return confirmed == true;
}
