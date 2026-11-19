import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/backup_node_identity.dart';
import '../l10n/l10n.dart';
import '../services/adaptive_tx_power.dart';
import '../services/additional_identity_vault.dart';
import 'additional_identity_key_dialog.dart';

class NodeKeySettingsDialog extends StatefulWidget {
  const NodeKeySettingsDialog({super.key, required this.connector});
  final MeshCoreConnector connector;

  @override
  State<NodeKeySettingsDialog> createState() => _NodeKeySettingsDialogState();
}

class _NodeKeySettingsDialogState extends State<NodeKeySettingsDialog> {
  late final TxPowerSession? _session = widget.connector.txPowerSession;
  AdditionalIdentityEntry? _entry;
  String? _notice;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _current => _session != null &&
      widget.connector.isSessionReady &&
      widget.connector.txPowerSession == _session;

  Future<void> _load() async {
    AdditionalIdentityEntry? entry;
    try {
      if (_current) {
        entry = await widget.connector.exportNodeIdentity(
          _session!, name: widget.connector.deviceDisplayName,
        );
      }
    } catch (_) {
      // Keep the editor unavailable when the current key cannot be verified.
    }
    if (!mounted) return;
    setState(() {
      _entry = _current ? entry : null;
      _loading = false;
    });
  }

  Future<bool> _save(AdditionalIdentityEntry entry) async {
    final l10n = context.l10n;
    if (!_current) {
      setState(() => _notice = l10n.backupIdentity_notReady);
      return false;
    }
    if (entry.identity.publicKeyHex == _entry!.identity.publicKeyHex &&
        entry.identity.privateKeyHex == _entry!.identity.privateKeyHex) {
      return true;
    }
    try {
      final identity = await BackupNodeIdentity.read(
        entry.identity.privateKeyHex,
        hexadecimal: true, publicKeys: [entry.identity.publicKeyHex],
      );
      if (!mounted) return false;
      final preview = _current ? widget.connector.previewBackupNodeIdentity(identity) : null;
      if (preview == null || preview.destinationKey != _session!.nodeKey) {
        setState(() => _notice = l10n.backupIdentity_notReady);
        return false;
      }
      final result = await widget.connector.restoreBackupNodeIdentity(preview);
      if (!mounted) return false;
      setState(() => _notice = switch (result.status) {
        BackupNodeIdentityStatus.completed => l10n.backupIdentity_completed,
        BackupNodeIdentityStatus.notReady => l10n.backupIdentity_notReady,
        BackupNodeIdentityStatus.unsupported => l10n.backupIdentity_unsupported,
        BackupNodeIdentityStatus.writeRejected => l10n.backupIdentity_rejected,
        BackupNodeIdentityStatus.unconfirmed => l10n.backupIdentity_unconfirmed,
        BackupNodeIdentityStatus.reconnectRequired => l10n.backupIdentity_reconnect,
      });
    } catch (_) {
      if (mounted) setState(() => _notice = l10n.backupIdentity_unconfirmed);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_entry != null && _notice == null) {
      return AdditionalIdentityKeyDialog.node(previous: _entry!, onSave: _save);
    }
    return AlertDialog(
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      content: _loading
          ? const Center(heightFactor: 1, child: CircularProgressIndicator())
          : Text(_notice ?? context.l10n.extraKeys_nodeExportUnavailable),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.common_close),
        ),
      ],
    );
  }
}
