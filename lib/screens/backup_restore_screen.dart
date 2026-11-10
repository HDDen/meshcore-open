import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/backup_channel_restore.dart';
import '../helpers/backup_contact_restore.dart';
import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../models/contact.dart';
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

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen.channels({
    super.key,
    this.pickFile = _pickBackupFile,
  }) : _contactsOnly = false;

  const BackupRestoreScreen.contacts({
    super.key,
    this.pickFile = _pickBackupFile,
  }) : _contactsOnly = true;

  final Future<XFile?> Function() pickFile;
  final bool _contactsOnly;

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _reading = false;
  bool _applying = false;
  String? _fileName;
  String? _notice;
  String? _destinationName;
  List<Channel>? _source;
  BackupChannelRestorePreview? _preview;
  ({String? nodeKey, List<Contact> contacts})? _contactSource;
  BackupContactRestorePreview? _contactPreview;

  bool get _busy => _reading || _applying;
  bool get _hasSource => _source != null || _contactSource != null;

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
        _contactSource = null;
        _contactPreview = null;
        _notice = null;
      });
      final contents = await _readBackupFile(file);
      final plan = await _inspectWithPassword(contents);
      if (!mounted || plan == null) return;
      final l10n = context.l10n;
      if (widget._contactsOnly) {
        final contacts = plan.contacts;
        if (contacts == null || contacts.isEmpty) {
          setState(() => _notice = l10n.backupContacts_noContacts);
          return;
        }
        _contactSource = (nodeKey: plan.sourcePublicKey, contacts: contacts);
      } else {
        final channels = plan.channels;
        if (channels == null || channels.isEmpty) {
          setState(() => _notice = l10n.backupChannels_noChannels);
          return;
        }
        _source = channels;
      }
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
    final contactSource = _contactSource;
    final connector = context.read<MeshCoreConnector>();
    setState(() {
      if (channels != null) {
        _preview = connector.previewBackupChannelRestore(channels);
      }
      if (contactSource != null) {
        _contactPreview = connector.previewBackupContactRestore(
          sourcePublicKey: contactSource.nodeKey,
          contacts: contactSource.contacts,
        );
      }
      _destinationName = connector.deviceDisplayName;
      _notice = null;
    });
  }

  Future<void> _confirmRestore({
    required String title,
    required String prompt,
    required Future<String> Function() apply,
  }) async {
    if (_busy) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        return AlertDialog(
          title: Text(title),
          scrollable: true,
          content: Text(prompt),
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
      final message = await apply();
      if (!mounted) return;
      setState(() => _notice = message);
    } catch (_) {
      if (mounted) {
        final l10n = context.l10n;
        setState(() => _notice = widget._contactsOnly
            ? l10n.backupContacts_applyFailed
            : l10n.backupChannels_applyFailed);
      }
    } finally {
      if (mounted) {
        setState(() {
          _applying = false;
          _preview = null;
          _contactPreview = null;
        });
      }
    }
  }

  Future<void> _restoreChannels(BackupChannelRestorePreview preview, int count) {
    final connector = context.read<MeshCoreConnector>();
    final l10n = context.l10n;
    return _confirmRestore(
      title: l10n.backupChannels_title,
      prompt: l10n.backupChannels_confirm(_destinationName!, count),
      apply: () async {
        final result = await connector.restoreBackupChannels(preview);
        return switch (result.status) {
          BackupChannelRestoreStatus.completed =>
            l10n.backupChannels_applied(result.confirmed),
          BackupChannelRestoreStatus.destinationChanged =>
            l10n.backupChannels_changed(result.confirmed),
          BackupChannelRestoreStatus.writeUnconfirmed =>
            l10n.backupChannels_unconfirmed(result.confirmed),
          BackupChannelRestoreStatus.syncFailed =>
            l10n.backupChannels_syncFailed(result.confirmed),
        };
      },
    );
  }

  Future<void> _restoreContacts(BackupContactRestorePreview preview, int count) {
    final connector = context.read<MeshCoreConnector>();
    final l10n = context.l10n;
    return _confirmRestore(
      title: l10n.backupContacts_title,
      prompt: l10n.backupContacts_confirm(_destinationName!, count),
      apply: () async {
        final result = await connector.restoreBackupContacts(preview);
        return switch (result.status) {
          BackupContactRestoreStatus.completed =>
            l10n.backupContacts_applied(result.confirmed),
          BackupContactRestoreStatus.destinationChanged =>
            l10n.backupContacts_changed(result.confirmed),
          BackupContactRestoreStatus.overwriteUnsafe =>
            l10n.backupContacts_overwriteUnsafe(result.confirmed),
          BackupContactRestoreStatus.writeUnconfirmed =>
            l10n.backupContacts_unconfirmed(result.confirmed),
          BackupContactRestoreStatus.syncFailed =>
            l10n.backupContacts_syncFailed(result.confirmed),
        };
      },
    );
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
    final contactPreview = _contactPreview;
    final contactAdds = [
      if (contactPreview != null)
        for (final decision in contactPreview.decisions)
          if (decision.action == BackupContactAction.add) decision,
    ];
    final skippedContacts = contactPreview?.decisions.where(
      (decision) =>
          decision.action == BackupContactAction.self ||
          decision.action == BackupContactAction.unsupportedType,
    ).length ?? 0;
    final changes = preview?.decisions.where(
      (decision) =>
          decision.action == BackupChannelAction.add ||
          decision.action == BackupChannelAction.rename,
    ).length ?? 0;

    return PopScope(
      canPop: !_applying,
      child: Scaffold(
        appBar: AppBar(title: Text(widget._contactsOnly
            ? l10n.backupContacts_title
            : l10n.backupChannels_title)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget._contactsOnly
                  ? l10n.backupContacts_intro
                  : l10n.backupChannels_intro),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _chooseFile,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(l10n.backupChannels_choose),
              ),
              if (_fileName case final name?) Text(name),
              if (_hasSource)
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
              else if (_hasSource && preview == null && contactPreview == null)
                Text(widget._contactsOnly
                    ? l10n.backupContacts_waitForNode
                    : l10n.backupChannels_waitForNode),
              if (preview != null || contactPreview != null)
                Text(
                  l10n.backupChannels_target(_destinationName!),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              if (preview != null) ...[
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
                        : () => _restoreChannels(preview, changes),
                    child: Text(l10n.backupChannels_apply),
                  ),
              ],
              if (contactPreview != null) ...[
                Text(l10n.backupContacts_summary(
                  contactAdds.length,
                  contactPreview.decisions.where(
                    (decision) => decision.action == BackupContactAction.alreadyPresent,
                  ).length,
                  contactPreview.decisions.where(
                    (decision) => decision.action == BackupContactAction.noRoom,
                  ).length,
                )),
                if (skippedContacts > 0)
                  Text(l10n.backupContacts_skipped(skippedContacts)),
                if (contactAdds.any((decision) => decision.usesFloodFallback))
                  Text(l10n.backupContacts_floodFallback),
                for (final decision in contactAdds)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(decision.contact.name),
                    subtitle: Text(decision.contact.publicKeyHex),
                  ),
                if (contactAdds.isNotEmpty)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _restoreContacts(contactPreview, contactAdds.length),
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
