import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../l10n/l10n.dart';
import '../screens/additional_identity_screen.dart';
import '../services/adaptive_tx_power.dart';
import '../services/additional_identity_vault.dart';
import '../storage/prefs_manager.dart';

enum _NodeIdentityImportChoice { cancel, never, save }

/// The preference records only the decision, keyed by the full public key.
abstract final class NodeIdentityImportPrompt {
  static final _cancelledSessions = Expando<TxPowerSession>();

  static String _preferenceKey(String key) => 'node_identity_import_prompt_$key';

  static bool shouldOffer(MeshCoreConnector connector, TxPowerSession session) =>
      _cancelledSessions[connector] != session &&
      connector.isSessionReady &&
      connector.hasCompletedSelfInfoHandshake &&
      !connector.isRestartingTransport &&
      !connector.isOfflineMode &&
      !connector.isReviewMode &&
      connector.selfName?.trim().isNotEmpty == true &&
      connector.additionalIdentityInbox != null &&
      connector.additionalIdentityInbox!.entryFor(session.nodeKey) == null &&
      PrefsManager.instance.getBool(_preferenceKey(session.nodeKey)) != true;

  static Future<void> show(
    BuildContext context,
    MeshCoreConnector connector,
    TxPowerSession session,
  ) async {
    bool isCurrentSession() =>
        connector.isSessionReady &&
        !connector.isRestartingTransport &&
        connector.txPowerSession == session;
    if (!context.mounted ||
        !isCurrentSession() ||
        !shouldOffer(connector, session)) {
      return;
    }

    final l10n = context.l10n;
    void showError(String message) {
      if (!context.mounted || !isCurrentSession()) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(message)),
      );
    }

    try {
      if (await AdditionalIdentityVault.containsPublicKey(session.nodeKey)) {
        return;
      }
    } catch (_) {
      showError(l10n.extraKeys_actionError);
      return;
    }
    if (!context.mounted ||
        !isCurrentSession() ||
        !shouldOffer(connector, session)) {
      return;
    }
    final name = connector.selfName!.trim();

    final confirmed = await showDialog<_NodeIdentityImportChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(name),
        scrollable: true,
        content: Text(l10n.extraKeys_importNodePrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(_NodeIdentityImportChoice.cancel),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(_NodeIdentityImportChoice.never),
            child: Text(l10n.extraKeys_importNodeNever),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(_NodeIdentityImportChoice.save),
            child: Text(l10n.common_ok),
          ),
        ],
      ),
    );
    if (!context.mounted || !isCurrentSession()) return;
    final preference = _preferenceKey(session.nodeKey);
    try {
      if (confirmed != _NodeIdentityImportChoice.save) {
        _cancelledSessions[connector] = session;
        if (confirmed == _NodeIdentityImportChoice.never) {
          await PrefsManager.instance.setBool(preference, true);
        }
        return;
      }
      final vault = await AdditionalIdentityScreen.unlockVault(
        context,
        allowRemembered: true,
      );
      if (vault == null || !context.mounted || !isCurrentSession()) return;

      if (!vault.entries.any((entry) =>
          entry.identity.publicKeyHex == session.nodeKey)) {
        final entry = await connector.exportNodeIdentity(session, name: name);
        if (!context.mounted || !isCurrentSession()) return;
        if (entry == null) {
          showError(l10n.extraKeys_nodeExportUnavailable);
          return;
        }
        await vault.save(entry);
        connector.additionalIdentityInbox?.unlock(vault.entries);
      }
      await PrefsManager.instance.setBool(preference, true);
    } catch (_) {
      showError(l10n.extraKeys_actionError);
    }
  }
}
