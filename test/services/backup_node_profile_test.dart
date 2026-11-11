import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/backup_node_profile.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';

final _key = 'a1' * 32;

void main() {
  test('reads only supported fields from the official node profile', () async {
    final plan = await const BackupImportPlanner().inspect(
      jsonEncode({
        'public_key': _key,
        'private_key': 'ignored in this restore',
        'name': 'Репитер',
        'position_settings': {'latitude': 55.1234567, 'longitude': -37.1},
        'other_settings': {'advert_location_policy': 1},
        'radio_settings': {'frequency': 869495},
      }),
      password: '', nodeProfileOnly: true,
    );
    final profile = plan.nodeProfile!;
    expect(plan.sourcePublicKey, _key);
    expect(profile.nodeName, 'Репитер');
    expect(profile.position, (latitudeE6: 55123457, longitudeE6: -37100000));
    expect(BackupNodeProfile.privacyValues(profile.privacy!), {'advertLocation': 1});

    final snapshot = BackupSnapshot(
      sourcePublicKey: _key,
      nodeProfile: profile,
      createdAt: DateTime.utc(2026),
    );
    final contents = await snapshot.encode(password: '');
    final decoded = await const BackupFileCodec().decode(contents, password: '');
    expect(decoded['items'], ['deviceName', 'location', 'privacySettings']);
    expect(contents, isNot(contains('private_key')));
    final v1 = await const BackupImportPlanner().inspect(
      contents, password: '', nodeProfileOnly: true,
    );
    expect(v1.nodeProfile!.position, profile.position);
    expect(v1.nodeProfile!.privacy, profile.privacy);
  });

  test('radio fields round trip in the upstream v1 section', () async {
    final profile = BackupNodeProfile.fromBackup(radio: {
      'frequencyHz': 869495,
      'bandwidthHz': 125000,
      'spreadingFactor': 7,
      'codingRate': 5,
      'clientRepeat': false,
      'txPowerDbm': -2,
      'pathHashByteWidth': 3,
    });
    final snapshot = BackupSnapshot(
      sourcePublicKey: _key,
      nodeProfile: profile,
      createdAt: DateTime.utc(2026),
    );
    final contents = await snapshot.encode(password: '');
    final decoded = await const BackupFileCodec().decode(contents, password: '');
    expect(decoded['items'], ['radioSettings']);
    expect(decoded['sections'], {
      'nodeSettings': {'radio': profile.radioValues},
    });
    final plan = await const BackupImportPlanner().inspect(
      contents, password: '', nodeProfileOnly: true,
    );
    expect(plan.nodeProfile!.radioValues, profile.radioValues);
  });

  test('official radio settings normalize frequency and omit unknown options', () async {
    for (final frequency in [869495, 869495000, 869.495, '869495']) {
      final plan = await const BackupImportPlanner().inspect(
        jsonEncode({
          'public_key': _key,
          'position_settings': {'latitude': '47.5', 'longitude': '7.8'},
          'radio_settings': {
            'frequency': frequency,
            'bandwidth': 125000,
            'spreading_factor': 7,
            'coding_rate': 5,
            'tx_power': 14,
          },
        }),
        password: '', nodeProfileOnly: true,
      );
      expect(plan.nodeProfile!.position, (latitudeE6: 47500000, longitudeE6: 7800000));
      expect(plan.nodeProfile!.radioValues, {
        'frequencyHz': 869495,
        'bandwidthHz': 125000,
        'spreadingFactor': 7,
        'codingRate': 5,
        'txPowerDbm': 14,
      });
    }
  });

  test('upstream scope names derive a key and an explicit empty value clears it', () {
    final old = BackupNodeProfile.fromBackup(radio: {'defaultFloodScope': '#uk'});
    expect(old.defaultFloodScope, (
      name: 'uk', keyHex: pubKeyToHex(floodScopeKeyForRegion('uk')),
    ));
    final clear = BackupNodeProfile.fromBackup(radio: {'defaultFloodScope': ''});
    expect(clear.defaultFloodScope, emptyDefaultFloodScope);
    expect(clear.radioValues, {'defaultFloodScope': ''});
    final absent = BackupNodeProfile.fromBackup(radio: {'defaultFloodScope': null});
    expect(absent.defaultFloodScope, isNull);
    expect(absent.radioValues, isEmpty);
  });

  test('rejects malformed scopes instead of deriving another key or clearing them', () {
    for (final radio in [
      {'defaultFloodScopeKey': 'a1' * 16},
      {'defaultFloodScope': '', 'defaultFloodScopeKey': 'a1' * 16},
      {'defaultFloodScope': 'uk', 'defaultFloodScopeKey': 'a1'},
      {'defaultFloodScope': 'uk', 'defaultFloodScopeKey': 'gg' * 16},
      {'defaultFloodScope': 'uk', 'defaultFloodScopeKey': 1},
      {'defaultFloodScope': 'я' * 16},
      {'defaultFloodScope': 'uk\u0000extra'},
      {'defaultFloodScope': '#'},
      {'defaultFloodScope': '   '},
    ]) {
      expect(() => BackupNodeProfile.fromBackup(radio: radio), throwsFormatException);
    }
  });

  test('rejects out-of-range radio fields and a malformed repeat flag', () {
    const radio = {
      'frequencyHz': 869495,
      'bandwidthHz': 125000,
      'spreadingFactor': 7,
      'codingRate': 5,
    };
    for (final invalid in [
      {'frequencyHz': 149999},
      {'bandwidthHz': 125.5},
      {'spreadingFactor': 13},
      {'codingRate': 9},
      {'clientRepeat': 'true'},
      {'txPowerDbm': 128},
      {'pathHashByteWidth': 4},
    ]) {
      expect(
        () => BackupNodeProfile.fromBackup(radio: {...radio, ...invalid}),
        throwsFormatException,
      );
    }
  });

  test('rejects names beyond the firmware byte limit and invalid coordinates', () async {
    for (final fields in [
      {'name': 'Я' * 16},
      {'position_settings': {'latitude': 91, 'longitude': 0}},
      {'position_settings': {'latitude': 12}},
    ]) {
      await expectLater(
        const BackupImportPlanner().inspect(
          jsonEncode({'public_key': _key, ...fields}),
          password: '', nodeProfileOnly: true,
        ),
        throwsFormatException,
      );
    }
  });
}
