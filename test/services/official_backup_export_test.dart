import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/official_backup_export.dart';
import 'package:meshcore_open/helpers/backup_node_profile.dart';
import 'package:meshcore_open/helpers/portable_app_settings.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';

void main() {
  final nodeKey = '12' * 32;
  test('official document uses native field names, hex secrets and packed-hop widths', () {
    final file = OfficialBackupExport.document(
      publicKey: nodeKey, privateKeyBase64: base64Encode(List.filled(64, 0x56)),
      profile: const BackupNodeProfile(nodeName: 'Test node',
        tuning: (frequencyKHz: 868900, bandwidthHz: 62500, spreadingFactor: 8, codingRate: 8, clientRepeat: null),
        txPowerDbm: 22, position: (latitudeE6: 12345678, longitudeE6: -23456789),
        privacy: (telemetryBase: null, telemetryLocation: null, telemetryEnvironment: null, advertLocation: 0, multiAcks: null)),
      manualAddContacts: 1,
      autoAdd: {'autoAddChat': false, 'autoAddRepeater': true, 'autoAddRoomServer': true,
        'autoAddSensor': false, 'overwriteOldest': true, 'maxHops': 0},
      regions: ['north'], channelRegions: {2: 'north'},
      channels: [{'index': 2, 'name': 'Test', 'psk': base64Encode(List.filled(16, 0x78))}],
      contacts: [
        for (final hops in [-1, 0, 2]) {
          'name': 'Alice', 'publicKey': base64Encode(List.filled(32, 0x34)),
          'type': 1, 'flags': 0, 'latitude': 12.3, 'longitude': null,
          'lastSeen': 1700000000123, 'lastModified': 1700000001999,
          'pathLength': hops, 'pathHashWidth': 2,
          'path': base64Encode(hops > 0 ? [0x10, 0x11, 0x20, 0x21] : []),
        },
      ],
    );
    expect(file.keys.toSet(), {'name', 'public_key', 'private_key', 'radio_settings',
      'position_settings', 'other_settings', 'auto_add_settings', 'channels', 'contacts', 'region_transport_keys'});
    expect(file['private_key'], '56' * 64);
    expect((file['radio_settings'] as Map)['frequency'], 868900);
    expect((file['position_settings'] as Map)['latitude'], '12.345678');
    expect(file['auto_add_settings'], {'auto_add_chat': false, 'auto_add_repeater': true,
      'auto_add_room_server': true, 'auto_add_sensor': false, 'overwrite_oldest': true, 'auto_add_max_hops': 0});
    final channels = file['channels'] as List;
    expect(channels, hasLength(3));
    expect(channels[0]['secret'], '0' * 32);
    expect(channels[2]['secret'], '78' * 16);
    expect(channels[2]['region_scope_key'], (file['region_transport_keys'] as List).single['key']);
    expect((file['contacts'] as List).map((row) => row['out_path_list']), [null, '', '1011,2021']);
    expect((file['contacts'] as List).first['last_advert'], 1700000000);
    expect((file['contacts'] as List).first['last_modified'], 1700000001);
  });

  test('official snapshot round-trips supported sections without Open or MCOa extensions', () async {
    final snapshot = BackupSnapshot(sourcePublicKey: nodeKey, createdAt: DateTime.utc(2026),
      publicKeySelected: true, nodeProfile: const BackupNodeProfile(nodeName: 'Test node'),
      channels: [Channel.fromHex(2, 'Test', '78' * 16)],
      contacts: [Contact(publicKey: Uint8List.fromList(List.filled(32, 0x34)), name: 'Alice',
        type: 1, flags: 0, pathLength: 2, pathHashWidth: 2,
        path: Uint8List.fromList([0x10, 0x11, 0x20, 0x21]), lastSeen: DateTime.utc(2026))],
      portableSettings: {PortableAppSettings.extension:
        PortableAppSettings.capture(PortableAppSettings.extension, AppSettings())},
    );
    final official = snapshot.encodeOfficial();
    final doc = jsonDecode(official) as Map;
    expect(doc.containsKey('format'), isFalse);
    expect(doc.containsKey('sections'), isFalse);
    expect(doc.containsKey('private_key'), isFalse);
    expect(doc.keys.any((key) => key.toString().startsWith('mcoa')), isFalse);
    final imported = await const BackupImportPlanner().inspect(official, password: '');
    expect(imported.isOfficial, isTrue);
    expect(imported.channels!.single.index, 2);
    expect(imported.contacts!.single.path, [0x10, 0x11, 0x20, 0x21]);
    expect(imported.contacts!.single.pathHashWidth, 2);
    final normal = jsonDecode(await snapshot.encode(password: '')) as Map;
    expect(normal['format'], 'meshcore-open-backup');
    expect(normal['sections'], contains(PortableAppSettings.extension));
  });
}
