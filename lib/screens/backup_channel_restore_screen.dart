import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/backup_channel_restore.dart';
import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../services/backup_file_codec.dart';
import '../services/backup_import_planner.dart';
import '../utils/backup_json_file.dart';

const _maxBackupBytes = 32 * 1024 * 1024;

Future<XFile?> _pickBackupFile() =>
    openFile(acceptedTypeGroups: const [backupJsonFileType]);

Future<BackupImportPlan> _inspectBackup(
  ({String contents, String password}) input,
) => const BackupImportPlanner().inspect(
  input.contents,
  password: input.password,
);

class _BackupFileTooLarge implements Exception {
  const _BackupFileTooLarge();
}

Future<String> _readBackupFile(XFile file) async {
  if (await file.length() > _maxBackupBytes) throw const _BackupFileTooLarge();
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    if (bytes.length + chunk.length > _maxBackupBytes) {
      throw const _BackupFileTooLarge();
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}

class BackupChannelRestoreScreen extends StatefulWidget {
  const BackupChannelRestoreScreen({
    super.key,
    this.pickFile = _pickBackupFile,
  });

  final Future<XFile?> Function() pickFile;

  @override
  State<BackupChannelRestoreScreen> createState() =>
      _BackupChannelRestoreScreenState();
}

class _BackupChannelRestoreScreenState
    extends State<BackupChannelRestoreScreen> {
  bool _reading = false;
  bool _applying = false;
  String? _fileName;
  String? _notice;
  String? _destinationName;
  List<Channel>? _source;
  BackupChannelRestorePreview? _preview;

  bool get _busy => _reading || _applying;

  Future<void> _chooseFile() async {
    if (_busy) return;
    setState(() => _reading = true);
    try {
      final file = await widget.pickFile();
      if (!mounted || file == null) return;
      setState(() {
        _fileName = file.name;
        _source = null;
        _preview = null;
        _notice = null;
      });
      final contents = await _readBackupFile(file);
      final plan = await _inspectWithPassword(contents);
      if (!mounted || plan == null) return;
      final channels = plan.channels;
      if (channels == null || channels.isEmpty) {
        setState(() => _notice = context.l10n.backupChannels_noChannels);
        return;
      }
      _source = channels;
      _refreshPreview();
    } on _BackupFileTooLarge {
      if (mounted) {
        setState(() => _notice = context.l10n.backupChannels_fileTooLarge);
      }
    } on FormatException {
      if (mounted) {
        setState(() => _notice = context.l10n.backupChannels_invalidFile);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _notice = context.l10n.backupChannels_readFailed);
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<BackupImportPlan?> _inspectWithPassword(String contents) async {
    var password = '';
    while (mounted) {
      try {
        return await compute(
          _inspectBackup,
          (contents: contents, password: password),
        );
      } on BackupPasswordException catch (error) {
        if (!mounted) return null;
        final entered = await _askPassword(rejected: error.rejected);
        if (entered == null) return null;
        password = entered;
      }
    }
    return null;
  }

  Future<String?> _askPassword({required bool rejected}) {
    var password = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final l10n = context.l10n;
          return AlertDialog(
            title: Text(l10n.backupChannels_password),
            scrollable: true,
            content: TextField(
              autofocus: true,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l10n.backupChannels_password,
                helperText: rejected ? l10n.backupChannels_badPassword : null,
                helperMaxLines: 3,
              ),
              onChanged: (value) => setDialogState(() => password = value),
              onSubmitted: (value) {
                if (value.isNotEmpty) Navigator.pop(dialogContext, value);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.common_cancel),
              ),
              FilledButton(
                onPressed: password.isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, password),
                child: Text(l10n.common_ok),
              ),
            ],
          );
        },
      ),
    );
  }

  void _refreshPreview() {
    final channels = _source;
    if (channels == null) return;
    final connector = context.read<MeshCoreConnector>();
    setState(() {
      _preview = connector.previewBackupChannelRestore(channels);
      _destinationName = connector.deviceDisplayName;
      _notice = null;
    });
  }

  Future<void> _confirmRestore(
    BackupChannelRestorePreview preview,
    int changes,
  ) async {
    if (_busy) return;
    final node = _destinationName!;
    final connector = context.read<MeshCoreConnector>();
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        return AlertDialog(
          title: Text(l10n.backupChannels_title),
          scrollable: true,
          content: Text(l10n.backupChannels_confirm(node, changes)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.common_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.backupChannels_apply),
            ),
          ],
        );
      },
    );
    if (!mounted || approved != true) return;
    setState(() {
      _applying = true;
      _notice = null;
    });
    try {
      final result = await connector.restoreBackupChannels(preview);
      if (!mounted) return;
      final l10n = context.l10n;
      setState(() {
        _notice = switch (result.status) {
          BackupChannelRestoreStatus.completed =>
            l10n.backupChannels_applied(result.confirmed),
          BackupChannelRestoreStatus.destinationChanged =>
            l10n.backupChannels_changed(result.confirmed),
          BackupChannelRestoreStatus.writeUnconfirmed =>
            l10n.backupChannels_unconfirmed(result.confirmed),
          BackupChannelRestoreStatus.syncFailed =>
            l10n.backupChannels_syncFailed(result.confirmed),
        };
      });
    } catch (_) {
      if (mounted) {
        setState(() => _notice = context.l10n.backupChannels_applyFailed);
      }
    } finally {
      if (mounted) {
        setState(() {
          _applying = false;
          _preview = null;
        });
      }
    }
  }

  String _decisionLabel(
    BackupChannelRestorePreview preview,
    BackupChannelDecision decision,
  ) {
    final l10n = context.l10n;
    final slot = decision.destination?.index;
    return switch (decision.action) {
      BackupChannelAction.add => l10n.backupChannels_add(slot!),
      BackupChannelAction.rename =>
        l10n.backupChannels_rename(preview.currentNameAt(slot!) ?? '', slot),
      BackupChannelAction.alreadyPresent => l10n.backupChannels_existing(slot!),
      BackupChannelAction.duplicateInBackup => l10n.backupChannels_duplicate(slot!),
      BackupChannelAction.nameConflict => l10n.backupChannels_nameConflict,
      BackupChannelAction.noFreeSlot => l10n.channels_noFreeSlots,
      BackupChannelAction.unconfirmedSlot => l10n.backupChannels_slotUnknown,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preview = _preview;
    final changes = preview?.decisions.where(
      (decision) =>
          decision.action == BackupChannelAction.add ||
          decision.action == BackupChannelAction.rename,
    ).length ?? 0;

    return PopScope(
      canPop: !_applying,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.backupChannels_title)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l10n.backupChannels_intro),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _chooseFile,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(l10n.backupChannels_choose),
              ),
              if (_fileName case final name?) Text(name),
              if (_source != null)
                TextButton(
                  onPressed: _busy ? null : _refreshPreview,
                  child: Text(l10n.backupChannels_preview),
                ),
              if (_busy) const LinearProgressIndicator(),
              if (_notice case final notice?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(liveRegion: true, child: Text(notice)),
                )
              else if (_source != null && preview == null)
                Text(l10n.backupChannels_waitForNode),
              if (preview != null) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.backupChannels_target(_destinationName!),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final decision in preview.decisions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(decision.source.name),
                    subtitle: Text(_decisionLabel(preview, decision)),
                  ),
                if (changes > 0)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _confirmRestore(preview, changes),
                    child: Text(l10n.backupChannels_apply),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
