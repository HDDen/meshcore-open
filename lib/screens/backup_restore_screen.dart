import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/backup_channel_restore.dart';
import '../helpers/backup_channel_settings.dart';
import '../helpers/backup_communities.dart';
import '../helpers/backup_contact_groups.dart';
import '../helpers/backup_contact_settings.dart';
import '../helpers/backup_contact_restore.dart';
import '../helpers/backup_discovered_contacts.dart';
import '../helpers/backup_filter_training.dart';
import '../helpers/backup_message_filter.dart';
import '../helpers/backup_message_history.dart';
import '../helpers/backup_node_profile.dart';
import '../l10n/l10n.dart';
import '../models/app_settings_backup.dart';
import '../models/channel.dart';
import '../models/community.dart';
import '../models/contact.dart';
import '../models/contact_group.dart';
import '../models/message_filter.dart';
import '../services/app_settings_service.dart';
import '../services/backup_file_codec.dart';
import '../services/backup_import_planner.dart';
import '../services/message_filter/message_filter_service.dart';
import '../utils/backup_json_file.dart';

Future<XFile?> _pickBackupFile() =>
    openFile(acceptedTypeGroups: const [backupJsonFileType]);

Future<BackupImportPlan> _inspectBackup(
  ({
    String contents,
    String password,
    bool appSettingsOnly,
    bool messageHistoryOnly,
    bool discoveredContactsOnly,
    bool contactGroupsOnly,
    bool communitiesOnly,
    bool contactSettingsOnly,
    bool channelSettingsOnly,
    bool messageFilterOnly,
    bool filterTrainingOnly,
    bool nodeProfileOnly,
  }) input,
) => const BackupImportPlanner().inspect(
  input.contents,
  password: input.password,
  appSettingsOnly: input.appSettingsOnly,
  messageHistoryOnly: input.messageHistoryOnly,
  discoveredContactsOnly: input.discoveredContactsOnly,
  contactGroupsOnly: input.contactGroupsOnly,
  communitiesOnly: input.communitiesOnly,
  contactSettingsOnly: input.contactSettingsOnly,
  channelSettingsOnly: input.channelSettingsOnly,
  messageFilterOnly: input.messageFilterOnly,
  filterTrainingOnly: input.filterTrainingOnly,
  nodeProfileOnly: input.nodeProfileOnly,
);

