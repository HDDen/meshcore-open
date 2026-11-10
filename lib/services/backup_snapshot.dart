import 'dart:convert';

import '../connector/meshcore_protocol.dart';
import '../models/app_settings_backup.dart';
import '../models/channel.dart';
import '../models/contact.dart';
import 'backup_file_codec.dart';

/// Immutable selected data from the active profile and, optionally, its node.
class BackupSnapshot {
  BackupSnapshot({
    String? sourcePublicKey,
    this.nodeName,
    Iterable<Channel>? channels,
    Iterable<Contact>? contacts,
    AppSettingsBackup? appSettings,
    required DateTime createdAt,
  }) : sourcePublicKey = channels == null && contacts == null
           ? ''
           : sourcePublicKey?.toLowerCase() ?? '',
       createdAt = createdAt.toUtc(),
       _appSettings = appSettings?.isEmpty == true ? null : appSettings,
       _sections = {
         if (channels != null) 'channels': _channelRows(channels),
         if (contacts != null) 'contacts': _contactRows(contacts),
       } {
    if (_sections.isNotEmpty &&
        (this.sourcePublicKey.length != pubKeySize * 2 ||
            _nonHex.hasMatch(this.sourcePublicKey))) {
      throw const FormatException('Invalid backup source key');
    }
    if (_sections.isEmpty && _appSettings == null) {
      throw const FormatException('No selected backup sections');
    }
  }

  static final _nonHex = RegExp(r'[^0-9a-fA-F]');
  static final _invalidFileNameChars = RegExp(r'[\x00-\x1f<>:"/\\|?*]+');
  final String sourcePublicKey;
  final String? nodeName;
  final DateTime createdAt;
  final Map<String, List<Map<String, Object?>>> _sections;
  final AppSettingsBackup? _appSettings;

  bool get isEmpty =>
      _appSettings == null && _sections.values.every((rows) => rows.isEmpty);
  int get channelCount => _sections['channels']?.length ?? 0;

  String get fileName {
    final safeName = (nodeName ?? '').replaceAll(_invalidFileNameChars, '-').trim();
    final stem = String.fromCharCodes(safeName.runes.take(40)).trim();
    final stamp = createdAt.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final kind = _sections.isEmpty
        ? 'settings'
        : _sections.length == 1 && _appSettings == null
        ? _sections.keys.single
        : 'backup';
    final name = ['meshcore-$kind', if (stem.isNotEmpty) stem, stamp].join('-');
    return '$name.json';
  }

  Future<String> encode({required String password}) {
    final scope = _sections.isEmpty ? '' : sourcePublicKey.substring(0, 10);
    return const BackupFileCodec().encode({
      'format': BackupFileCodec.payloadFormat,
      'version': BackupFileCodec.formatVersion,
      'createdAt': createdAt.toIso8601String(),
      'sourcePublicKey': sourcePublicKey,
      'items': [
        ..._sections.keys,
        if (_appSettings != null) AppSettingsBackup.section,
      ],
      'sections': {
        for (final section in _sections.entries)
          section.key: {
            // An empty list is a JSON string for upstream preferences.
            'preferences': {
              '${section.key}$scope':
                  section.value.isEmpty ? '[]' : section.value,
            },
          },
        if (_appSettings case final settings?)
          AppSettingsBackup.section: {
            'preferences': {'app_settings': settings.values},
          },
      },
    }, password: password);
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
