import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/backup_additional_identities.dart';
import 'package:meshcore_open/helpers/backup_node_profile.dart';
import 'package:meshcore_open/helpers/backup_location_preferences.dart';
import 'package:meshcore_open/helpers/portable_app_settings.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/services/additional_identity_vault.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';

void main() {
  const planner = BackupImportPlanner();
  final nodeKey = 'ab' * 32;
  final now = DateTime.utc(2026, 11, 14);

  test('combined backup keeps upstream v1 names and fork settings separate', () async {
    final settings = AppSettings(
      themeMode: 'dark',
      suppressPhantomChannels: false,
      uploadIpfsApiKey: 'never include this by default',
    );
    final snapshot = BackupSnapshot(
      sourcePublicKey: nodeKey,
      nodeProfile: const BackupNodeProfile(nodeName: 'Test node'),
      channels: [Channel.fromHex(2, 'Public', Channel.publicChannelPsk)],
      publicKeySelected: true,
      regions: ['bots'],
      portableSettings: {
        for (final item in [PortableAppSettings.shared, PortableAppSettings.extension])
          item: PortableAppSettings.capture(item, settings),
      },
      createdAt: now,
    );
    final encoded = await snapshot.encode(password: '');
    final file = jsonDecode(encoded) as Map<String, dynamic>;
    final sections = file['sections'] as Map<String, dynamic>;
    expect(file['format'], 'meshcore-open-backup');
    expect(file['version'], 1);
    expect(file['items'], containsAll([
      'deviceName', 'publicKey', 'regions', 'channels', 'appSettings',
    ]));
    expect(sections['nodeSettings']['publicKey'], nodeKey);
    expect(sections['nodeSettings']['preferences']['regions'], ['bots']);
    final shared = sections['appSettings']['preferences']['app_settings'] as Map;
    expect(shared['theme_mode'], 'dark');
    expect(shared, isNot(containsPair('suppress_phantom_channels', false)));
    expect(encoded, isNot(contains(settings.uploadIpfsApiKey)));

    final imported = await planner.inspectSections(encoded, password: '');
    expect(imported.invalid, isEmpty);
    expect(imported.sections[BackupRestoreSection.channels]!.channels!.single.index, 2);
    expect(imported.sections[BackupRestoreSection.regions]!.regions, ['bots']);
    final portable = imported.sections[BackupRestoreSection.portableSettings]!.portableSettings;
    final local = AppSettings(uploadIpfsApiKey: 'local credential');
    final restored = portable[PortableAppSettings.extension]!.mergeInto(
      portable[PortableAppSettings.shared]!.mergeInto(local),
    );
    expect(restored.suppressPhantomChannels, isFalse);
    expect(restored.themeMode, 'dark');
    expect(restored.uploadIpfsApiKey, 'local credential');
  });

  test('an unreadable channel section leaves the node profile available', () async {
    final snapshot = BackupSnapshot(
      sourcePublicKey: nodeKey,
      channels: [Channel.fromHex(2, 'Public', Channel.publicChannelPsk)],
      nodeProfile: const BackupNodeProfile(nodeName: 'Test node'),
      createdAt: now,
    );
    final file = jsonDecode(await snapshot.encode(password: '')) as Map<String, dynamic>;
    file['sections']['channels']['preferences']['channels${nodeKey.substring(0, 10)}'] =
        'invalid data';
    final imported = await planner.inspectSections(jsonEncode(file), password: '');
    expect(imported.invalid, {BackupRestoreSection.channels});
    expect(imported.sections[BackupRestoreSection.nodeProfile]!.nodeProfile!.nodeName,
        'Test node');
  });

  test('location settings preserve upstream names and privacy together', () async {
    final location = BackupLocationPreferences.read({
      'gpsEnabled': true, 'gpsIntervalSeconds': 90,
      'contactSettings': {'autoAddRepeater': true, 'maxHops': 2},
      'privacySettings': {'autoSendZeroHopAdvertOnGpsUpdate': true},
    }, {'location', 'contactSettings', 'privacySettings'});
    final snapshot = BackupSnapshot(
      sourcePublicKey: nodeKey, createdAt: now, locationPreferences: location,
      nodeProfile: const BackupNodeProfile(privacy: (
        telemetryBase: 0, telemetryLocation: 1, telemetryEnvironment: 0,
        advertLocation: 1, multiAcks: 0,
      )),
    );
    expect(location.contacts, {'autoAddRepeater': true, 'maxHops': 2});
    expect(location.values['privacySettings'], isA<Map<String, Object?>>());
    expect(() => location.contacts['maxHops'] = 3, throwsUnsupportedError);
    final contents = await snapshot.encode(password: '');
    final file = jsonDecode(contents) as Map<String, dynamic>;
    expect(file['items'], containsAll(['location', 'contactSettings', 'privacySettings']));
    expect((file['items'] as List).toSet().length, (file['items'] as List).length);
    final section = file['sections']['locationSettings'] as Map;
    expect(section['contactSettings']['autoAddRepeater'], isTrue);
    expect(section['privacySettings']['telemetryLocation'], 1);
    expect(section['privacySettings']['autoSendZeroHopAdvertOnGpsUpdate'], isTrue);
    final imported = await planner.inspectSections(contents, password: '');
    expect(imported.invalid, isEmpty);
    final restored = imported.sections[BackupRestoreSection.locationPreferences]!.locationPreferences!;
    expect(restored.fingerprint, location.fingerprint);
    expect(imported.sections[BackupRestoreSection.nodeProfile]!.nodeProfile!.privacy!.advertLocation, 1);
  });

  test('invalid GPS interval leaves unrelated sections available', () async {
    final file = {
      'format': BackupFileCodec.payloadFormat, 'version': 1,
      'sourcePublicKey': nodeKey,
      'items': ['location', 'deviceName'],
      'sections': {
        'nodeSettings': {'name': 'Usable node'},
        'locationSettings': {'gpsEnabled': true, 'gpsIntervalSeconds': 86400},
      },
    };
    final imported = await planner.inspectSections(jsonEncode(file), password: '');
    expect(imported.invalid, {BackupRestoreSection.locationPreferences});
    expect(imported.sections[BackupRestoreSection.nodeProfile]!.nodeProfile!.nodeName, 'Usable node');
  });

  test('malformed fork fields keep shared settings and node profile available', () async {
    final file = {
      'format': BackupFileCodec.payloadFormat, 'version': 1,
      'sourcePublicKey': nodeKey,
      'items': ['deviceName', PortableAppSettings.shared, PortableAppSettings.extension],
      'sections': {
        'nodeSettings': {'name': 'Usable node'},
        PortableAppSettings.shared: {
          'preferences': {'app_settings': {'theme_mode': 'dark'}},
        },
        PortableAppSettings.extension: {
          'preferences': {'app_settings': {'suppress_phantom_channels': 'invalid'}},
        },
      },
    };
    final imported = await planner.inspectSections(jsonEncode(file), password: '');
    expect(imported.invalid, {BackupRestoreSection.portableSettings});
    expect(imported.sections[BackupRestoreSection.portableSettings]!.portableSettings.keys,
        [PortableAppSettings.shared]);
    expect(imported.sections[BackupRestoreSection.nodeProfile]!.nodeProfile!.nodeName, 'Usable node');
  });

  test('additional keys require encryption and keep their original identity', () async {
    final entry = await AdditionalIdentityEntry.parse(
      'Test key',
      '307c83864f2833cb427a2ef1c00a013cfdff2768d980c0a3a520f006904de94f'
      '9b4f0afe280b746a778684e75442502057b7473a03f08f96f5a38e9287e01f8f',
    );
    final snapshot = BackupSnapshot(
      additionalIdentities: BackupAdditionalIdentities([entry]), createdAt: now,
    );
    await expectLater(snapshot.encode(password: ''), throwsA(isA<BackupPasswordException>()));
    const password = 'test password';
    final encrypted = await snapshot.encode(password: password);
    expect(encrypted, isNot(contains(entry.identity.privateKeyHex)));
    final imported = await planner.inspectSections(encrypted, password: password);
    final restored = imported.sections[BackupRestoreSection.additionalIdentities]!
        .additionalIdentities!.entries.single;
    expect(restored.name, entry.name);
    expect(restored.identity.publicKeyHex, entry.identity.publicKeyHex);
    expect(restored.identity.privateKeyHex, entry.identity.privateKeyHex);

    final payload = await const BackupFileCodec().decode(encrypted, password: password);
    final plaintext = await planner.inspectSections(jsonEncode(payload), password: '');
    expect(plaintext.invalid, {BackupRestoreSection.additionalIdentities});
    expect(plaintext.sections, isEmpty);
  });
}
