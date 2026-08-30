import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../storage/message_history_maintenance.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/mesh_ui.dart';

class MessageHistoryDatabaseScreen extends StatefulWidget {
  const MessageHistoryDatabaseScreen({super.key});

  @override
  State<MessageHistoryDatabaseScreen> createState() =>
      _MessageHistoryDatabaseScreenState();
}

class _MessageHistoryDatabaseScreenState
    extends State<MessageHistoryDatabaseScreen> {
  final MessageHistoryMaintenance _maintenance = MessageHistoryMaintenance();
  MessageHistoryMaintenanceSnapshot? _snapshot;
  Object? _loadError;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final snapshot = await _maintenance.snapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<bool> _run(
    Future<String?> Function() operation, {
    bool refresh = true,
    bool nullIsCancellation = false,
  }) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      final message = await operation();
      if (!mounted) return false;
      if (message == null && nullIsCancellation) return false;
      if (refresh) await _refresh();
      if (!mounted) return false;
      showDismissibleSnackBar(
        context,
        content: Text(
          message ?? context.l10n.messageHistoryDatabaseOperationComplete,
        ),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      showDismissibleSnackBar(
        context,
        content: Text(
          context.l10n.messageHistoryDatabaseOperationFailed('$error'),
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String description,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: destructive
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _copyPath() async {
    final path = _snapshot?.databasePath;
    if (path == null) return;
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.messageHistoryDatabasePathCopied),
    );
  }

  Future<bool> _retryRejected() {
    final l10n = context.l10n;
    return _run(() async {
      final result = await _maintenance.retryRejected();
      return l10n.messageHistoryDatabaseRetryResult(
        result.restored,
        result.remaining,
      );
    });
  }

  Future<bool> _exportDiagnostic() {
    final l10n = context.l10n;
    return _run(() async {
      final path = await _maintenance.exportDiagnosticReport();
      if (path == null) return null;
      if (path.isEmpty) return l10n.messageHistoryDatabaseExportShared;
      return l10n.messageHistoryDatabaseExportSaved(path);
    }, refresh: false, nullIsCancellation: true);
  }

  Future<void> _exportRecovery() async {
    final l10n = context.l10n;
    final confirmed = await _confirm(
      title: l10n.messageHistoryDatabaseRecoveryWarningTitle,
      description: l10n.messageHistoryDatabaseRecoveryWarningDescription,
      confirmLabel: l10n.messageHistoryDatabaseRecovery,
    );
    if (!confirmed) return;
    final exported = await _run(() async {
      final path = await _maintenance.exportRecoveryData();
      if (path == null) return null;
      if (path.isEmpty) return l10n.messageHistoryDatabaseExportShared;
      return l10n.messageHistoryDatabaseExportSaved(path);
    }, refresh: false, nullIsCancellation: true);
    if (!exported || !mounted) return;
    final deleteAfterExport = await _confirm(
      title: l10n.messageHistoryDatabaseDeleteAfterExportTitle,
      description: l10n.messageHistoryDatabaseDeleteAfterExportDescription,
      confirmLabel: l10n.common_delete,
      destructive: true,
    );
    if (deleteAfterExport) await _deleteQuarantine();
  }

  Future<void> _clearQuarantine() async {
    final confirmed = await _confirm(
      title: context.l10n.messageHistoryDatabaseClearWarningTitle,
      description: context.l10n.messageHistoryDatabaseClearWarningDescription,
      confirmLabel: context.l10n.common_delete,
      destructive: true,
    );
    if (!confirmed) return;
    await _deleteQuarantine();
  }

  Future<void> _deleteQuarantine() async {
    final l10n = context.l10n;
    await _run(() async {
      final count = await _maintenance.clearRejected();
      return l10n.messageHistoryDatabaseDeleted(count);
    });
  }

  Future<bool> _incrementalVacuum() => _run(() async {
    await _maintenance.incrementalVacuum();
    return null;
  });

  Future<void> _fullVacuum() async {
    final confirmed = await _confirm(
      title: context.l10n.messageHistoryDatabaseFullVacuumWarningTitle,
      description:
          context.l10n.messageHistoryDatabaseFullVacuumWarningDescription,
      confirmLabel: context.l10n.messageHistoryDatabaseFullVacuum,
      destructive: true,
    );
    if (!confirmed) return;
    await _run(() async {
      await _maintenance.fullVacuum();
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final stats = snapshot?.stats;
    final hasQuarantine = (stats?.rejectedEntries ?? 0) > 0;
    final supportsIncrementalVacuum = stats?.autoVacuumMode == 2;
    return Scaffold(
      appBar: AppBar(
        title: AdaptiveAppBarTitle(
          context.l10n.messageHistoryDatabaseTitle,
        ),
        centerTitle: true,
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.l10n.messageHistoryDatabaseOperationFailed(
                          '$_loadError',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: Text(context.l10n.common_retry),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  SectionHeader(
                    context.l10n.messageHistoryDatabaseOverview,
                  ),
                  MeshCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _InfoRow(
                          icon: Icons.storage_outlined,
                          label: context.l10n.messageHistoryDatabaseFileSize,
                          value: _formatBytes(snapshot?.databaseBytes ?? 0),
                        ),
                        _InfoRow(
                          icon: Icons.person_outline,
                          label:
                              context.l10n.messageHistoryDatabaseDirectCount,
                          value: '${stats?.directMessages ?? 0}',
                        ),
                        _InfoRow(
                          icon: Icons.tag_outlined,
                          label:
                              context.l10n.messageHistoryDatabaseChannelCount,
                          value: '${stats?.channelMessages ?? 0}',
                        ),
                        _InfoRow(
                          icon: Icons.compress_outlined,
                          label:
                              context.l10n.messageHistoryDatabaseReclaimable,
                          value: _formatBytes(stats?.reclaimableBytes ?? 0),
                        ),
                      ],
                    ),
                  ),
                  MeshCard(
                    onTap: _busy ? null : _copyPath,
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(
                        context.l10n.messageHistoryDatabasePath,
                      ),
                      subtitle: SelectableText(snapshot?.databasePath ?? ''),
                      trailing: const Icon(Icons.copy_outlined),
                    ),
                  ),
                  SectionHeader(
                    context.l10n.messageHistoryDatabaseQuarantine,
                  ),
                  MeshCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: Icon(
                        hasQuarantine
                            ? Icons.warning_amber_outlined
                            : Icons.check_circle_outline,
                      ),
                      title: Text(
                        hasQuarantine
                            ? context.l10n
                                  .messageHistoryDatabaseQuarantineCount(
                                    stats!.rejectedEntries,
                                    _formatBytes(stats.rejectedBytes),
                                  )
                            : context
                                  .l10n
                                  .messageHistoryDatabaseQuarantineEmpty,
                      ),
                    ),
                  ),
                  if (hasQuarantine) ...[
                    _ActionCard(
                      icon: Icons.replay_outlined,
                      title: context.l10n.messageHistoryDatabaseRetry,
                      description:
                          context.l10n.messageHistoryDatabaseRetryDescription,
                      onTap: _busy ? null : _retryRejected,
                    ),
                    _ActionCard(
                      icon: Icons.description_outlined,
                      title: context.l10n.messageHistoryDatabaseDiagnostic,
                      description: context
                          .l10n
                          .messageHistoryDatabaseDiagnosticDescription,
                      onTap: _busy ? null : _exportDiagnostic,
                    ),
                    _ActionCard(
                      icon: Icons.lock_outline,
                      title: context.l10n.messageHistoryDatabaseRecovery,
                      description: context
                          .l10n
                          .messageHistoryDatabaseRecoveryDescription,
                      onTap: _busy ? null : _exportRecovery,
                    ),
                    _ActionCard(
                      icon: Icons.delete_outline,
                      title:
                          context.l10n.messageHistoryDatabaseClearQuarantine,
                      description: context
                          .l10n
                          .messageHistoryDatabaseClearQuarantineDescription,
                      destructive: true,
                      onTap: _busy ? null : _clearQuarantine,
                    ),
                  ],
                  SectionHeader(
                    context.l10n.messageHistoryDatabaseMaintenance,
                  ),
                  _ActionCard(
                    icon: Icons.cleaning_services_outlined,
                    title: context
                        .l10n
                        .messageHistoryDatabaseIncrementalVacuum,
                    description: supportsIncrementalVacuum
                        ? context
                              .l10n
                              .messageHistoryDatabaseIncrementalVacuumDescription
                        : context
                              .l10n
                              .messageHistoryDatabaseIncrementalVacuumUnavailableDescription,
                    onTap: _busy || !supportsIncrementalVacuum
                        ? null
                        : _incrementalVacuum,
                  ),
                  _ActionCard(
                    icon: Icons.build_outlined,
                    title: context.l10n.messageHistoryDatabaseFullVacuum,
                    description: context
                        .l10n
                        .messageHistoryDatabaseFullVacuumDescription,
                    destructive: true,
                    onTap: _busy ? null : _fullVacuum,
                  ),
                ],
              ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(value, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return MeshCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: ListTile(
        enabled: onTap != null,
        leading: Icon(icon, color: color),
        title: Text(title, style: color == null ? null : TextStyle(color: color)),
        subtitle: Text(description),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
