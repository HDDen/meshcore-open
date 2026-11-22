import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/backup_additional_identities.dart';
import '../helpers/backup_filter_training.dart';
import '../helpers/backup_message_filter.dart';
import '../helpers/backup_node_profile.dart';
import '../helpers/backup_node_identity.dart';
import '../helpers/backup_location_preferences.dart';
import '../helpers/portable_app_settings.dart';
import '../helpers/official_backup_export.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../models/app_settings_backup.dart';
import '../services/app_settings_service.dart';
import '../services/backup_file_codec.dart';
import '../services/backup_import_planner.dart';
import '../services/backup_snapshot.dart';
import '../storage/message_history_storage.dart';
import '../storage/prefs_manager.dart';
import '../storage/region_store.dart';
import '../utils/backup_json_file.dart';
import '../utils/share_origin.dart';
import '../widgets/mesh_ui.dart';
import 'additional_identity_screen.dart';
import 'backup_export_screen.dart';
import 'backup_restore_screen.dart';

typedef _ImportedSections = ({
  Map<BackupRestoreSection, BackupImportPlan> sections,
  Set<BackupRestoreSection> invalid,
});

Future<_ImportedSections> _inspect(
  ({String contents, String password}) input,
) => const BackupImportPlanner().inspectSections(
  input.contents, password: input.password,
);

Future<String> _encode(
  ({BackupSnapshot snapshot, String password}) input,
) => input.snapshot.encode(password: input.password);

String _encodeOfficial(({BackupSnapshot snapshot, int? manualAddContacts, Map<int, String> channelRegions}) input) =>
    input.snapshot.encodeOfficial(manualAddContacts: input.manualAddContacts, channelRegions: input.channelRegions);

Future<XFile?> _pickFile() =>
    openFile(acceptedTypeGroups: const [backupJsonFileType]);

