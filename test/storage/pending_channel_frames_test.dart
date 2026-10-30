import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/pending_channel_frame.dart';
import 'package:meshcore_open/storage/message_history_database.dart';

MessageHistoryDatabase _open(File file) => MessageHistoryDatabase.withExecutor(
  NativeDatabase(file, setup: MessageHistoryDatabase.setupConnection),
);

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? skip;
  try {
    final probe = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
    await probe.customSelect('SELECT 1').get();
    await probe.close();
  } catch (error) {
    skip = 'sqlite3 is not available to this test host: $error';
  }

  final node = List.filled(64, 'a').join();
  final otherNode = List.filled(64, 'b').join();
  late Directory directory;
  late File file;
  late MessageHistoryDatabase database;

  PendingChannelFrame frame(String id, {String? nodeKey, int second = 0}) =>
      PendingChannelFrame(
        id: id,
        nodeKey: nodeKey ?? node,
        channelIndex: 2,
        frame: Uint8List.fromList([8, 2, 0, 0, 1, 0, 0, 0, 65]),
        receivedAt: DateTime.utc(2026, 10, 30, 12, 0, second),
      );

  group('pending channel frames', () {
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mco_pending_channels_');
      file = File('${directory.path}/history.sqlite');
      database = _open(file);
    });

    tearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    test('raw bytes and first receipt survive a database close and reopen', () async {
      final pending = frame('one');
      await database.putPendingChannelFrame(pending);
      await database.close();
      database = _open(file);
      final restored = (await database.readPendingChannelFrames(node)).single;
      expect(restored.id, pending.id);
      expect(restored.channelIndex, 2);
      expect(restored.frame, orderedEquals(pending.frame));
      expect(restored.receivedAt.millisecondsSinceEpoch, pending.receivedAt.millisecondsSinceEpoch);
      expect(restored.channelName, isNull);
    });

    test('pinning is idempotent and preserves original frame and receipt time', () async {
      final pending = frame('one');
      await database.putPendingChannelFrame(pending);
      await database.putPendingChannelFrame(pending.bind('Test', 'key'));
      await database.putPendingChannelFrame(pending.bind('Test', 'key'));
      final restored = (await database.readPendingChannelFrames(node)).single;
      expect(restored.channelName, 'Test');
      expect(restored.channelKey, 'key');
      expect(restored.frame, orderedEquals(pending.frame));
      expect(restored.receivedAt.millisecondsSinceEpoch, pending.receivedAt.millisecondsSinceEpoch);
    });

    test('acknowledgement is scoped to the full node key', () async {
      await database.putPendingChannelFrame(frame('same-id'));
      await database.putPendingChannelFrame(frame('same-id', nodeKey: otherNode));
      await database.removePendingChannelFrame(node, 'same-id');
      expect(await database.readPendingChannelFrames(node), isEmpty);
      expect(await database.readPendingChannelFrames(otherNode), hasLength(1));
    });

    test('received frames are replayed by receipt time', () async {
      await database.putPendingChannelFrame(frame('later', second: 2));
      await database.putPendingChannelFrame(frame('earlier', second: 1));
      expect(
        (await database.readPendingChannelFrames(node)).map((row) => row.id),
        ['earlier', 'later'],
      );
    });

    test('an existing schema gains the auxiliary table without losing metadata', () async {
      await database.customStatement(
        "INSERT INTO history_metadata (key, value) VALUES ('fixture', 'kept')",
      );
      await database.customStatement('DROP TABLE pending_channel_frames');
      await database.close();
      database = _open(file);
      expect(await database.readPendingChannelFrames(node), isEmpty);
      final row = await database.customSelect(
        "SELECT value FROM history_metadata WHERE key = 'fixture'",
      ).getSingle();
      expect(row.read<String>('value'), 'kept');
      final version = await database.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), MessageHistoryDatabase.currentSchemaVersion);
    });
  }, skip: skip);
}