Future<String> _readBackupFile(XFile file) async {
  if (await file.length() > backupMaxJsonBytes) throw const BackupFileTooLarge();
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    if (bytes.length + chunk.length > backupMaxJsonBytes) {
      throw const BackupFileTooLarge();
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}

enum _BackupSection {
  channels,
  contacts,
  appSettings,
  messageHistory,
  discoveredContacts,
  contactGroups,
  communities,
  contactSettings,
  channelSettings,
  messageFilter,
  filterTraining,
  nodeProfile,
}

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen.channels({
    super.key,
    this.pickFile = _pickBackupFile,
  }) : _section = _BackupSection.channels, _filter = null;

  const BackupRestoreScreen.nodeProfile({
    super.key,
    this.pickFile = _pickBackupFile,
  }) : _section = _BackupSection.nodeProfile, _filter = null;

  const BackupRestoreScreen.contacts({
    super.key,
    this.pickFile = _pickBackupFile,
  }) : _section = _BackupSection.contacts, _filter = null;

  const BackupRestoreScreen.appSettings({
    super.key,
    this.pickFile = _pickBackupFile,
  }) : _section = _BackupSection.appSettings, _filter = null;

  const BackupRestoreScreen.messageHistory({
    super.key,
    this.pickFile = _pickBackupFile,
  }) : _section = _BackupSection.messageHistory, _filter = null;

  const BackupRestoreScreen.discoveredContacts({
    super.key,
    this.pickFile = _pickBackupFile,
  }) : _section = _BackupSection.discoveredContacts, _filter = null;

  const BackupRestoreScreen.contactGroups({
    super.key,
    this.pickFile = _pickBackupFile,
  }) : _section = _BackupSection.contactGroups, _filter = null;

  const BackupRestoreScreen.communities({
    super.key,
    this.pickFile = _pickBackupFile,
  }) : _section = _BackupSection.communities, _filter = null;

  const BackupRestoreScreen.contactSettings({
    super.key,
    this.pickFile = _pickBackupFile,
  }) : _section = _BackupSection.contactSettings, _filter = null;

  const BackupRestoreScreen.channelSettings({
    super.key,
    this.pickFile = _pickBackupFile,
  }) : _section = _BackupSection.channelSettings, _filter = null;

  const BackupRestoreScreen.messageFilter(
    MessageFilterService filter, {
    super.key,
    this.pickFile = _pickBackupFile,
  }) : _section = _BackupSection.messageFilter, _filter = filter;

  const BackupRestoreScreen.filterTraining(
    MessageFilterService filter, {
    super.key,
    this.pickFile = _pickBackupFile,
  }) : _section = _BackupSection.filterTraining, _filter = filter;

  final Future<XFile?> Function() pickFile;
  final _BackupSection _section;
  final MessageFilterService? _filter;

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
  AppSettingsBackup? _settingsSource;
  AppSettingsBackupPreview? _settingsPreview;
  BackupMessageFilter? _filterSource;
  BackupMessageFilterPreview? _filterPreview;
  BackupFilterTraining? _trainingSource;
  BackupNodeProfile? _nodeProfileSource;
  BackupNodeProfilePreview? _nodeProfilePreview;
  final _selectedNodeProfileParts = <BackupNodeProfilePart>{};
  BackupMessageHistory? _historySource;
  BackupMessageHistoryPreview? _historyPreview;
  String? _discoveredSource;
  BackupDiscoveredContactsPreview? _discoveredPreview;
  List<ContactGroup>? _contactGroupsSource;
  BackupContactGroupsPreview? _contactGroupsPreview;
  List<Community>? _communitiesSource;
  BackupCommunitiesPreview? _communitiesPreview;
  BackupContactSettings? _contactSettingsSource;
  BackupContactSettingsPreview? _contactSettingsPreview;
  BackupChannelSettings? _channelSettingsSource;
  BackupChannelSettingsPreview? _channelSettingsPreview;
  bool _readingLocalLists = false;

  bool get _busy => _reading || _applying || _readingLocalLists;
  bool get _hasSource =>
      _source != null ||
      _contactSource != null ||
      _settingsSource != null ||
      _filterSource != null ||
      _nodeProfileSource != null ||
      _historySource != null ||
      _discoveredSource != null ||
      _contactGroupsSource != null ||
      _communitiesSource != null ||
      _contactSettingsSource != null ||
      _channelSettingsSource != null;

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
        _settingsSource = null;
        _settingsPreview = null;
        _filterSource = null;
        _filterPreview = null;
        _trainingSource = null;
        _nodeProfileSource = null;
        _nodeProfilePreview = null;
        _selectedNodeProfileParts.clear();
        _historySource = null;
        _historyPreview = null;
        _discoveredSource = null;
        _discoveredPreview = null;
        _contactGroupsSource = null;
        _contactGroupsPreview = null;
        _communitiesSource = null;
        _communitiesPreview = null;
        _contactSettingsSource = null;
        _contactSettingsPreview = null;
        _channelSettingsSource = null;
        _channelSettingsPreview = null;
        _notice = null;
      });
      final contents = await _readBackupFile(file);
      final plan = await _inspectWithPassword(contents);
      if (!mounted || plan == null) return;
      final l10n = context.l10n;
      if (widget._section == _BackupSection.nodeProfile) {
        final profile = plan.nodeProfile;
        if (profile == null || profile.isEmpty) {
          setState(() => _notice = l10n.backupNodeProfile_empty);
          return;
        }
        _nodeProfileSource = profile;
      } else if (widget._section == _BackupSection.filterTraining) {
        final training = plan.filterTraining;
        if (training == null || training.isEmpty) {
          setState(() => _notice = l10n.backupFilterTraining_empty);
          return;
        }
        setState(() => _trainingSource = training);
        return;
      } else if (widget._section == _BackupSection.messageFilter) {
        final filter = plan.messageFilter;
        if (filter == null || filter.isEmpty) {
          setState(() => _notice = l10n.backupMessageFilter_empty);
          return;
        }
        _filterSource = filter;
      } else if (widget._section == _BackupSection.channelSettings) {
        final settings = plan.channelSettings;
        if (settings == null || settings.isEmpty) {
          setState(() => _notice = l10n.backupChannelSettings_empty);
          return;
        }
        _channelSettingsSource = settings;
      } else if (widget._section == _BackupSection.contactSettings) {
        final settings = plan.contactSettings;
        if (settings == null || settings.isEmpty) {
          setState(() => _notice = l10n.backupContactSettings_empty);
          return;
        }
        _contactSettingsSource = settings;
      } else if (widget._section == _BackupSection.communities) {
        final communities = plan.communities;
        if (communities == null || communities.isEmpty) {
          setState(() => _notice = l10n.backupCommunities_empty);
          return;
        }
        _communitiesSource = communities;
      } else if (widget._section == _BackupSection.contactGroups) {
        final groups = plan.contactGroups;
        if (groups == null || groups.isEmpty) {
          setState(() => _notice = l10n.backupContactGroups_empty);
          return;
        }
        _contactGroupsSource = groups;
      } else if (widget._section == _BackupSection.discoveredContacts) {
        final discovered = plan.discoveredContactsJson;
        if (discovered == null || discovered == '[]') {
          setState(() => _notice = l10n.discoveredContacts_importNoContacts);
          return;
        }
        _discoveredSource = discovered;
      } else if (widget._section == _BackupSection.messageHistory) {
        final history = plan.messageHistory;
        if (history == null) {
          setState(() => _notice = l10n.backupMessageHistory_empty);
          return;
        }
        _historySource = history;
      } else if (widget._section == _BackupSection.appSettings) {
        final settings = plan.appSettings;
        if (settings == null) {
          setState(() => _notice = l10n.backupAppSettings_noSupported);
          return;
        }
        _settingsSource = settings;
      } else if (widget._section == _BackupSection.contacts) {
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
      await _refreshPreview();
    } on BackupFileTooLarge {
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
          (
            contents: contents,
            password: password,
            appSettingsOnly: widget._section == _BackupSection.appSettings,
            messageHistoryOnly: widget._section == _BackupSection.messageHistory,
            discoveredContactsOnly: widget._section == _BackupSection.discoveredContacts,
            contactGroupsOnly: widget._section == _BackupSection.contactGroups,
            communitiesOnly: widget._section == _BackupSection.communities,
            contactSettingsOnly: widget._section == _BackupSection.contactSettings,
            channelSettingsOnly: widget._section == _BackupSection.channelSettings,
            messageFilterOnly: widget._section == _BackupSection.messageFilter,
            filterTrainingOnly: widget._section == _BackupSection.filterTraining,
            nodeProfileOnly: widget._section == _BackupSection.nodeProfile,
          ),
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

  Future<void> _refreshPreview() async {
    if (_filterSource case final source?) {
      final filter = widget._filter!;
      setState(() {
        _filterPreview = source.preview(filter.settings, filter.rules);
        _notice = null;
      });
      return;
    }
    if (_channelSettingsSource case final source?) {
      final connector = context.read<MeshCoreConnector>();
      setState(() {
        _readingLocalLists = true;
        _channelSettingsPreview = null;
        _notice = null;
      });
      try {
        final preview = await connector.previewBackupChannelSettings(source);
        if (!mounted) return;
        setState(() {
          _channelSettingsPreview = preview;
          _destinationName = connector.deviceDisplayName;
        });
      } catch (_) {
        if (mounted) setState(() => _notice = context.l10n.backupChannelSettings_failed);
      } finally {
        if (mounted) setState(() => _readingLocalLists = false);
      }
      return;
    }
    if (_communitiesSource case final source?) {
      final connector = context.read<MeshCoreConnector>();
      setState(() {
        _readingLocalLists = true;
        _communitiesPreview = null;
        _notice = null;
      });
      try {
        final preview = await connector.previewBackupCommunities(source);
        if (!mounted) return;
        setState(() {
          _communitiesPreview = preview;
          _destinationName = connector.deviceDisplayName;
        });
      } catch (_) {
        if (mounted) {
          setState(() => _notice = context.l10n.backupCommunities_failed);
        }
      } finally {
        if (mounted) setState(() => _readingLocalLists = false);
      }
      return;
    }
    if (_contactGroupsSource case final source?) {
      final connector = context.read<MeshCoreConnector>();
      setState(() {
        _readingLocalLists = true;
        _contactGroupsPreview = null;
        _notice = null;
      });
      try {
        final preview = await connector.previewBackupContactGroups(source);
        if (!mounted) return;
        setState(() {
          _contactGroupsPreview = preview;
          _destinationName = connector.deviceDisplayName;
        });
      } catch (_) {
        if (mounted) {
          setState(() => _notice = context.l10n.backupContactGroups_failed);
        }
      } finally {
        if (mounted) setState(() => _readingLocalLists = false);
      }
      return;
    }
    if (_settingsSource case final source?) {
      final settings = context.read<AppSettingsService>().settings;
      setState(() {
        _settingsPreview = source.preview(settings);
        _notice = null;
      });
      return;
    }
    final channels = _source;
    final contactSource = _contactSource;
    final connector = context.read<MeshCoreConnector>();
    setState(() {
      if (_nodeProfileSource case final profile?) {
        _nodeProfilePreview = connector.previewBackupNodeProfile(profile);
        _selectedNodeProfileParts.clear();
      }
      if (channels != null) {
        _preview = connector.previewBackupChannelRestore(channels);
      }
      if (contactSource != null) {
        _contactPreview = connector.previewBackupContactRestore(
          sourcePublicKey: contactSource.nodeKey,
          contacts: contactSource.contacts,
        );
      }
      if (_historySource case final history?) {
        _historyPreview = connector.previewBackupMessageHistory(history);
      }
      if (_discoveredSource case final discovered?) {
        _discoveredPreview = connector.previewBackupDiscoveredContacts(discovered);
      }
      if (_contactSettingsSource case final settings?) {
        _contactSettingsPreview = connector.previewBackupContactSettings(settings);
      }
      _destinationName = connector.deviceDisplayName;
      _notice = null;
    });
  }

  Future<void> _confirmRestore({
    required String title,
    required String prompt,
    required String failure,
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
      if (mounted) setState(() => _notice = failure);
    } finally {
      if (mounted) {
        setState(() {
          _applying = false;
          _preview = null;
          _contactPreview = null;
          _settingsPreview = null;
          _filterPreview = null;
          _nodeProfilePreview = null;
          _selectedNodeProfileParts.clear();
          _historyPreview = null;
          _discoveredPreview = null;
          _contactGroupsPreview = null;
          _communitiesPreview = null;
          _contactSettingsPreview = null;
          _channelSettingsPreview = null;
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
      failure: l10n.backupChannels_applyFailed,
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
      failure: l10n.backupContacts_applyFailed,
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

  Future<void> _restoreAppSettings(AppSettingsBackupPreview preview) {
    final service = context.read<AppSettingsService>();
    final l10n = context.l10n;
    final count = preview.changes.length;
    return _confirmRestore(
      title: l10n.backupAppSettings_title,
      prompt: l10n.backupAppSettings_confirm(count),
      failure: l10n.backupAppSettings_failed,
      apply: () async {
        final restored = await service.restoreAppSettingsBackup(preview);
        return restored
            ? l10n.backupAppSettings_applied(count)
            : l10n.backupAppSettings_changed;
      },
    );
  }

  Future<void> _restoreMessageHistory(BackupMessageHistoryPreview preview) {
    final connector = context.read<MeshCoreConnector>();
    final l10n = context.l10n;
    return _confirmRestore(
      title: l10n.backupMessageHistory_title,
      prompt: l10n.backupMessageHistory_confirm(_destinationName!, preview.count),
      failure: l10n.backupMessageHistory_failed,
      apply: () async {
        final added = await connector.restoreBackupMessageHistory(preview);
        return added == null
            ? l10n.backupMessageHistory_waitForNode
            : l10n.backupMessageHistory_applied(added);
      },
    );
  }

  Future<void> _restoreMessageFilter(BackupMessageFilterPreview preview) {
    final filter = widget._filter!;
    final l10n = context.l10n;
    return _confirmRestore(
      title: l10n.backupMessageFilter_title,
      prompt: l10n.backupMessageFilter_confirm,
      failure: l10n.backupMessageFilter_failed,
      apply: () async => await filter.restoreBackup(preview)
          ? l10n.backupMessageFilter_applied
          : l10n.backupMessageFilter_changed,
    );
  }

  Future<void> _restoreFilterTraining(BackupFilterTraining training) {
    final filter = widget._filter!;
    final l10n = context.l10n;
    return _confirmRestore(
      title: l10n.backupFilterTraining_title,
      prompt: l10n.backupFilterTraining_confirm,
      failure: l10n.backupFilterTraining_failed,
      apply: () async {
        final added = await filter.restoreTrainingBackup(training);
        if (mounted) setState(() => _trainingSource = null);
        return l10n.backupFilterTraining_applied(added);
      },
    );
  }

  Future<void> _restoreNodeProfile(BackupNodeProfilePreview preview) {
    final connector = context.read<MeshCoreConnector>();
    final l10n = context.l10n;
    final selected = Set<BackupNodeProfilePart>.of(_selectedNodeProfileParts);
    return _confirmRestore(
      title: l10n.backupNodeProfile_title,
      prompt: l10n.backupNodeProfile_confirm(_destinationName!, selected.length),
      failure: l10n.backupNodeProfile_failed,
      apply: () async {
        final result = await connector.restoreBackupNodeProfile(preview, selected);
        return switch (result.status) {
          BackupNodeProfileStatus.completed => l10n.backupNodeProfile_applied(result.confirmed),
          BackupNodeProfileStatus.destinationChanged => l10n.backupNodeProfile_changed(result.confirmed),
          BackupNodeProfileStatus.writeUnconfirmed => l10n.backupNodeProfile_unconfirmed(result.confirmed),
        };
      },
    );
  }

  List<Widget> _nodeProfileChoices(BackupNodeProfilePreview preview) {
    final l10n = context.l10n;
    final changes = preview.changes;
    Widget option(BackupNodeProfilePart part, String title, Widget subtitle) =>
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: subtitle,
          value: _selectedNodeProfileParts.contains(part),
          onChanged: _busy ? null : (checked) => setState(() {
            if (checked == true) {
              _selectedNodeProfileParts.add(part);
            } else {
              _selectedNodeProfileParts.remove(part);
            }
          }),
        );
    String policy(int? mode) => switch (mode) {
      0 => l10n.settings_denyAll,
      1 => l10n.settings_allowByContact,
      2 => l10n.settings_allowAll,
      _ => '$mode',
    };
    Widget privacyDetails(BackupNodePrivacy privacy) {
      final before = preview.before.privacy!;
      final details = <(String, String)>[
        if (privacy.telemetryBase != before.telemetryBase)
          (l10n.settings_telemetryBaseMode, policy(privacy.telemetryBase)),
        if (privacy.telemetryLocation != before.telemetryLocation)
          (l10n.settings_telemetryLocationMode, policy(privacy.telemetryLocation)),
        if (privacy.telemetryEnvironment != before.telemetryEnvironment)
          (l10n.settings_telemetryEnvironmentMode, policy(privacy.telemetryEnvironment)),
        if (privacy.advertLocation != before.advertLocation)
          (l10n.settings_advertLocation, privacy.advertLocation == 1
              ? l10n.backupAppSettings_enabled : l10n.backupAppSettings_disabled),
        if (privacy.multiAcks != before.multiAcks)
          (l10n.settings_multiAck, '${privacy.multiAcks}'),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final (label, value) in details) Text('$label · $value')],
      );
    }

    Widget tuningDetails(BackupRadioTuning tuning) => Text(
      '${(tuning.frequencyKHz / 1000).toStringAsFixed(3)} MHz · '
      '${tuning.bandwidthHz / 1000} kHz · SF${tuning.spreadingFactor} · '
      'CR 4/${tuning.codingRate}'
      '${switch (tuning.clientRepeat) {
        true => '\n${l10n.settings_clientRepeat} · ${l10n.backupAppSettings_enabled}',
        false => '\n${l10n.settings_clientRepeat} · ${l10n.backupAppSettings_disabled}',
        null => '',
      }}',
    );

    return [
      if (changes.nodeName case final name?)
        option(BackupNodeProfilePart.nodeName, l10n.settings_nodeName, Text(name)),
      if (changes.position case final position?)
        option(BackupNodeProfilePart.position, l10n.settings_location, Text(
          '${(position.latitudeE6 / 1000000).toStringAsFixed(6)}, '
          '${(position.longitudeE6 / 1000000).toStringAsFixed(6)}',
        )),
      if (changes.privacy case final privacy?)
        option(BackupNodeProfilePart.privacy, l10n.settings_privacy, privacyDetails(privacy)),
      if (changes.tuning case final tuning?)
        option(BackupNodeProfilePart.tuning, l10n.settings_radioSettings, tuningDetails(tuning)),
      if (changes.txPowerDbm case final power?)
        option(BackupNodeProfilePart.txPower, l10n.settings_txPower, Text('$power dBm')),
      if (changes.pathHashByteWidth case final width?)
        option(BackupNodeProfilePart.pathHashWidth, l10n.repeater_pathHashMode, Text(switch (width) {
          1 => l10n.repeater_pathHashModeOption0,
          2 => l10n.repeater_pathHashModeOption1,
          _ => l10n.repeater_pathHashModeOption2,
        })),
      if (preview.unavailable.isNotEmpty)
        Text(l10n.backupNodeProfile_radioUnavailable([
          if (preview.unavailable.contains(BackupNodeProfilePart.tuning)) l10n.settings_radioSettings,
          if (preview.unavailable.contains(BackupNodeProfilePart.txPower)) l10n.settings_txPower,
          if (preview.unavailable.contains(BackupNodeProfilePart.pathHashWidth)) l10n.repeater_pathHashMode,
        ].join(', '))),
    ];
  }

  Future<void> _restoreDiscoveredContacts(
    BackupDiscoveredContactsPreview preview,
  ) {
    final connector = context.read<MeshCoreConnector>();
    final l10n = context.l10n;
    return _confirmRestore(
      title: l10n.backupDiscoveredContacts_title,
      prompt: l10n.backupDiscoveredContacts_confirm(preview.contacts.length),
      failure: l10n.backupDiscoveredContacts_failed,
      apply: () async {
        final added = await connector.restoreBackupDiscoveredContacts(preview);
        return added == null
            ? l10n.backupDiscoveredContacts_changed
            : l10n.discoveredContacts_imported(added);
      },
    );
  }

  Future<void> _restoreContactGroups(BackupContactGroupsPreview preview) {
    final connector = context.read<MeshCoreConnector>();
    final l10n = context.l10n;
    return _confirmRestore(
      title: l10n.backupContactGroups_title,
      prompt: l10n.backupContactGroups_confirm(_destinationName!, preview.added.length),
      failure: l10n.backupContactGroups_failed,
      apply: () async {
        final added = await connector.restoreBackupContactGroups(preview);
        return added == null
            ? l10n.backupContactGroups_changed
            : l10n.backupContactGroups_applied(added);
      },
    );
  }

  Future<void> _restoreCommunities(BackupCommunitiesPreview preview) {
    final connector = context.read<MeshCoreConnector>();
    final l10n = context.l10n;
    return _confirmRestore(
      title: l10n.backupCommunities_title,
      prompt: l10n.backupCommunities_confirm(_destinationName!, preview.added.length),
      failure: l10n.backupCommunities_failed,
      apply: () async {
        final added = await connector.restoreBackupCommunities(preview);
        return added == null
            ? l10n.backupCommunities_changed
            : l10n.backupCommunities_applied(added);
      },
    );
  }

  Future<void> _restoreContactSettings(BackupContactSettingsPreview preview) {
    final connector = context.read<MeshCoreConnector>();
    final l10n = context.l10n;
    return _confirmRestore(
      title: l10n.backupContactSettings_title,
      prompt: l10n.backupContactSettings_confirm(
        _destinationName!, preview.additions.values.length,
      ),
      failure: l10n.backupContactSettings_failed,
      apply: () async {
        final added = await connector.restoreBackupContactSettings(preview);
        return added == null
            ? l10n.backupContactSettings_changed
            : l10n.backupContactSettings_applied(added);
      },
    );
  }

  Future<void> _restoreChannelSettings(BackupChannelSettingsPreview preview) {
    final connector = context.read<MeshCoreConnector>();
    final l10n = context.l10n;
    return _confirmRestore(
      title: l10n.backupChannelSettings_title,
      prompt: l10n.backupChannelSettings_confirm(_destinationName!, preview.count),
      failure: l10n.backupChannelSettings_failed,
      apply: () async {
        final result = await connector.restoreBackupChannelSettings(preview);
        if (result == null) return l10n.backupChannelSettings_changed;
        return result.completed
            ? l10n.backupChannelSettings_applied(result.count)
            : l10n.backupChannelSettings_partial(result.count);
      },
    );
  }

  ListTile _settingsChange(MapEntry<String, Object?> change) {
    final l10n = context.l10n;
    final label = switch (change.key) {
      'theme_mode' => l10n.appSettings_theme,
      'language_override' => l10n.appSettings_language,
      'unit_system' => l10n.appSettings_unitsTitle,
      'ui_scale' => l10n.settings_modSettingsDPIchange,
      'ui_scale_apply_to_icons' => l10n.settings_modSettingsDPIchangeToIcons,
      'enable_time_seconds' => l10n.appSettings_enableTimeSeconds,
      'show_keyboard_hiding_button' => l10n.appSettings_showKeyboardHidingButton,
      'jump_to_oldest_unread' => l10n.appSettings_jumpToOldestUnread,
      'show_hops' => l10n.chat_showHops,
      'show_channel_preview_sender' => l10n.settings_modSettingsShowChannelPreviewSender,
      'channels_unread_sorting' => l10n.settings_modSettingsVisualChannelsUnreadSorting,
      'monochrome_sender_names' => l10n.settings_modSettingsMonochromeSenderNames,
      'show_last_hop_signal' => l10n.settings_modSettingsLastHopSignal,
      'region_on_hops_line' => l10n.appSettings_regionOnHopsLine,
      _ => change.key,
    };
    final value = switch ((change.key, change.value)) {
      ('theme_mode', 'system') => l10n.appSettings_themeSystem,
      ('theme_mode', 'dark') => l10n.appSettings_themeDark,
      ('theme_mode', 'light') => l10n.appSettings_themeLight,
      ('language_override', null) => l10n.appSettings_languageSystem,
      ('unit_system', 'metric') => l10n.appSettings_unitsMetric,
      ('unit_system', 'imperial') => l10n.appSettings_unitsImperial,
      ('ui_scale', final double scale) => '${(scale * 100).round()}%',
      (_, true) => l10n.backupAppSettings_enabled,
      (_, false) => l10n.backupAppSettings_disabled,
      (_, final value) => value.toString(),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value),
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
    final settingsPreview = _settingsPreview;
    final filterPreview = _filterPreview;
    final training = _trainingSource;
    final nodeProfile = _nodeProfilePreview;
    final historyPreview = _historyPreview;
    final discoveredPreview = _discoveredPreview;
    final groupsPreview = _contactGroupsPreview;
    final communitiesPreview = _communitiesPreview;
    final contactSettingsPreview = _contactSettingsPreview;
    final channelSettingsPreview = _channelSettingsPreview;
    final (title, intro) = switch (widget._section) {
      _BackupSection.channels => (l10n.backupChannels_title, l10n.backupChannels_intro),
      _BackupSection.contacts => (l10n.backupContacts_title, l10n.backupContacts_intro),
      _BackupSection.appSettings => (l10n.backupAppSettings_title, l10n.backupAppSettings_scope),
      _BackupSection.messageFilter => (l10n.backupMessageFilter_title, l10n.backupMessageFilter_scope),
      _BackupSection.filterTraining => (l10n.backupFilterTraining_title, l10n.backupFilterTraining_scope),
      _BackupSection.nodeProfile => (l10n.backupNodeProfile_title, l10n.backupNodeProfile_intro),
      _BackupSection.messageHistory => (
        l10n.backupMessageHistory_title,
        l10n.backupMessageHistory_intro,
      ),
      _BackupSection.discoveredContacts => (
        l10n.backupDiscoveredContacts_title,
        l10n.backupDiscoveredContacts_intro,
      ),
      _BackupSection.contactGroups => (
        l10n.backupContactGroups_title,
        l10n.backupContactGroups_intro,
      ),
      _BackupSection.communities => (
        l10n.backupCommunities_title,
        l10n.backupCommunities_intro,
      ),
      _BackupSection.contactSettings => (
        l10n.backupContactSettings_title,
        l10n.backupContactSettings_intro,
      ),
      _BackupSection.channelSettings => (
        l10n.backupChannelSettings_title,
        l10n.backupChannelSettings_intro,
      ),
    };
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
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(intro),
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
              else if (_hasSource &&
                  widget._section != _BackupSection.appSettings &&
                  widget._section != _BackupSection.messageFilter &&
                  preview == null &&
                  contactPreview == null &&
                  historyPreview == null &&
                  discoveredPreview == null &&
                  groupsPreview == null &&
                  communitiesPreview == null &&
                  contactSettingsPreview == null &&
                  channelSettingsPreview == null &&
                  nodeProfile == null &&
                  !_readingLocalLists)
                Text(switch (widget._section) {
                  _BackupSection.contacts => l10n.backupContacts_waitForNode,
                  _BackupSection.messageHistory => l10n.backupMessageHistory_waitForNode,
                  _BackupSection.discoveredContacts => l10n.backupContacts_waitForNode,
                  _BackupSection.contactGroups => l10n.backupContactGroups_waitForNode,
                  _BackupSection.communities => l10n.backupContacts_waitForNode,
                  _BackupSection.contactSettings => l10n.backupContacts_waitForNode,
                  _BackupSection.nodeProfile => l10n.backupContacts_waitForNode,
                  _ => l10n.backupChannels_waitForNode,
                }),
              if (preview != null || contactPreview != null ||
                  historyPreview != null || groupsPreview != null ||
                  communitiesPreview != null || contactSettingsPreview != null ||
                  channelSettingsPreview != null || nodeProfile != null)
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
              if (settingsPreview != null)
                if (settingsPreview.changes.isEmpty)
                  Text(l10n.backupAppSettings_noChanges)
                else ...[
                  for (final change in settingsPreview.changes.entries)
                    _settingsChange(change),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _restoreAppSettings(settingsPreview),
                    child: Text(l10n.backupChannels_apply),
                  ),
                ],
              if (nodeProfile != null) ...[
                ..._nodeProfileChoices(nodeProfile),
                if (nodeProfile.changes.isEmpty && nodeProfile.unavailable.isEmpty)
                  Text(l10n.backupNodeProfile_noChanges)
                else if (!nodeProfile.changes.isEmpty)
                  FilledButton(
                    onPressed: _busy || _selectedNodeProfileParts.isEmpty
                        ? null : () => _restoreNodeProfile(nodeProfile),
                    child: Text(l10n.backupChannels_apply),
                  ),
              ],
              if (training != null) ...[
                Text(l10n.backupFilterTraining_summary(
                  training.count(FilterTrainingKind.spam),
                  training.count(FilterTrainingKind.notSpam),
                  training.count(FilterTrainingKind.ordinary),
                )),
                FilledButton(
                  onPressed: _busy ? null : () => _restoreFilterTraining(training),
                  child: Text(l10n.backupChannels_apply),
                ),
              ],
              if (filterPreview != null) ...[
                if (filterPreview.isEmpty)
                  Text(l10n.backupMessageFilter_noChanges)
                else ...[
                  Text(l10n.backupMessageFilter_summary(
                    filterPreview.addedRules.length,
                    filterPreview.changedSettings,
                  )),
                  FilledButton(
                    onPressed: _busy ? null : () => _restoreMessageFilter(filterPreview),
                    child: Text(l10n.backupChannels_apply),
                  ),
                ],
              ],
              if (historyPreview != null) ...[
                Text(l10n.backupMessageHistory_summary(
                  historyPreview.count,
                  historyPreview.skipped,
                )),
                if (historyPreview.count > 0)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _restoreMessageHistory(historyPreview),
                    child: Text(l10n.backupChannels_apply),
                  ),
              ],
              if (discoveredPreview != null) ...[
                Text(l10n.backupDiscoveredContacts_summary(
                  discoveredPreview.contacts.length,
                  discoveredPreview.skipped,
                  discoveredPreview.invalid,
                  discoveredPreview.noRoom,
                )),
                if (discoveredPreview.contacts.isNotEmpty)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _restoreDiscoveredContacts(discoveredPreview),
                    child: Text(l10n.backupChannels_apply),
                  ),
              ],
              if (groupsPreview != null) ...[
                Text(l10n.backupContactGroups_summary(
                  groupsPreview.added.length,
                  groupsPreview.skipped,
                )),
                if (groupsPreview.added.isNotEmpty)
                  FilledButton(
                    onPressed: _busy ? null : () => _restoreContactGroups(groupsPreview),
                    child: Text(l10n.backupChannels_apply),
                  ),
              ],
              if (communitiesPreview != null) ...[
                Text(l10n.backupCommunities_summary(
                  communitiesPreview.added.length,
                  communitiesPreview.skipped,
                )),
                for (final community in communitiesPreview.added)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(community.name),
                  ),
                if (communitiesPreview.added.isNotEmpty)
                  FilledButton(
                    onPressed: _busy ? null : () => _restoreCommunities(communitiesPreview),
                    child: Text(l10n.backupChannels_apply),
                  ),
              ],
              if (contactSettingsPreview != null) ...[
                Text(l10n.backupContactSettings_summary(
                  contactSettingsPreview.additions.values.length,
                  contactSettingsPreview.skipped,
                )),
                if (!contactSettingsPreview.additions.isEmpty)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _restoreContactSettings(contactSettingsPreview),
                    child: Text(l10n.backupChannels_apply),
                  ),
              ],
              if (channelSettingsPreview != null) ...[
                Text(l10n.backupChannelSettings_summary(
                  channelSettingsPreview.count,
                  channelSettingsPreview.skipped,
                )),
                if (channelSettingsPreview.order.isNotEmpty)
                  Text(l10n.backupChannelSettings_includesOrder),
                if (channelSettingsPreview.count > 0)
                  FilledButton(
                    onPressed: _busy ? null : () => _restoreChannelSettings(channelSettingsPreview),
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
