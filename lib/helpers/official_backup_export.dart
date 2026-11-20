import 'dart:convert';

import '../connector/meshcore_protocol.dart';
import 'backup_node_profile.dart';

/// Official MeshCore configuration JSON, independent of the Open v1 envelope.
abstract final class OfficialBackupExport {
  static const items = {
    'deviceName', 'publicKey', 'privateKey', 'radioSettings', 'regions',
    'location', 'privacySettings', 'contactSettings', 'contacts', 'channels',
  };

  static Map<String, Object?> document({
    required String publicKey,
    BackupNodeProfile? profile,
    String? privateKeyBase64,
    List<Map<String, Object?>>? contacts,
    List<Map<String, Object?>>? channels,
    Map<String, Object?> autoAdd = const {},
    int? manualAddContacts,
    List<String>? regions,
    Map<int, String> channelRegions = const {},
  }) {
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(publicKey)) {
      throw const FormatException('Official backup requires a node public key');
    }
    String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    String regionKey(String name) => name.startsWith(r'$') &&
        RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(name.substring(1))
        ? name.substring(1).toLowerCase() : hex(floodScopeKeyForRegion(name));
    bool scoped(String name) => name.isNotEmpty && name != '!unscoped';
    Map<String, Object?> channel(Map<String, Object?>? row) {
      final region = row == null ? '' : channelRegions[row['index']] ?? '';
      return {
        'name': row?['name'] ?? '',
        'secret': row == null ? '0' * 32 : hex(base64Decode(row['psk'] as String)),
        'region_scope_name': scoped(region) ? region.replaceFirst(RegExp(r'^#'), '') : null,
        'region_scope_key': scoped(region) ? regionKey(region) : null,
        'message_retention_duration_seconds': null,
      };
    }
    String? path(Map<String, Object?> row) {
      if ((row['pathLength'] as int) < 0) return null;
      final bytes = base64Decode(row['path'] as String);
      final width = row['pathHashWidth'] as int;
      return [for (var i = 0; i < bytes.length; i += width)
        hex(bytes.sublist(i, i + width))].join(',');
    }
    final radio = profile?.tuning;
    final position = profile?.position;
    final advert = profile?.privacy?.advertLocation;
    final bySlot = {for (final row in channels ?? <Map<String, Object?>>[]) row['index'] as int: row};
    final slots = bySlot.keys.toList()..sort();
    final regionNames = <String>{...?regions,
      for (final name in channelRegions.values) if (scoped(name)) name};
    return {
      'name': ?profile?.nodeName,
      'public_key': publicKey.toLowerCase(),
      if (privateKeyBase64 != null) 'private_key': hex(base64Decode(privateKeyBase64)),
      if (radio != null || profile?.txPowerDbm != null) 'radio_settings': {
        if (radio != null) ...{
          'frequency': radio.frequencyKHz,
          'bandwidth': radio.bandwidthHz,
          'spreading_factor': radio.spreadingFactor,
          'coding_rate': radio.codingRate,
        },
        'tx_power': ?profile?.txPowerDbm,
      },
      if (position != null) 'position_settings': {
        'latitude': (position.latitudeE6 / 1000000).toString(),
        'longitude': (position.longitudeE6 / 1000000).toString(),
      },
      if (manualAddContacts != null || advert != null) 'other_settings': {
        'manual_add_contacts': ?manualAddContacts,
        'advert_location_policy': ?advert,
      },
      if (autoAdd.isNotEmpty) 'auto_add_settings': {
        for (final entry in const {
          'autoAddChat': 'auto_add_chat', 'autoAddRepeater': 'auto_add_repeater',
          'autoAddRoomServer': 'auto_add_room_server', 'autoAddSensor': 'auto_add_sensor',
          'overwriteOldest': 'overwrite_oldest', 'maxHops': 'auto_add_max_hops',
        }.entries)
          if (autoAdd.containsKey(entry.key)) entry.value: autoAdd[entry.key],
      },
      if (channels != null) 'channels': [
        for (var i = 0; i <= (slots.isEmpty ? -1 : slots.last); i++) channel(bySlot[i]),
      ],
      if (contacts != null) 'contacts': [
        for (final row in contacts) {
          'type': row['type'], 'name': row['name'], 'custom_name': null,
          'public_key': hex(base64Decode(row['publicKey'] as String)),
          'flags': row['flags'],
          'latitude': row['latitude']?.toString() ?? '0',
          'longitude': row['longitude']?.toString() ?? '0',
          'last_advert': (row['lastSeen'] as int) ~/ 1000,
          'last_modified': ((row['lastModified'] ?? row['lastSeen']) as int) ~/ 1000,
          'out_path_list': path(row),
        },
      ],
      if (regions != null || channelRegions.isNotEmpty) 'region_transport_keys': [
        for (final name in regionNames) if (scoped(name)) {
          'name': name.replaceFirst(RegExp(r'^#'), ''), 'key': regionKey(name),
        },
      ],
    };
  }
}
