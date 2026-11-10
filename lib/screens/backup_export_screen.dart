import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../l10n/l10n.dart';
import '../models/app_settings_backup.dart';
import '../services/app_settings_service.dart';
import '../services/backup_snapshot.dart';
import '../utils/backup_json_file.dart';
import '../utils/share_origin.dart';

Future<String> _encodeBackup(
  ({BackupSnapshot snapshot, String password}) input,
) => input.snapshot.encode(password: input.password);

class BackupExportScreen extends StatefulWidget {
  const BackupExportScreen({
    super.key,
    this.saveFile = saveBackupJson,
  }) : _settingsOnly = false;

  const BackupExportScreen.appSettings({
    super.key,
    this.saveFile = saveBackupJson,
  }) : _settingsOnly = true;

  final bool _settingsOnly;

  final Future<BackupJsonSaveResult> Function(
    String contents,
    String fileName, {
    Rect? sharePositionOrigin,
  }) saveFile;

  @override
  State<BackupExportScreen> createState() => _BackupExportScreenState();
}

class _BackupExportScreenState extends State<BackupExportScreen> {
  bool _busy = false;
  late bool _includeChannels = !widget._settingsOnly;
  bool _includeContacts = false;
  late bool _includeSettings = widget._settingsOnly;
  String? _notice;

  bool get _hasSelection => _includeChannels || _includeContacts || _includeSettings;

  Future<void> _createBackup() async {
    if (_busy || !_hasSelection) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final settings = _includeSettings
          ? AppSettingsBackup.capture(context.read<AppSettingsService>().settings)
          : null;
      final snapshot = _includeChannels || _includeContacts
          ? await context.read<MeshCoreConnector>().snapshotNodeBackup(
              includeChannels: _includeChannels,
              includeContacts: _includeContacts,
              appSettings: settings,
            )
          : BackupSnapshot(appSettings: settings, createdAt: DateTime.now());
      if (!mounted) return;
      if (snapshot == null) {
        setState(() => _notice = context.l10n.backupExport_notReady);
        return;
      }
      if (snapshot.isEmpty) {
        setState(() => _notice = context.l10n.backupExport_empty);
        return;
      }
      final password = await _askPassword(snapshot);
      if (!mounted || password == null) return;
      final contents = await compute(
        _encodeBackup,
        (snapshot: snapshot, password: password),
      );
      if (!mounted) return;
      final result = await widget.saveFile(
        contents,
        snapshot.fileName,
        sharePositionOrigin: shareOriginOf(context),
      );
      if (!mounted) return;
      final l10n = context.l10n;
      setState(() {
        _notice = switch (result) {
          BackupJsonSaveResult.saved => l10n.backupExport_saved,
          BackupJsonSaveResult.shareOpened => l10n.backupExport_shared,
          BackupJsonSaveResult.cancelled => null,
        };
      });
    } catch (_) {
      if (mounted) {
        setState(() => _notice = context.l10n.backupExport_failed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPassword(BackupSnapshot snapshot) {
    var password = '';
    var confirmation = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final l10n = context.l10n;
          return AlertDialog(
            title: Text(l10n.backupExport_createTitle),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (snapshot.nodeName case final name?) ...[
                  Text(l10n.backupChannels_target(name)),
                  const SizedBox(height: 8),
                ],
                Text(snapshot.channelCount > 0
                    ? l10n.backupChannels_exportPasswordHint
                    : l10n.backupExport_passwordHint),
                TextField(
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: l10n.backupChannels_password,
                  ),
                  onChanged: (value) => setDialogState(() {
                    password = value;
                    if (value.isEmpty) confirmation = '';
                  }),
                ),
                if (password.isNotEmpty)
                  TextField(
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: l10n.backupChannels_repeatPassword,
                    ),
                    onChanged: (value) =>
                        setDialogState(() => confirmation = value),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.common_cancel),
              ),
              FilledButton(
                onPressed: password.isEmpty || password == confirmation
                    ? () => Navigator.pop(dialogContext, password)
                    : null,
                child: Text(l10n.common_save),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupExport_createTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.backupExport_pickSections),
            if (widget._settingsOnly)
              Text(l10n.backupAppSettings_scope)
            else ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.channels_title),
                value: _includeChannels,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _includeChannels = value ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.contacts_title),
                subtitle: Text(l10n.backupExport_contactsHint),
                value: _includeContacts,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _includeContacts = value ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.settings_appSettings),
                subtitle: Text(l10n.backupAppSettings_scope),
                value: _includeSettings,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _includeSettings = value ?? false),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || !_hasSelection ? null : _createBackup,
              icon: const Icon(Icons.save_outlined),
              label: Text(l10n.backupChannels_createBackup),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_notice case final notice?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(liveRegion: true, child: Text(notice)),
              ),
          ],
        ),
      ),
    );
  }
}
