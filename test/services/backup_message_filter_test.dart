import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/backup_message_filter.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';

void main() {
  test('reads an upstream filter backup without activating it or copying its corpus', () async {
    final id = 'ab' * 8;
    final contents = await const BackupFileCodec().encode({
      'format': BackupFileCodec.payloadFormat,
      'version': BackupFileCodec.formatVersion,
      'sourcePublicKey': '',
      'items': ['channelFilters'],
      'sections': {
        'channels': {
          'preferences': {
            BackupMessageFilter.settingsKey: jsonEncode({
              'enabled': true,
              'learning': true,
              'duplicates': true,
              'repeatSends': 4,
              'excludedChannelIds': [id.toUpperCase(), '7'],
            }),
            BackupMessageFilter.rulesKey: [
              {'id': 'promo', 'pattern': 'promo', 'field': 'text', 'match': 'wholeWord'},
              {'id': 'broken', 'pattern': 'unrecognized rule type', 'field': 'other'},
            ],
            'message_filter_spam_examples': 'example from the original profile',
          },
        },
      },
    }, password: '');
    final plan = await const BackupImportPlanner().inspect(
      contents, password: '', messageFilterOnly: true,
    );
    expect(plan.sourcePublicKey, isNull);
    final backup = plan.messageFilter!;
    final preview = backup.preview(const MessageFilterSettings(), const []);
    expect(preview.addedRules.single.match, FilterRuleMatch.wholeWord);
    expect(preview.settings.enabled, isFalse);
    expect(preview.settings.learning, isFalse);
    expect(preview.settings.duplicates, isTrue);
    expect(preview.settings.repeatSends, 4);
    expect(preview.settings.excludedChannelIds, {id});

    final snapshot = BackupSnapshot(messageFilter: backup, createdAt: DateTime.utc(2026));
    final encoded = await snapshot.encode(password: '');
    final payload = await const BackupFileCodec().decode(encoded, password: '');
    expect(payload['items'], [BackupMessageFilter.section]);
    expect(encoded, isNot(contains('example from the original profile')));
    expect(encoded, isNot(contains('"learning"')));
    final roundTrip = await const BackupImportPlanner().inspect(
      encoded, password: '', messageFilterOnly: true,
    );
    expect(roundTrip.messageFilter!.toPreferences(), backup.toPreferences());
  });
}
