import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';

final _node = 'ab' * 32;
final _scope = _node.substring(0, 10);
final _first = 'cd' * 32;
final _second = 'ef' * 32;

Future<String> _upstreamBackup(Map<String, Object?> preferences) =>
    const BackupFileCodec().encode({
      'format': BackupFileCodec.payloadFormat,
      'version': BackupFileCodec.formatVersion,
      'sourcePublicKey': _node,
      'items': ['contacts', 'perContactSettings'],
      'sections': {'contacts': {'preferences': preferences}},
    }, password: '');

void main() {
  test('reads scoped options and round-trips explicit false without the contact list', () async {
    final plan = await const BackupImportPlanner().inspect(
      await _upstreamBackup({
        'contacts$_scope': 'unrelated malformed contact list',
        'contact_smaz_$_scope$_first': true,
        'contact_cyr2lat_${_scope}profile_$_first': 'custom',
        'contact_url_images_$_scope$_first': false,
        'contact_url_images_$_scope$_second': 'true',
        'contact_cyr2lat_0123456789$_second': true,
      }),
      password: '',
      contactSettingsOnly: true,
    );
    expect(plan.contacts, isNull);
    expect(plan.contactSettings!.values, {
      (_first, 'smaz_enabled'): '1',
      (_first, 'cyr2lat_profile'): 'custom',
      (_first, 'url_images_enabled'): '0',
    });

    final snapshot = BackupSnapshot(
      sourcePublicKey: _node,
      contactSettings: plan.contactSettings,
      createdAt: DateTime.utc(2026),
    );
    final contents = await snapshot.encode(password: '');
    final payload = await const BackupFileCodec().decode(contents, password: '');
    expect(payload['items'], ['perContactSettings']);
    final roundTrip = await const BackupImportPlanner().inspect(
      contents, password: '', contactSettingsOnly: true,
    );
    expect(roundTrip.contactSettings!.values, plan.contactSettings!.values);
  });

  test('conflicting spellings of a scoped option are rejected', () async {
    final contents = await _upstreamBackup({
      'contact_url_images_$_scope$_first': true,
      'contact_url_images_$_scope${_first.toUpperCase()}': false,
    });
    await expectLater(
      const BackupImportPlanner().inspect(
        contents, password: '', contactSettingsOnly: true,
      ),
      throwsFormatException,
    );
  });
}
