import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/backup_message_filter.dart';
import '../l10n/l10n.dart';
import '../models/app_settings_backup.dart';
import '../services/app_settings_service.dart';
import '../services/backup_file_codec.dart';
import '../services/backup_snapshot.dart';
import '../services/message_filter/message_filter_service.dart';
import '../utils/backup_json_file.dart';
import '../utils/share_origin.dart';

Future<String> _encodeBackup(
  ({BackupSnapshot snapshot, String password}) input,
) => input.snapshot.encode(password: input.password);

enum _BackupExportMode { selected, appSettings, messageHistory, messageFilter, filterTraining }

class BackupExportScreen extends StatefulWidget {
  const BackupExportScreen({
    super.key,
    this.saveFile = saveBackupJson,
  }) : _mode = _BackupExportMode.selected, _filter = null;

  const BackupExportScreen.appSettings({
    super.key,
    this.saveFile = saveBackupJson,
  }) : _mode = _BackupExportMode.appSettings, _filter = null;

  const BackupExportScreen.messageHistory({
    super.key,
    this.saveFile = saveBackupJson,
  }) : _mode = _BackupExportMode.messageHistory, _filter = null;

  const BackupExportScreen.messageFilter(
    MessageFilterService filter, {
    super.key,
    this.saveFile = saveBackupJson,
  }) : _mode = _BackupExportMode.messageFilter, _filter = filter;

  const BackupExportScreen.filterTraining(
    MessageFilterService filter, {
    super.key,
    this.saveFile = saveBackupJson,
  }) : _mode = _BackupExportMode.filterTraining, _filter = filter;

  final _BackupExportMode _mode;
  final MessageFilterService? _filter;

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
  late bool _includeChannels = widget._mode == _BackupExportMode.selected;
  bool _includeChannelSettings = false;
  bool _includeContacts = false;
  bool _includeContactSettings = false;
  bool _includeContactGroups = false;
  bool _includeCommunities = false;
  bool _includeDiscoveredContacts = false;
  late bool _includeSettings = widget._mode == _BackupExportMode.appSettings;
  bool _includeDirectHistory = true;
  bool _includeChannelHistory = true;
  String? _notice;

  bool get _historyOnly => widget._mode == _BackupExportMode.messageHistory;
  bool get _trainingOnly => widget._mode == _BackupExportMode.filterTraining;
  bool get _hasSelection => _historyOnly
      ? _includeDirectHistory || _includeChannelHistory
      : _includeChannels || _includeContacts || _includeContactGroups ||
          _includeDiscoveredContacts || _includeSettings || _includeCommunities ||
          _includeContactSettings || _includeChannelSettings || widget._filter != null;

  String _title(BuildContext context) => switch (widget._mode) {
    _BackupExportMode.messageHistory => context.l10n.backupMessageHistory_exportTitle,
    _BackupExportMode.messageFilter => context.l10n.backupMessageFilter_exportTitle,
    _BackupExportMode.filterTraining => context.l10n.backupFilterTraining_exportTitle,
    _ => context.l10n.backupExport_createTitle,
  };

  Future<BackupSnapshot?> _capture() async {
    if (_trainingOnly) {
      final corpus = await widget._filter!.snapshotTrainingBackup();
      return BackupSnapshot(filterTraining: corpus, createdAt: DateTime.now());
    }
    if (widget._filter case final filter?) {
      return BackupSnapshot(
        messageFilter: BackupMessageFilter.capture(filter.settings, filter.rules),
        createdAt: DateTime.now(),
      );
    }
    if (_historyOnly) {
      return context.read<MeshCoreConnector>().snapshotMessageHistoryBackup(
        includeDirect: _includeDirectHistory,
        includeChannels: _includeChannelHistory,
      );
    }
    final settings = _includeSettings
        ? AppSettingsBackup.capture(context.read<AppSettingsService>().settings)
        : null;
    if (_includeChannels || _includeContacts ||
        _includeContactGroups || _includeDiscoveredContacts || _includeCommunities ||
        _includeContactSettings || _includeChannelSettings) {
      return context.read<MeshCoreConnector>().snapshotNodeBackup(
        includeChannels: _includeChannels,
        includeContacts: _includeContacts,
        appSettings: settings,
        includeDiscoveredContacts: _includeDiscoveredContacts,
        includeContactGroups: _includeContactGroups,
        includeCommunities: _includeCommunities,
        includeContactSettings: _includeContactSettings,
        includeChannelSettings: _includeChannelSettings,
      );
    }
    return BackupSnapshot(appSettings: settings, createdAt: DateTime.now());
  }

  Future<void> _createBackup() async {
    if (_busy || !_hasSelection) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final snapshot = await _capture();
      if (!mounted) return;
      if (snapshot == null) {
        final l10n = context.l10n;
        setState(() => _notice = _historyOnly
            ? l10n.backupMessageHistory_exportNotReady
            : l10n.backupExport_notReady);
        return;
      }
      if (snapshot.isEmpty) {
        final l10n = context.l10n;
        setState(() => _notice = switch (widget._mode) {
          _BackupExportMode.messageHistory => l10n.backupMessageHistory_exportEmpty,
          _BackupExportMode.filterTraining => l10n.backupFilterTraining_empty,
          _ => l10n.backupExport_empty,
        });
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
    } on BackupFileTooLarge {
      if (mounted) {
        setState(() => _notice = context.l10n.backupMessageHistory_exportTooLarge);
      }
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
            title: Text(_title(context)),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (snapshot.nodeName case final name?) ...[
                  Text(l10n.backupChannels_target(name)),
                  const SizedBox(height: 8),
                ],
                Text(_trainingOnly
                    ? l10n.backupFilterTraining_passwordHint
                    : snapshot.containsCommunityKeys
                    ? l10n.backupCommunities_passwordHint
                    : snapshot.channelCount > 0
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
      appBar: AppBar(
        title: Text(_title(context)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget._filter == null)
              Text(_historyOnly
                  ? l10n.backupMessageHistory_exportIntro
                  : l10n.backupExport_pickSections),
            if (_historyOnly) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.backupMessageHistory_direct),
                value: _includeDirectHistory,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _includeDirectHistory = value ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.backupMessageHistory_channels),
                value: _includeChannelHistory,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _includeChannelHistory = value ?? false),
              ),
            ] else if (_trainingOnly)
              Text(l10n.backupFilterTraining_scope)
            else if (widget._filter != null)
              Text(l10n.backupMessageFilter_scope)
            else if (widget._mode == _BackupExportMode.appSettings)
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
                title: Text(l10n.backupChannelSettings_label),
                value: _includeChannelSettings,
                onChanged: _busy ? null : (value) => setState(
                  () => _includeChannelSettings = value ?? false,
                ),
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
                title: Text(l10n.backupContactSettings_label),
                value: _includeContactSettings,
                onChanged: _busy ? null : (value) => setState(
                  () => _includeContactSettings = value ?? false,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.backupContactGroups_label),
                value: _includeContactGroups,
                onChanged: _busy ? null : (value) => setState(
                  () => _includeContactGroups = value ?? false,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.backupDiscoveredContacts_label),
                value: _includeDiscoveredContacts,
                onChanged: _busy ? null : (value) => setState(
                  () => _includeDiscoveredContacts = value ?? false,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.backupCommunities_label),
                value: _includeCommunities,
                onChanged: _busy ? null : (value) => setState(
                  () => _includeCommunities = value ?? false,
                ),
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
