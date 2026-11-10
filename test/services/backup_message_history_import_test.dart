import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/storage/channel_name_keyed_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';

final _node = List.filled(32, 'ab').join();
final _contact = List.filled(32, 'cd').join();
const _scope = 'ababababab';
final _directKey = 'messages_$_scope$_contact';
final _psk = Uint8List.fromList(List.filled(16, 1));
final _channel = Channel(index: 7, name: 'Current name', psk: _psk);

Map<String, dynamic> _direct(String text, {String? id}) => {
  'messageId': id,
  'text': text,
  'senderKey': base64Encode(List.filled(32, 0xcd)),
  'timestamp': 1700000000000,
  'isOutgoing': true,
  'status': MessageStatus.pending.index,
};

Map<String, dynamic> _channelMessage(String id) => {
  'messageId': id,
  'text': 'Channel text',
  'senderName': 'Someone',
  'timestamp': 1700000000000,
  'receivedAt': 1700000001000,
  'channelIndex': 2,
  'isOutgoing': false,
  'status': ChannelMessageStatus.sent.index,
};

Map<String, Object?> _payload({bool invalid = false}) => {
  'format': BackupFileCodec.payloadFormat,
  'version': BackupFileCodec.formatVersion,
  'sourcePublicKey': _node,
  'items': ['contactHistory', 'channelHistory', 'channels'],
  'sections': {
    'contacts': {
      'preferences': {
        _directKey: jsonEncode([
          _direct('Backup text', id: 'exists'),
          _direct('New direct', id: 'new'),
          _direct('Repeated legacy text'),
          _direct('Repeated legacy text'),
        ]),
        'messages_fffffffffff$_contact': 'not from the source scope',
      },
    },
    'channels': {
      'preferences': {
        'channels$_scope': 'unrelated section is not applied',
        'channel_messages_${_scope}_${_channel.storageId}': [
          if (invalid) {'text': 'Malformed'} else _channelMessage('channel'),
        ],
        'channel_messages_${_scope}_0000000000000000': [
          _channelMessage('unknown-psk'),
        ],
      },
    },
  },
};

Future<BackupImportPlan> _inspect(String file, {String password = ''}) =>
    const BackupImportPlanner().inspect(
      file,
      password: password,
      messageHistoryOnly: true,
    );

void main() {
  test('imports by channel PSK and appends without overwriting or duplicating',
      () async {
    final contents = await const BackupFileCodec().encode(
      _payload(),
      password: '',
    );
    final plan = await _inspect(contents);
    expect(plan.channels, isNull);
    final preview = plan.messageHistory!.preview(
      destination: [_channel],
      session: Object(),
    );
    expect(preview.count, 5);
    expect(preview.skipped, 1);
    expect(preview.channelTargets.keys, [7]);

    final db = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await db.upsertMessages(0, _directKey, [
      _direct('Current text', id: 'exists')
        ..['status'] = MessageStatus.delivered.index,
    ]);
    final added = await db.mergeBackupMessages(
      preview.batches,
      stillCurrent: () => true,
    );
    expect(added.added, 4);
    final direct = (await db.readMessageJson(0, _directKey))
        .map((row) => jsonDecode(row) as Map<String, dynamic>)
        .toList();
    final existing = direct.singleWhere((row) => row['messageId'] == 'exists');
    expect(existing['text'], 'Current text');
    expect(existing['status'], MessageStatus.delivered.index);
    final imported = direct.singleWhere((row) => row['messageId'] == 'new');
    expect(imported['status'], MessageStatus.failed.index);
    expect(direct.where((row) => row['text'] == 'Repeated legacy text'), hasLength(2));

    final key = ChannelNameKeyedStore.nameStorageKey(
      'channel_messages_$_scope',
      'Current name',
    );
    final channel = await db.readMessageJson(1, key);
    expect(jsonDecode(channel.single)['messageId'], 'channel');
    final repeated = await db.mergeBackupMessages(
      preview.batches,
      stillCurrent: () => true,
    );
    expect(repeated.added, 0);
  });

  test('a channel name shared by different PSKs is not a safe target', () async {
    final contents = await const BackupFileCodec().encode(
      _payload(),
      password: '',
    );
    final preview = (await _inspect(contents)).messageHistory!.preview(
      destination: [
        _channel,
        Channel(
          index: 1,
          name: _channel.name,
          psk: Uint8List.fromList(List.filled(16, 2)),
        ),
      ],
      session: Object(),
    );
    expect(preview.channelTargets, isEmpty);
    expect(preview.skipped, 2);
    expect(preview.count, 4);
  });

  test('a changed destination rolls back the whole transaction', () async {
    final db = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final contents = await const BackupFileCodec().encode(_payload(), password: '');
    final preview = (await _inspect(contents)).messageHistory!.preview(
      destination: [_channel],
      session: Object(),
    );
    var checks = 0;
    await expectLater(
      db.mergeBackupMessages(
        preview.batches,
        stillCurrent: () => ++checks <= 3,
      ),
      throwsStateError,
    );
    expect(await db.storageKeys(0), isEmpty);
    expect(await db.storageKeys(1), isEmpty);
  });

  test('checks the password and rejects malformed messages at inspection',
      () async {
    const password = 'synthetic password';
    final contents = await const BackupFileCodec().encode(
      _payload(invalid: true),
      password: password,
    );
    await expectLater(_inspect(contents), throwsA(isA<BackupPasswordException>()));
    await expectLater(_inspect(contents, password: password), throwsFormatException);
  });
}
