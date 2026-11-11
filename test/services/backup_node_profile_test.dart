import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
