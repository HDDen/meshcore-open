import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../l10n/l10n.dart';
import '../screens/additional_identity_screen.dart';
import '../services/adaptive_tx_power.dart';
import '../services/additional_identity_vault.dart';
import '../storage/prefs_manager.dart';

/// The preference records only the decision, keyed by the full public key.
abstract final class NodeIdentityImportPrompt {
  static String _preferenceKey(String key) => 'node_identity_import_prompt_$key';

  static bool shouldOffer(MeshCoreConnector connector, TxPowerSession session) =>
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
    bool isCurrent() =>
        context.mounted &&
        connector.isSessionReady &&
        !connector.isRestartingTransport &&
        connector.txPowerSession == session;
    if (!isCurrent() || !shouldOffer(connector, session)) return;

    final l10n = context.l10n;
    void showError(String message) {
      if (!isCurrent()) return;
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
    if (!isCurrent() || !shouldOffer(connector, session)) return;
    final name = connector.selfName!.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(name),
        scrollable: true,
        content: Text(l10n.extraKeys_importNodePrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.common_ok),
          ),
        ],
      ),
    );
    if (!isCurrent()) return;
    final preference = _preferenceKey(session.nodeKey);
    try {
      if (confirmed != true) {
        await PrefsManager.instance.setBool(preference, true);
        return;
      }
      final vault = await AdditionalIdentityScreen.unlockVault(
        context,
        allowRemembered: true,
      );
      if (vault == null || !isCurrent()) return;

      if (!vault.entries.any((entry) =>
          entry.identity.publicKeyHex == session.nodeKey)) {
        final entry = await connector.exportNodeIdentity(session, name: name);
        if (!isCurrent()) return;
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
