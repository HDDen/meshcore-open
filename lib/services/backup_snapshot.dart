import 'dart:convert';

import '../connector/meshcore_protocol.dart';
import '../helpers/backup_additional_identities.dart';
import '../helpers/backup_channel_settings.dart';
import '../helpers/backup_contact_settings.dart';
import '../helpers/backup_filter_training.dart';
import '../helpers/backup_message_filter.dart';
import '../helpers/backup_node_profile.dart';
import '../helpers/backup_location_preferences.dart';
import '../helpers/portable_app_settings.dart';
import '../helpers/official_backup_export.dart';
import '../models/app_settings_backup.dart';
import '../models/channel.dart';
import '../models/community.dart';
import '../models/contact.dart';
import '../models/contact_group.dart';
import '../models/bookmarked_message.dart';
import 'backup_file_codec.dart';

/// Immutable selected data from the active profile and, optionally, its node.
class BackupSnapshot {
  BackupSnapshot({
    String? sourcePublicKey,
    this.nodeName,
    Iterable<Channel>? channels,
    BackupChannelSettings? channelSettings,
    Iterable<Contact>? contacts,
    Iterable<ContactGroup>? contactGroups,
    BackupContactSettings? contactSettings,
    Iterable<Community>? communities,
    Iterable<BookmarkedMessage>? bookmarks,
    String? discoveredContactsJson,
    AppSettingsBackup? appSettings,
    BackupMessageFilter? messageFilter,
    BackupFilterTraining? filterTraining,
    BackupNodeProfile? nodeProfile,
    this.publicKeySelected = false,
    this.nodePrivateKey,
    this.locationPreferences,
    this.regions,
    this.portableSettings = const {},
    this.additionalIdentities,
    required DateTime createdAt,
  }) : sourcePublicKey =
           channels == null && channelSettings == null && contacts == null &&
               contactGroups == null && discoveredContactsJson == null &&
               communities == null && bookmarks == null && contactSettings == null && nodeProfile == null &&
               !publicKeySelected && nodePrivateKey == null && locationPreferences == null
           ? ''
           : sourcePublicKey?.toLowerCase() ?? '',
       createdAt = createdAt.toUtc(),
       _appSettings = appSettings?.isEmpty == true ? null : appSettings,
       _messageFilter = messageFilter?.isEmpty == true ? null : messageFilter,
       _filterTraining = filterTraining?.isEmpty == true ? null : filterTraining,
       _nodeProfile = nodeProfile?.isEmpty == true ? null : nodeProfile,
       _contactSettings = contactSettings?.isEmpty == true ? null : contactSettings,
       _channelSettings = channelSettings?.isEmpty == true ? null : channelSettings,
       _historyRows = null,
       _sections = {
         if (bookmarks != null) 'bookmarks': [for (final bookmark in bookmarks) bookmark.toJson()],
         if (channels != null) 'channels': _channelRows(channels),
         if (contacts != null) 'contacts': _contactRows(contacts),
         if (communities != null)
           'communities': [
             for (final community in communities)
               {
                 ...community.toJson(),
                 'hashtag_channels': List<String>.of(community.hashtagChannels),
               },
           ],
         if (contactGroups != null)
           'contactGroups': [
             for (final group in contactGroups)
               {'name': group.name, 'members': List<String>.of(group.memberKeys)},
           ],
         if (discoveredContactsJson != null)
           'discoveredContacts': [
             for (final row in jsonDecode(discoveredContactsJson) as List<dynamic>)
               Map<String, Object?>.from(row as Map),
           ],
       } {
    if (_hasNodeData &&
        (this.sourcePublicKey.length != pubKeySize * 2 ||
            _nonHex.hasMatch(this.sourcePublicKey))) {
      throw const FormatException('Invalid backup source key');
    }
    if (_sections.isEmpty && _appSettings == null &&
        contactSettings == null && channelSettings == null && messageFilter == null &&
        filterTraining == null && nodeProfile == null &&
        !publicKeySelected && nodePrivateKey == null && locationPreferences == null && regions == null &&
        portableSettings.isEmpty && additionalIdentities == null) {
      throw const FormatException('No selected backup sections');
    }
  }