class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    this.pickFile = _pickFile,
    this.saveFile = saveBackupJson,
  });

  final Future<XFile?> Function() pickFile;
  final Future<BackupJsonSaveResult> Function(
    String contents,
    String fileName, {
    Rect? sharePositionOrigin,
  }) saveFile;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _password = TextEditingController();
  final _selected = <String>{
    'deviceName', 'publicKey', 'radioSettings', 'regions', 'location',
    'privacySettings', 'contactSettings', PortableAppSettings.shared, PortableAppSettings.extension,
    'contacts', 'perContactSettings', 'contactGroups', 'discoveredContacts',
    'channels', 'channelSettings', 'communities', 'channelFilters',
  };
  static const _nodeItems = {
    'deviceName', 'publicKey', 'privateKey', 'radioSettings', 'location',
    'privacySettings', 'contactSettings', 'contacts', 'perContactSettings', 'contactGroups',
    'discoveredContacts', 'channels', 'channelSettings', 'communities', 'bookmarks',
  };
  static const _secretItems = {
    'privateKey', PortableAppSettings.ipfsKey, PortableAppSettings.stadiaKey,
    BackupAdditionalIdentities.section,
  };

  XFile? _file;
  _ImportedSections? _imported;
  bool _busy = false;
  bool _officialFormat = false;
  String? _notice;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool _available(MeshCoreConnector node, String item) {
    if (_nodeItems.contains(item) &&
        (!node.isSessionReady || node.isOfflineMode || node.isReviewMode)) {
      return false;
    }
    return switch (item) {
      'radioSettings' => node.availableBackupRadioParts.isNotEmpty,
      'contactSettings' => node.canBackupAutoAddConfig,
      'channelFilters' => node.messageFilterService != null,
      BackupFilterTraining.section =>
        MessageHistoryStorage.instance.hasDatabase && node.messageFilterService != null,
      BackupAdditionalIdentities.section => MessageHistoryStorage.instance.hasDatabase,
      _ => true,
    };
  }

  Future<void> _import({bool chooseFile = true}) async {
    if (_busy) return;
    final password = _password.text;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final file = chooseFile ? await widget.pickFile() : _file;
      if (!mounted || file == null) return;
      setState(() {
        _file = file;
        _imported = null;
      });
      final contents = await readBackupJson(file);
      if (!mounted) return;
      final imported = await compute(
        _inspect, (contents: contents, password: password),
      );
      if (!mounted) return;
      setState(() {
        _imported = imported;
        if (imported.invalid.isNotEmpty) {
          _notice = context.l10n.backupRestore_invalidSections;
        } else if (imported.sections.isEmpty) {
          _notice = context.l10n.backupChannels_invalidFile;
        }
      });
    } on BackupPasswordException catch (error) {
      if (mounted) {
        setState(() => _notice = error.rejected
            ? context.l10n.backupChannels_badPassword
            : context.l10n.backupChannels_password);
      }
    } on BackupFileTooLarge {
      if (mounted) setState(() => _notice = context.l10n.backupChannels_fileTooLarge);
    } on FormatException {
      if (mounted) setState(() => _notice = context.l10n.backupChannels_invalidFile);
    } catch (_) {
      if (mounted) setState(() => _notice = context.l10n.backupChannels_readFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(MeshCoreConnector node, Set<String> selection) async {
    // Format filters the output only; it never changes selection controls.
    final items = _officialFormat
        ? selection.where(OfficialBackupExport.items.contains).toSet()
        : selection;
    if (!_busy && items.isEmpty) {
      setState(() => _notice = context.l10n.backupExport_empty);
      return;
    }
    if (_busy || items.isEmpty) return;
    final official = _officialFormat;
    final password = official ? '' : _password.text;
    final l10n = context.l10n;
    if (!official && password.isEmpty && items.any(_secretItems.contains)) {
      setState(() => _notice = l10n.backupRestore_passwordRequired);
      return;
    }
    final app = context.read<AppSettingsService>().settings;
    final session = node.txPowerSession;
    final filter = node.messageFilterService;
    final saveOrigin = shareOriginOf(context);
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      if (password.isNotEmpty && !await _confirmPassword(password)) return;
      if (!mounted) return;
      BackupAdditionalIdentities? keys;
      if (items.contains(BackupAdditionalIdentities.section)) {
        final saved = await MessageHistoryStorage.instance.readAdditionalIdentityVault();
        if (!mounted) return;
        if (saved != null) {
          final vault = await AdditionalIdentityScreen.unlockVault(
            context, allowRemembered: true,
          );
          if (vault == null || !mounted) return;
          keys = BackupAdditionalIdentities(vault.entries);
        }
      }
      final training = items.contains(BackupFilterTraining.section)
          ? await filter?.snapshotTrainingBackup()
          : null;
      if (!mounted) return;
      final settings = {
        for (final item in [
          PortableAppSettings.shared,
          PortableAppSettings.extension,
          ...PortableAppSettings.secretKeys.keys,
        ])
          if (items.contains(item)) item: PortableAppSettings.capture(item, app),
      };
      final display = items.contains(PortableAppSettings.shared)
          ? AppSettingsBackup.capture(app)
          : null;
      final regions = items.contains('regions') ? RegionStore().loadRegions() : null;
      final messageFilter = filter != null && items.contains('channelFilters')
          ? BackupMessageFilter.capture(filter.settings, filter.rules)
          : null;
      final parts = {
        if (items.contains('deviceName')) BackupNodeProfilePart.nodeName,
        if (items.contains('location')) BackupNodeProfilePart.position,
        if (items.contains('privacySettings')) BackupNodeProfilePart.privacy,
        if (items.contains('radioSettings')) ...node.availableBackupRadioParts,
      };
      if (items.any(_nodeItems.contains) &&
          (node.txPowerSession != session || !items.every((item) => _available(node, item)))) {
        setState(() => _notice = l10n.backupExport_notReady);
        return;
      }
      final snapshot = official || items.any(_nodeItems.contains)
          ? await node.snapshotBackup(
              includeChannels: items.contains('channels'),
              includeContacts: items.contains('contacts'),
              includeChannelSettings: items.contains('channelSettings'),
              includeBookmarks: items.contains('bookmarks'),
              includeContactSettings: items.contains('perContactSettings'),
              includeContactGroups: items.contains('contactGroups'),
              includeDiscoveredContacts: items.contains('discoveredContacts'),
              includeCommunities: items.contains('communities'),
              appSettings: display,
              profileParts: parts,
              publicKeySelected: official || items.contains('publicKey'),
              includePrivateKey: items.contains('privateKey'),
              locationPreferences: node.captureBackupLocationPreferences(items, app),
              regions: regions,
              portableSettings: settings,
              messageFilter: messageFilter,
              filterTraining: training,
              additionalIdentities: keys,
            )
          : BackupSnapshot(
              createdAt: DateTime.now(),
              appSettings: display,
              regions: regions,
              portableSettings: settings,
              messageFilter: messageFilter,
              filterTraining: training,
              additionalIdentities: keys,
            );
      if (!mounted) return;
      if (snapshot == null || snapshot.isEmpty) {
        setState(() => _notice =
            snapshot == null ? l10n.backupExport_notReady : l10n.backupExport_empty);
        return;
      }
      final contents = official
          ? await compute(_encodeOfficial, (
              snapshot: snapshot,
              manualAddContacts: items.contains('contactSettings') || items.contains('privacySettings')
                  ? node.backupManualAddContactFlags : null,
              channelRegions: {
                if (items.contains('channels'))
                  for (final channel in node.channels) channel.index: node.getChannelRegion(channel.index),
              },
            ))
          : await compute(_encode, (snapshot: snapshot, password: password));
      if (!mounted) return;
      final saved = await widget.saveFile(
        contents, snapshot.fileName, sharePositionOrigin: saveOrigin,
      );
      if (mounted) {
        setState(() => _notice = switch (saved) {
          BackupJsonSaveResult.saved => l10n.backupExport_saved,
          BackupJsonSaveResult.shareOpened => l10n.backupExport_shared,
          BackupJsonSaveResult.cancelled => null,
        });
      }
    } on BackupFileTooLarge {
      if (mounted) setState(() => _notice = l10n.backupChannels_fileTooLarge);
    } catch (_) {
      if (mounted) setState(() => _notice = l10n.backupExport_failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmPassword(String password) async {
    var matches = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.backupChannels_repeatPassword),
          scrollable: true,
          content: TextField(
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            onChanged: (value) => setDialogState(() => matches = value == password),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.common_cancel),
            ),
            FilledButton(
              onPressed: matches ? () => Navigator.pop(context, true) : null,
              child: Text(context.l10n.common_ok),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  String _restoreTitle(AppLocalizations l10n, BackupRestoreSection section) =>
      switch (section) {
        BackupRestoreSection.nodeProfile => l10n.settings_nodeSettings,
        BackupRestoreSection.nodeIdentity => l10n.backupRestore_privateKey,
        BackupRestoreSection.regions => l10n.settings_regionSettings,
        BackupRestoreSection.locationPreferences => l10n.backupRestore_locationSettings,
        BackupRestoreSection.appSettings => l10n.backupAppSettings_title,
        BackupRestoreSection.portableSettings => l10n.settings_appSettings,
        BackupRestoreSection.contacts => l10n.contacts_title,
        BackupRestoreSection.contactSettings => l10n.backupContactSettings_label,
        BackupRestoreSection.contactGroups => l10n.backupContactGroups_label,
        BackupRestoreSection.bookmarks => l10n.backupRestore_bookmarks,
        BackupRestoreSection.discoveredContacts => l10n.backupDiscoveredContacts_label,
        BackupRestoreSection.channels => l10n.channels_title,
        BackupRestoreSection.channelSettings => l10n.backupChannelSettings_label,
        BackupRestoreSection.communities => l10n.backupCommunities_label,
        BackupRestoreSection.messageFilter => l10n.messageFilter_title,
        BackupRestoreSection.filterTraining => l10n.backupFilterTraining_title,
        BackupRestoreSection.messageHistory => l10n.backupMessageHistory_title,
        BackupRestoreSection.additionalIdentities => l10n.backupRestore_extraKeys,
      };

  Future<void> _restore(
    MeshCoreConnector node,
    BackupRestoreSection section,
    BackupImportPlan plan, {
    String? settingsItem,
  }) async {
    if (_busy) return;
    if (section == BackupRestoreSection.bookmarks) {
      await _restoreBookmarks(node, plan);
      return;
    }
    if (section == BackupRestoreSection.nodeIdentity) {
      await _restoreNodeIdentity(node, plan.nodeIdentity!);
      return;
    }
    final l10n = context.l10n;
    final filter = node.messageFilterService;
    final location = section == BackupRestoreSection.locationPreferences
        ? node.previewBackupLocationPreferences(
            plan.locationPreferences!, context.read<AppSettingsService>().settings,
          )
        : null;
    if (section == BackupRestoreSection.locationPreferences && location == null) {
      setState(() => _notice = l10n.backupExport_notReady);
      return;
    }
    final isLocal = section == BackupRestoreSection.locationPreferences ||
        section == BackupRestoreSection.portableSettings ||
        section == BackupRestoreSection.regions ||
        section == BackupRestoreSection.additionalIdentities;
    if (!isLocal) {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => BackupRestoreScreen.preview(
          plan, section: section, fileName: _file!.name, filter: filter,
        ),
      ));
      return;
    }

    final title = settingsItem == null
        ? _restoreTitle(l10n, section)
        : _settingsTitle(l10n, settingsItem);
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        scrollable: true,
        content: location != null
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text(node.deviceDisplayName),
                ..._locationDetails(location.source),
              ])
            : section == BackupRestoreSection.additionalIdentities
            ? Text(l10n.backupRestore_keysIntro)
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.backupChannels_apply),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      switch (section) {
        case BackupRestoreSection.locationPreferences:
          final result = await node.restoreBackupLocationPreferences(location!);
          if (!result.completed) {
            if (mounted) setState(() => _notice = l10n.backupNodeProfile_unconfirmed(result.count));
            return;
          }
        case BackupRestoreSection.portableSettings:
          final service = context.read<AppSettingsService>();
          final next = plan.portableSettings[settingsItem]!.mergeInto(service.settings);
          await service.updateSettings(next);
        case BackupRestoreSection.regions:
          final regions = {
            ...RegionStore().loadRegions(),
            ...plan.regions!,
          }.toList()..sort();
          await PrefsManager.instance.setStringList(RegionStore.key, regions);
        case BackupRestoreSection.additionalIdentities:
          final vault = await AdditionalIdentityScreen.unlockVault(
            context, allowRemembered: true,
          );
          if (!mounted || vault == null) return;
          await vault.importMissing(plan.additionalIdentities!.entries);
          node.additionalIdentityInbox?.unlock(vault.entries);
        default:
          throw StateError('Invalid local restore section');
      }
      if (mounted) setState(() => _notice = l10n.backupRestore_localApplied);
    } catch (_) {
      if (mounted) setState(() => _notice = l10n.backupAppSettings_failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBookmarks(MeshCoreConnector node, BackupImportPlan plan) async {
    final key = node.storageKeyHex;
    if (key.isEmpty) return;
    final existing = <String>{};
    try {
      existing.addAll((await node.loadBookmarkedMessages()).map((entry) => entry.storageId));
    } on Object {
      if (mounted) setState(() => _notice = context.l10n.bookmarks_saveFailed);
      return;
    }
    if (!mounted || node.storageKeyHex != key) return;
    final additions = {
      for (final entry in plan.bookmarks ?? [])
        if (!existing.contains(entry.storageId)) entry.storageId: entry,
    }.values.toList();
    final l10n = context.l10n;
    final approved = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(l10n.backupRestore_bookmarks), scrollable: true,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(node.deviceDisplayName),
          SizedBox(width: double.maxFinite, height: 320, child: ListView.builder(
            itemCount: additions.length,
            itemBuilder: (_, index) => ListTile(dense: true,
              title: Text(additions[index].sourceName),
              subtitle: Text('${additions[index].senderName}: ${additions[index].text}', maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
          )),
        ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.common_cancel)),
        FilledButton(onPressed: additions.isEmpty ? null : () => Navigator.pop(context, true), child: Text(l10n.backupChannels_apply))],
    ));
    if (approved != true || !mounted || node.storageKeyHex != key) return;
    setState(() => _busy = true);
    try {
      final now = {for (final row in await node.loadBookmarkedMessages()) row.storageId};
      for (final entry in additions) {
        if (now.add(entry.storageId)) {
          await node.setBookmarkedMessage(entry, isBookmarked: true, expectedNodeKey: key);
        }
      }
    } on Object {
      if (mounted) setState(() => _notice = l10n.bookmarks_saveFailed);
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _restoreNodeIdentity(
    MeshCoreConnector node, BackupNodeIdentity source,
  ) async {
    final l10n = context.l10n;
    final preview = node.previewBackupNodeIdentity(source);
    if (preview == null) {
      setState(() => _notice = l10n.backupIdentity_notReady);
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.backupIdentity_confirmTitle),
          scrollable: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.backupIdentity_confirmBody(preview.destinationName)),
              const SizedBox(height: 16),
              Text(l10n.backupIdentity_currentKey),
              SelectableText(preview.destinationKey),
              const SizedBox(height: 12),
              Text(l10n.backupIdentity_backupKey),
              SelectableText(source.publicKey),
            ],
          ),
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
        ),
      );
      if (!mounted || confirmed != true) return;
      final result = await node.restoreBackupNodeIdentity(preview);
      if (!mounted) return;
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _locationDetails(BackupLocationPreferences source) {
    final l10n = context.l10n;
    final labels = {
      'gpsEnabled': l10n.settings_locationGPSEnable,
      'gpsIntervalSeconds': l10n.settings_locationIntervalSec,
      'autoAddChat': l10n.contactsSettings_autoAddUsersTitle,
      'autoAddRepeater': l10n.contactsSettings_autoAddRepeatersTitle,
      'autoAddRoomServer': l10n.contactsSettings_autoAddRoomServersTitle,
      'autoAddSensor': l10n.contactsSettings_autoAddSensorsTitle,
      'overwriteOldest': l10n.contactsSettings_overwriteOldestTitle,
      'maxHops': l10n.backupRestore_autoAddMaxHops,
      'evictDiscoveredContactsEnabled': l10n.contactsSettings_evictDiscoveredContactsTitle,
      'autoSendZeroHopAdvertOnGpsUpdate': l10n.settings_autoZeroHopAdvertOnGpsUpdate,
    };
    final values = {
      ...source.values, ...source.contacts,
      ...?(source.values['privacySettings'] as Map<String, Object?>?),
    }..removeWhere((key, _) => !labels.containsKey(key));
    return [
      for (final entry in values.entries)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(labels[entry.key]!),
          trailing: entry.value is bool
              ? Icon(entry.value == true ? Icons.check : Icons.close)
              : Text('${entry.value}'),
        ),
    ];
  }

  String _settingsTitle(AppLocalizations l10n, String item) => switch (item) {
    PortableAppSettings.extension => l10n.settings_modSettings,
    PortableAppSettings.ipfsKey => l10n.backupRestore_ipfsKey,
    PortableAppSettings.stadiaKey => l10n.backupRestore_stadiaMapKey,
    _ => l10n.settings_appSettings,
  };

  Widget _option(
    MeshCoreConnector node, String item, String title, {String? subtitle}) {
    final available = _available(node, item);
    return CheckboxListTile(
      key: ValueKey('backup-$item'),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: available && _selected.contains(item),
      onChanged: _busy || !available ? null : (checked) => setState(() {
        if (checked == true) {
          _selected.add(item);
        } else {
          _selected.remove(item);
        }
      }),
    );
  }

  Widget _group(String title, IconData icon, List<Widget> children) =>
      ExpansionTile(
        key: PageStorageKey(title),
        initiallyExpanded: true,
        leading: Icon(icon),
        title: Text(title),
        children: children,
      );

  List<Widget> _imports(MeshCoreConnector node, _ImportedSections imported) {
    final l10n = context.l10n;
    final sections = imported.sections;
    return [
      for (final entry in sections.entries)
        if (entry.key == BackupRestoreSection.portableSettings)
          for (final item in entry.value.portableSettings.keys)
            ListTile(
              key: ValueKey('restore-$item'),
              title: Text(_settingsTitle(l10n, item)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null :
                  () => _restore(node, entry.key, entry.value, settingsItem: item),
            )
        else
          ListTile(
            key: ValueKey('restore-${entry.key.name}'),
            title: Text(_restoreTitle(l10n, entry.key)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ||
                (entry.key == BackupRestoreSection.additionalIdentities &&
                    !MessageHistoryStorage.instance.hasDatabase) ||
                ((entry.key == BackupRestoreSection.messageFilter ||
                    entry.key == BackupRestoreSection.filterTraining) &&
                    node.messageFilterService == null) ||
                (entry.key == BackupRestoreSection.messageHistory && kIsWeb)
                ? null : () => _restore(node, entry.key, entry.value),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final node = context.watch<MeshCoreConnector>();
    final selected = _selected.where((item) => _available(node, item)).toSet();
    final imported = _imported;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.backupRestore_title)),
        bottomNavigationBar: _notice == null ? null : SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Semantics(liveRegion: true, child: Text(_notice!)),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              SectionHeader(l10n.backupRestore_import),
              MeshCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _import,
                      icon: const Icon(Icons.upload_file),
                      label: Text(l10n.backupRestore_selectImportFile),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: l10n.backupRestore_password,
                        helperText: l10n.backupExport_passwordHint,
                        helperMaxLines: 4,
                      ),
                    ),
                    if (_file case final file?) ...[
                      const SizedBox(height: 12),
                      Text(file.name),
                      if (imported == null)
                        TextButton(
                          onPressed: _busy ? null : () => _import(chooseFile: false),
                          child: Text(l10n.backupChannels_preview),
                        ),
                    ],
                    if (_busy) const LinearProgressIndicator(),

                  ],
                ),
              ),
              if (imported != null && imported.sections.isNotEmpty) ...[
                SectionHeader(l10n.backupRestore_review),
                MeshCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: _imports(node, imported)),
                ),
              ],
              SectionHeader(l10n.backupRestore_items),
              MeshCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _group(l10n.settings_nodeSettings, Icons.router_outlined, [
                      _option(node, 'deviceName', l10n.settings_nodeName),
                      _option(node, 'privateKey', l10n.backupRestore_privateKey),
                      _option(node, 'publicKey', l10n.settings_infoPublicKey),
                      _option(node, 'radioSettings', l10n.settings_radioSettings),
                      _option(node, 'regions', l10n.settings_regionSettings),
                    ]),
                    const Divider(height: 1),
                    _group(l10n.backupRestore_locationSettings, Icons.place_outlined, [
                      _option(node, 'location', l10n.settings_location),
                      _option(node, 'contactSettings', l10n.settings_contactSettings),
                      _option(node, 'privacySettings', l10n.settings_privacy),
                    ]),
                    const Divider(height: 1),
                    _group(l10n.settings_appSettings, Icons.settings_outlined, [
                      _option(node, PortableAppSettings.shared, l10n.settings_appSettings),
                      _option(node, PortableAppSettings.extension, l10n.settings_modSettings),
                      _option(node, PortableAppSettings.ipfsKey, l10n.backupRestore_ipfsKey),
                      _option(node, PortableAppSettings.stadiaKey, l10n.backupRestore_stadiaMapKey),
                      if (MessageHistoryStorage.instance.hasDatabase)
                        _option(node, BackupAdditionalIdentities.section, l10n.backupRestore_extraKeys),
                    ]),
                    const Divider(height: 1),
                    _group(l10n.contacts_title, Icons.contacts_outlined, [
                      _option(node, 'contacts', l10n.contacts_title),
                      _option(node, 'perContactSettings', l10n.backupContactSettings_label),
                      _option(node, 'contactGroups', l10n.backupContactGroups_label),
                    ]),
                    const Divider(height: 1),
                    _option(node, 'discoveredContacts', l10n.backupDiscoveredContacts_label),
                    _option(node, 'bookmarks', l10n.backupRestore_bookmarks),
                    const Divider(height: 1),
                    _group(l10n.channels_title, Icons.forum_outlined, [
                      _option(node, 'channels', l10n.channels_title),
                      _option(node, 'channelFilters', l10n.messageFilter_title),
                      _option(node, 'channelSettings', l10n.backupChannelSettings_label),
                      _option(node, 'communities', l10n.backupCommunities_label),
                      if (MessageHistoryStorage.instance.hasDatabase)
                        _option(node, BackupFilterTraining.section, l10n.backupFilterTraining_exportTitle),
                    ]),
                    if (!kIsWeb) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(l10n.backupMessageHistory_exportTitle),
                        subtitle: Text(l10n.backupRestore_historySeparate),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy ? null : () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => BackupExportScreen.messageHistory(
                              saveFile: widget.saveFile,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SwitchListTile(
                key: const ValueKey('backup-official-format'),
                title: Text(l10n.backup_officialFormat),
                subtitle: Text(l10n.backup_officialFormatHint,
                  style: Theme.of(context).textTheme.bodySmall),
                value: _officialFormat,
                onChanged: _busy ? null : (value) => setState(() => _officialFormat = value),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: FilledButton.icon(
                  onPressed: _busy || selected.isEmpty ? null : () => _export(node, selected),
                  icon: const Icon(Icons.backup_outlined),
                  label: Text(l10n.backupChannels_createBackup),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }
}
