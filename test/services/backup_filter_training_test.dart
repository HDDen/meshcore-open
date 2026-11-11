import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/backup_filter_training.dart';
import 'package:meshcore_open/models/message_filter.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';

Map<String, Object> _example(String sender, String text, int timestamp) => {
  'sender': sender, 'text': text, 'addedAtMs': timestamp,
};

void main() {
  test('reads upstream training classes and keeps the newest manual label per text', () async {
    final contents = await const BackupFileCodec().encode({
      'format': BackupFileCodec.payloadFormat,
      'version': BackupFileCodec.formatVersion,
      'sourcePublicKey': '',
      'items': ['channelFilters'],
      'sections': {
        'channels': {
          'preferences': {
            'message_filter_spam_examples': jsonEncode([
              _example('Alice', 'cheap radios', 10),
              _example('Carol', 'sale', 20),
              _example('Diane', 'sale', 21),
            ]),
            'message_filter_ham_examples': [
              _example('Bob', 'CHEAP RADIOS', 30),
            ],
            'message_filter_recent_clean': [
              _example('Bob', 'hello', 9),
              _example('Bob', 'hello', 12),
              _example('Alice', 'different', 22),
              _example('Bob', 'hello', 23),
            ],
            'message_filter_settings': {'enabled': true, 'learning': true},
          },
        },
      },
    }, password: '');
    final plan = await const BackupImportPlanner().inspect(
      contents, password: '', filterTrainingOnly: true,
    );
    final corpus = plan.filterTraining!;
    expect(plan.messageFilter, isNull);
    expect(corpus.rows.map((row) => (row.kind, row.sender, row.text)), [
      (FilterTrainingKind.ordinary, 'bob', 'hello'),
      (FilterTrainingKind.spam, 'carol', 'sale'),
      (FilterTrainingKind.spam, 'diane', 'sale'),
      (FilterTrainingKind.ordinary, 'alice', 'different'),
      (FilterTrainingKind.ordinary, 'bob', 'hello'),
      (FilterTrainingKind.notSpam, 'bob', 'cheap radios'),
    ]);

    final snapshot = BackupSnapshot(filterTraining: corpus, createdAt: DateTime.utc(2026));
    final encoded = await snapshot.encode(password: '');
    expect(snapshot.fileName, startsWith('meshcore-filter-training-'));
    final payload = await const BackupFileCodec().decode(encoded, password: '');
    expect(payload['items'], [BackupFilterTraining.section]);
    expect(encoded, isNot(contains('"learning"')));
    final roundTrip = await const BackupImportPlanner().inspect(
      encoded, password: '', filterTrainingOnly: true,
    );
    expect(roundTrip.filterTraining!.rows, corpus.rows);
  });
}
