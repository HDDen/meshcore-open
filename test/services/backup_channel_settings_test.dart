import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/backup_channel_settings.dart';
import 'package:meshcore_open/helpers/backup_contact_settings.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';
import 'package:meshcore_open/storage/region_store.dart';

final _node = 'ab' * 32;
final _scope = _node.substring(0, 10);
final _first = Channel.fromHex(2, 'First', '01' * 16);
final _second = Channel.fromHex(7, 'Second', '02' * 16);

void main() {
  test('reads v1 channel settings and order without interpreting slot keys', () async {
    final id = _first.storageId!;
    final second = _second.storageId!;
    final contents = await const BackupFileCodec().encode({
      'format': BackupFileCodec.payloadFormat,
      'version': BackupFileCodec.formatVersion,
      'sourcePublicKey': _node,
      'items': ['channels', 'channelSettings'],
      'sections': {
        'channels': {
          'preferences': {
            'channels$_scope': 'unrelated malformed channel list',
            'channel_smaz_${_scope}_$id': true,
            'channel_url_images_${_scope}_$id': false,
            'channel_cyr2lat_${_scope}_profile_$id': 'profile',
            'channel_region_${_scope}_$second': '#north',
            'channel_smaz_${_scope}7': true,
            'default_region_$_scope': '#other',
            'channel_smaz_0000000000_$second': true,
            'channel_order_$_scope': jsonEncode([second, id, second, 7]),
          },
        },
      },
    }, password: '');
    final plan = await const BackupImportPlanner().inspect(
      contents, password: '', channelSettingsOnly: true,
    );
    expect(plan.channels, isNull);
    final settings = plan.channelSettings!;
    expect(settings.values, {
      (id, BackupChannelOption.smaz): true,
      (id, BackupChannelOption.urlImages): false,
      (id, BackupChannelOption.cyr2latProfile): 'profile',
      (second, BackupChannelOption.region): '#north',
    });
    expect(settings.order, [second, id]);

    final snapshot = BackupSnapshot(
      sourcePublicKey: _node,
      channelSettings: settings,
      createdAt: DateTime.utc(2026),
    );
    final encoded = await snapshot.encode(password: '');
    final decoded = await const BackupFileCodec().decode(encoded, password: '');
    expect(decoded['items'], ['channelSettings']);
    expect(encoded, isNot(contains(_first.pskHex)));
    final roundTrip = await const BackupImportPlanner().inspect(
      encoded, password: '', channelSettingsOnly: true,
    );
    expect(roundTrip.channelSettings!.values, settings.values);
    expect(roundTrip.channelSettings!.order, settings.order);
  });

  test('never writes settings through ambiguous destination names or PSKs', () {
    final unrelated = Channel.fromHex(1, 'first', '03' * 16);
    final sameKey = Channel.fromHex(4, 'Other name', _second.pskHex);
    expect(backupChannelBindings([_first, _second, unrelated, sameKey]), isEmpty);
  });

  test('the standard sections only contain options recognized by upstream', () async {
    final id = _first.storageId!;
    final contact = 'cd' * 32;
    final settings = BackupChannelSettings({
      (id, BackupChannelOption.mcmp): true,
      (id, BackupChannelOption.urlImages): false,
      (id, BackupChannelOption.region): kUnscopedRegion,
    }, [id]);
    final contactSettings = BackupContactSettings({
      (contact, 'mcotxt_enabled'): '1',
      (contact, 'url_images_enabled'): '0',
    });
    final contents = await BackupSnapshot(
      sourcePublicKey: _node,
      channelSettings: settings,
      contactSettings: contactSettings,
      createdAt: DateTime.utc(2026),
    ).encode(password: '');
    final payload = await const BackupFileCodec().decode(contents, password: '');
    final sections = payload['sections'] as Map<String, Object?>;
    Map<String, Object?> preferences(String section) =>
        (sections[section] as Map<String, Object?>)['preferences'] as Map<String, Object?>;
    expect(preferences('channels'), {
      'channel_url_images_${_scope}_$id': false,
      'channel_order_$_scope': jsonEncode([id]),
    });
    expect(preferences('contacts'), {'contact_url_images_$_scope$contact': false});
    final channels = await const BackupImportPlanner().inspect(
      contents, password: '', channelSettingsOnly: true,
    );
    final contacts = await const BackupImportPlanner().inspect(
      contents, password: '', contactSettingsOnly: true,
    );
    expect(channels.channelSettings!.values, settings.values);
    expect(contacts.contactSettings!.values, contactSettings.values);
  });
}
