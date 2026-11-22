import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/message_history_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('denylist survives closing and reopening the database', () async {
    final directory = await Directory.systemTemp.createTemp('mcoa-region-filter-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File.fromUri(directory.uri.resolve('history.sqlite'));
    MessageHistoryDatabase open() => MessageHistoryDatabase.withExecutor(NativeDatabase(file));
    var database = open();
    addTearDown(() => database.close());
    await database.writeChannelRegionFilter('node', 'channel', '["!unknown","north"]');
    await database.close();
    database = open();
    expect(await database.readChannelRegionFilter('node', 'channel'), '["!unknown","north"]');
  });


  test('SQL region filters are independent per node and channel; explicit empty choices persist', () async {
    final database = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(database.close);
    expect(await database.readChannelRegionFilter('node-a', 'channel-a'), isNull);
    await database.writeChannelRegionFilter('node-a', 'channel-a', '["north"]');
    await database.writeChannelRegionFilter('node-a', 'channel-b', '[""]');
    await database.writeChannelRegionFilter('node-b', 'channel-a', '["!unknown"]');
    expect(await database.readChannelRegionFilter('node-a', 'channel-a'), '["north"]');
    expect(await database.readChannelRegionFilter('node-a', 'channel-b'), '[""]');
    expect(await database.readChannelRegionFilter('node-b', 'channel-a'), '["!unknown"]');
    await database.writeChannelRegionFilter('node-a', 'channel-a', '[]');
    expect(await database.readChannelRegionFilter('node-a', 'channel-a'), '[]');
    expect(await database.importChannelRegionFilter('node-a', 'channel-a', '["south"]'), isFalse);
    expect(await database.readChannelRegionFilter('node-a', 'channel-a'), '[]');
    expect(await database.importChannelRegionFilter('node-a', 'channel-c', '["south"]'), isTrue);
    expect(await database.readChannelRegionFilter('node-a', 'channel-c'), '["south"]');
  });
}
