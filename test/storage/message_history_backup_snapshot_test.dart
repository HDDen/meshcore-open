import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';
import 'package:meshcore_open/storage/message_history_backup_snapshot.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:sqlite3/sqlite3.dart';

const _scope = 'ababababab';
final _node = 'ab' * 32;
final _directKey = 'messages_$_scope${'cd' * 32}';
final _otherDirectKey = 'messages_${'ef' * 5}${'cd' * 32}';
const _channelKey = 'channel_messages_${_scope}_0123456789abcdef';
const _current = 'channel_messages_${_scope}name_Y3VycmVudA';
const _former = 'channel_messages_${_scope}name_Zm9ybWVy';
const _unbound = 'channel_messages_${_scope}name_dW5ib3VuZA';

Map<String, dynamic> _message(String id, String text) => {
  'messageId': id,
  'text': text,
  'senderKey': base64Encode(List.filled(32, 0xcd)),
  'senderName': 'Test sender',
  'timestamp': 1700000000000,
  'isOutgoing': false,
  'status': 1,
};

void main() {
  test('export has only the requested scope and uses the current channel row',
      () async {
    final db = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await db.upsertMessages(0, _directKey, [_message('direct', 'Local direct')]);
    await db.upsertMessages(0, _otherDirectKey, [_message('other', 'Foreign')]);
    await db.upsertMessages(1, _current, [_message('one', 'Current value')]);
    await db.upsertMessages(1, _former, [
      _message('one', 'Older duplicate'),
      _message('two', 'Only on former name'),
    ]);
    await db.upsertMessages(1, _unbound, [_message('unbound', 'Unbound')]);

    final rows = await db.snapshotBackupMessages(
      scope: _scope,
      includeDirect: true,
      channelKeys: {_channelKey: [_current, _former]},
      stillCurrent: () => true,
    );
    expect(rows.keys, unorderedEquals([_directKey, _channelKey]));
    final snapshot = BackupSnapshot.messageHistory(
      sourcePublicKey: _node,
      nodeName: 'Test / node',
      rows: rows,
      createdAt: DateTime.utc(2026),
    );
    expect(snapshot.fileName, startsWith('meshcore-history-Test - node'));
    const password = 'synthetic password';
    final contents = await snapshot.encode(password: password);
    expect(contents, isNot(contains('Local direct')));
    final plan = await const BackupImportPlanner().inspect(
      contents,
      password: password,
      messageHistoryOnly: true,
    );
    expect(plan.contacts, isNull);
    expect(plan.channels, isNull);
    expect(plan.appSettings, isNull);
    expect(plan.messageHistory!.nodeKey, _node);
    expect(plan.messageHistory!.direct.values.single.single['text'], 'Local direct');
    expect(
      plan.messageHistory!.channels.values.single.map((row) => row['text']),
      unorderedEquals(['Current value', 'Only on former name']),
    );
    expect(await db.readMessageJson(1, _former), hasLength(2));

    final directOnly = await db.snapshotBackupMessages(
      scope: _scope,
      includeDirect: true,
      channelKeys: const {},
      stillCurrent: () => true,
    );
    expect(directOnly.keys, [_directKey]);
  });

  test('both sections read the same WAL snapshot while a writer commits',
      () async {
    final directory = await Directory.systemTemp.createTemp('mcoa-history-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}history.sqlite');
    final db = MessageHistoryDatabase.withExecutor(NativeDatabase(
      file,
      setup: (database) => database.execute('PRAGMA journal_mode = WAL'),
    ));
    addTearDown(db.close);
    await db.upsertMessages(0, _directKey, [_message('direct', 'Direct')]);
    await db.upsertMessages(1, _current, [_message('channel', 'Before')]);
    final writer = sqlite3.open(file.path);
    addTearDown(writer.close);
    var checks = 0;
    final rows = await db.snapshotBackupMessages(
      scope: _scope,
      includeDirect: true,
      channelKeys: {_channelKey: [_current]},
      stillCurrent: () {
        if (++checks == 2) {
          writer.execute(
            'UPDATE history_messages SET message_json = ? WHERE storage_key = ?',
            [jsonEncode(_message('channel', 'After')), _current],
          );
        }
        return true;
      },
    );
    expect(jsonDecode(rows[_channelKey]!.single)['text'], 'Before');
    final current = await db.readMessageJson(1, _current);
    expect(jsonDecode(current.single)['text'], 'After');

    checks = 0;
    await expectLater(
      db.snapshotBackupMessages(
        scope: _scope,
        includeDirect: true,
        channelKeys: {_channelKey: [_current]},
        stillCurrent: () => ++checks < 2,
      ),
      throwsStateError,
    );
    await db.upsertMessages(1, _current, [_message('channel', 'Next')]);
    final next = await db.readMessageJson(1, _current);
    expect(jsonDecode(next.single)['text'], 'Next');
  });

  test('a backup beyond the importer limit is rejected before saving', () async {
    final snapshot = BackupSnapshot.messageHistory(
      sourcePublicKey: _node,
      nodeName: 'Test node',
      rows: {
        _directKey: [jsonEncode(_message('large', 'x' * backupMaxJsonBytes))],
      },
      createdAt: DateTime.utc(2026),
    );
    await expectLater(snapshot.encode(password: ''), throwsA(isA<BackupFileTooLarge>()));
  });
}