  BackupSnapshot.messageHistory({
    required String sourcePublicKey,
    required this.nodeName,
    required Map<String, List<String>> rows,
    required DateTime createdAt,
  }) : sourcePublicKey = sourcePublicKey.toLowerCase(),
       createdAt = createdAt.toUtc(),
       _sections = const {},
       _appSettings = null,
       publicKeySelected = false,
       nodePrivateKey = null,
       locationPreferences = null,
       regions = null,
       portableSettings = const {},
       additionalIdentities = null,
       _messageFilter = null,
       _filterTraining = null,
       _nodeProfile = null,
       _contactSettings = null,
       _channelSettings = null,
       _historyRows = Map<String, List<String>>.unmodifiable({
         for (final entry in rows.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       }) {
    if (sourcePublicKey.length != pubKeySize * 2 ||
        _nonHex.hasMatch(sourcePublicKey)) {
      throw const FormatException('Invalid backup source key');
    }
  }

  static final _nonHex = RegExp(r'[^0-9a-fA-F]');
  static final _invalidFileNameChars = RegExp(r'[\x00-\x1f<>:"/\\|?*]+');
  final String sourcePublicKey;
  final String? nodeName;
  final DateTime createdAt;
  final Map<String, List<Map<String, Object?>>> _sections;
  final AppSettingsBackup? _appSettings;
  final bool publicKeySelected;
  final String? nodePrivateKey;
  final BackupLocationPreferences? locationPreferences;
  final List<String>? regions;
  final Map<String, PortableAppSettings> portableSettings;
  final BackupAdditionalIdentities? additionalIdentities;

  bool get requiresPassword => nodePrivateKey != null ||
      additionalIdentities != null ||
      portableSettings.keys.any(PortableAppSettings.secretKeys.containsKey);
  final BackupMessageFilter? _messageFilter;
  final BackupFilterTraining? _filterTraining;
  final BackupNodeProfile? _nodeProfile;
  final BackupContactSettings? _contactSettings;
  final BackupChannelSettings? _channelSettings;
  final Map<String, List<String>>? _historyRows;

  bool get isEmpty =>
      _historyRows?.isEmpty ??
      (_appSettings == null && _contactSettings == null && _channelSettings == null &&
          _messageFilter == null && _filterTraining == null && _nodeProfile == null &&
          !publicKeySelected && nodePrivateKey == null && (locationPreferences?.isEmpty ?? true) &&
          (regions?.isEmpty ?? true) &&
          portableSettings.values.every((section) => section.isEmpty) &&
          (additionalIdentities?.entries.isEmpty ?? true) &&
          _sections.values.every((rows) => rows.isEmpty));
  bool get _hasNodeData =>
      _sections.isNotEmpty || _contactSettings != null || _channelSettings != null ||
      _nodeProfile != null || publicKeySelected || nodePrivateKey != null ||
      locationPreferences?.isEmpty == false;
  List<String> get _items => [
    ..._sections.keys,
    if (_contactSettings != null) 'perContactSettings',
    if (_channelSettings != null) 'channelSettings',
    if (_appSettings != null) AppSettingsBackup.section,
    if (_messageFilter != null) BackupMessageFilter.section,
    if (_filterTraining != null) BackupFilterTraining.section,
    if (_nodeProfile != null) 'node-profile',
  ];
  int get channelCount => _sections['channels']?.length ?? 0;
  bool get containsCommunityKeys => _sections['communities']?.isNotEmpty ?? false;

  String get fileName {
    final safeName = (nodeName ?? '').replaceAll(_invalidFileNameChars, '-').trim();
    final stem = String.fromCharCodes(safeName.runes.take(40)).trim();
    final stamp = createdAt.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final items = _items;
    final kind = _historyRows != null
        ? 'history'
        : !_hasNodeData
        ? switch (items.singleOrNull) {
            BackupMessageFilter.section => 'message-filter',
            BackupFilterTraining.section => 'filter-training',
            _ => 'settings',
          }
        : items.length == 1
        ? switch (items.single) {
            'perContactSettings' => 'contact-settings',
            'channelSettings' => 'channel-settings',
            final name => name,
          }
        : 'backup';
    final name = ['meshcore-$kind', if (stem.isNotEmpty) stem, stamp].join('-');
    return '$name.json';
  }

  /// Official files are plaintext JSON, including a private key only when selected.
  String encodeOfficial({int? manualAddContacts, Map<int, String> channelRegions = const {}}) {
    final document = OfficialBackupExport.document(
      publicKey: sourcePublicKey, profile: _nodeProfile,
      privateKeyBase64: nodePrivateKey,
      contacts: _sections['contacts'], channels: _sections['channels'],
      autoAdd: locationPreferences?.contacts ?? const {},
      manualAddContacts: manualAddContacts,
      regions: regions, channelRegions: channelRegions,
    );
    final contents = const JsonEncoder.withIndent('  ').convert(document);
    if (utf8.encode(contents).length > backupMaxJsonBytes) {
      throw const BackupFileTooLarge();
    }
    return contents;
  }

  Future<String> encode({required String password}) async {
    if (requiresPassword && password.isEmpty) {
      throw const BackupPasswordException.required();
    }
    if (_historyRows case final rows?) {
      return _encodeHistory(rows, password);
    }
    final scope = _hasNodeData ? sourcePublicKey.substring(0, 10) : '';
    final preferences = <String, Map<String, Object?>>{};
    for (final entry in _sections.entries) {
      final (section, prefix) = switch (entry.key) {
        'bookmarks' => ('discoveredContacts', 'message_bookmarks_'),
        'contactGroups' => ('contacts', 'contact_groups'),
        'communities' => ('channels', 'communities_v1'),
        'discoveredContacts' => ('discoveredContacts', 'discovered_contacts'),
        final name => (name, name),
      };
      // An empty list is a JSON string for upstream preferences.
      (preferences[section] ??= {})['$prefix$scope'] =
          entry.value.isEmpty ? '[]' : entry.value;
    }
    final items = [..._sections.keys];
    void addSettings(
      String item,
      String section,
      String extension,
      Map<String, Object?> upstream,
      Map<String, Object?> fork,
    ) {
      if (upstream.isNotEmpty) {
        items.add(item);
        (preferences[section] ??= {}).addAll(upstream);
      }
      if (fork.isNotEmpty) {
        items.add(extension);
        preferences[extension] = fork;
      }
    }
    if (_contactSettings case final settings?) {
      addSettings('perContactSettings', 'contacts', BackupContactSettings.extensionSection,
        settings.toPreferences(scope), settings.toPreferences(scope, forkOnly: true));
    }
    if (_channelSettings case final settings?) {
      addSettings('channelSettings', 'channels', BackupChannelSettings.extensionSection,
        settings.toPreferences(scope), settings.toPreferences(scope, forkOnly: true));
    }
    if (_appSettings != null) items.add(AppSettingsBackup.section);
    if (_messageFilter case final filter?) {
      items.add(BackupMessageFilter.section);
      preferences[BackupMessageFilter.section] = filter.toPreferences();
    }
    if (_filterTraining case final training?) {
      items.add(BackupFilterTraining.section);
      preferences[BackupFilterTraining.section] = training.toPreferences();
    }
    final profile = _nodeProfile;
    final name = profile?.nodeName;
    final position = profile?.position;
    final privacy = profile?.privacy;
    final radio = profile?.radioValues;
    final hasRadio = radio != null && radio.isNotEmpty;
    if (name != null) items.add('deviceName');
    if (position != null) items.add('location');
    if (privacy != null) items.add('privacySettings');
    items.addAll(locationPreferences?.items ?? const []);
    if (hasRadio) items.add('radioSettings');
    if (publicKeySelected || nodePrivateKey != null) items.add('publicKey');
    if (nodePrivateKey != null) items.add('privateKey');
    if (regions != null) items.add('regions');
    final extensionSettings = portableSettings[PortableAppSettings.extension];
    final sharedSettings = <String, Object?>{};
    for (final entry in portableSettings.entries) {
      if (entry.value.isEmpty) continue;
      items.add(entry.key);
      if (entry.key != PortableAppSettings.extension) {
        sharedSettings.addAll(entry.value.values);
      }
    }
    final keys = additionalIdentities;
    if (keys != null && keys.entries.isNotEmpty) {
      items.add(BackupAdditionalIdentities.section);
    }
    final contents = await const BackupFileCodec().encode({
      'format': BackupFileCodec.payloadFormat,
      'version': BackupFileCodec.formatVersion,
      'createdAt': createdAt.toIso8601String(),
      'sourcePublicKey': sourcePublicKey,
      'items': items.toSet().toList(),
      'sections': {
        for (final section in preferences.entries)
          section.key: {'preferences': section.value},
        if (_appSettings case final settings?)
          AppSettingsBackup.section: {
            'preferences': {'app_settings': settings.toJson()},
          },
        if (sharedSettings.isNotEmpty)
          PortableAppSettings.shared: {
            'preferences': {'app_settings': sharedSettings},
          },
        if (extensionSettings != null && !extensionSettings.isEmpty)
          PortableAppSettings.extension: {
            'preferences': {'app_settings': extensionSettings.values},
          },
        if (keys != null && keys.entries.isNotEmpty)
          BackupAdditionalIdentities.section: {'entries': keys.toJson()},
        if (name != null || hasRadio || publicKeySelected ||
            nodePrivateKey != null || regions != null)
          'nodeSettings': {
            'name': ?name,
            if (hasRadio) 'radio': radio,
            if (publicKeySelected || nodePrivateKey != null)
              'publicKey': sourcePublicKey,
            'privateKey': ?nodePrivateKey,
            if (regions != null) 'preferences': {'regions': regions},
          },
        if (position != null || privacy != null || locationPreferences?.isEmpty == false)
          'locationSettings': {
            ...?locationPreferences?.values,
            if (position != null) 'location': {
              'latitude': position.latitudeE6 / 1000000,
              'longitude': position.longitudeE6 / 1000000,
            },
            if (privacy != null) 'privacySettings': {
              ...?(locationPreferences?.values['privacySettings'] as Map<String, Object?>?),
              ...BackupNodeProfile.privacyValues(privacy),
            },
          },
      },
    }, password: password);
    if (utf8.encode(contents).length > backupMaxJsonBytes) {
      throw const BackupFileTooLarge();
    }
    return contents;
  }

  Future<String> _encodeHistory(
    Map<String, List<String>> rows,
    String password,
  ) async {
    final direct = <String, Object?>{};
    final channels = <String, Object?>{};
    for (final entry in rows.entries) {
      final isDirect = entry.key.startsWith('messages_');
      final messages = [
        for (final row in entry.value) jsonDecode(row) as Map<String, dynamic>,
      ];
      int timelineAt(Map<String, dynamic> row) =>
          (!isDirect ? row['receivedAt'] as int? : null) ??
          (row['timestamp'] as int? ?? 0);
      messages.sort((a, b) {
        final time = timelineAt(a).compareTo(timelineAt(b));
        return time != 0
            ? time
            : (a['messageId'] as String).compareTo(b['messageId'] as String);
      });
      (isDirect ? direct : channels)[entry.key] = messages;
    }
    final contents = await const BackupFileCodec().encode({
      'format': BackupFileCodec.payloadFormat,
      'version': BackupFileCodec.formatVersion,
      'createdAt': createdAt.toIso8601String(),
      'sourcePublicKey': sourcePublicKey,
      'items': [
        if (direct.isNotEmpty) 'contactHistory',
        if (channels.isNotEmpty) 'channelHistory',
      ],
      'sections': {
        if (direct.isNotEmpty) 'contacts': {'preferences': direct},
        if (channels.isNotEmpty) 'channels': {'preferences': channels},
      },
    }, password: password, compact: true);
    if (utf8.encode(contents).length > backupMaxJsonBytes) {
      throw const BackupFileTooLarge();
    }
    return contents;
  }

  static bool _validName(String name) =>
      !name.contains('\u0000') && utf8.encode(name).length < maxNameSize;

  static List<Map<String, Object?>> _channelRows(Iterable<Channel> channels) {
    final usedSlots = <int>{};
    final rows = <Map<String, Object?>>[];
    final ordered = channels.where((channel) => !channel.isEmpty).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    for (final channel in ordered) {
      if (channel.index < 0 ||
          channel.index > 255 ||
          !usedSlots.add(channel.index) ||
          !_validName(channel.name) ||
          channel.psk.length != 16 ||
          channel.psk.every((byte) => byte == 0)) {
        throw const FormatException('Invalid channel in backup snapshot');
      }
      rows.add({
        'index': channel.index,
        'name': channel.name,
        'psk': base64Encode(channel.psk),
        'unreadCount': 0,
      });
    }
    return rows;
  }

  static List<Map<String, Object?>> _contactRows(Iterable<Contact> contacts) {
    final rows = <Map<String, Object?>>[];
    final keys = <String>{};
    for (final contact in contacts) {
      final pathLength = contact.pathLength;
      final width = contact.pathHashWidth;
      final path = contact.path;
      if (contact.publicKey.length != pubKeySize ||
          !keys.add(contact.publicKeyHex) ||
          !_validName(contact.name) ||
          contact.type < 0 ||
          contact.type > 255 ||
          contact.flags < 0 ||
          contact.flags > 255 ||
          pathLength < -1 ||
          pathLength > 63 ||
          width < 1 ||
          width > maxPathHashWidth ||
          path.length > maxPathSize ||
          path.length != (pathLength < 0 ? 0 : pathLength * width)) {
        throw const FormatException('Invalid contact in backup snapshot');
      }
      final hasAdvertLocation = contact.telemetryFixAt == null &&
          contact.hasLocation;
      rows.add({
        'publicKey': base64Encode(contact.publicKey),
        'name': contact.name,
        'type': contact.type,
        'flags': contact.flags,
        'pathLength': pathLength,
        'pathHashWidth': width,
        'path': base64Encode(path),
        'latitude': hasAdvertLocation ? contact.latitude : null,
        'longitude': hasAdvertLocation ? contact.longitude : null,
        'lastSeen': contact.lastSeen.millisecondsSinceEpoch,
        'lastModified': contact.lastModified?.millisecondsSinceEpoch,
      });
    }
    return rows;
  }
}
