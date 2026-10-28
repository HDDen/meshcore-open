import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/cli_history_writes.dart';
import 'package:meshcore_open/helpers/repeater_cli_history.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await MessageHistoryStorage.instance.resetForTesting();
    await MessageHistoryStorage.instance.initializeAndMigrate(databaseFactory: () =>
      MessageHistoryDatabase.withExecutor(NativeDatabase.memory()));
  });
  tearDown(() async {
    await MessageHistoryStorage.instance.resetForTesting();
    PrefsManager.reset();
  });

  RepeaterCliHistory open() => RepeaterCliHistory(nodeKey: '01' * 32,
    nodeName: 'Synthetic node', repeaterKey: '02' * 32, repeaterName: 'Synthetic relay');

  test('reopened console restores transcript and an old controller cannot resurrect a cleared reply', () async {
    final first = open();
    await first.ensureLoaded();
    final old = first.revision;
    await first.append('command', 'ver', revision: old);
    first.dispose();
    final second = open();
    addTearDown(second.dispose);
    await second.ensureLoaded();
    expect(second.transcript.single['text'], 'ver');
    await second.clear();
    expect(await first.append('response', 'late reply', revision: old), isFalse);
    expect(second.transcript, isEmpty);
    final third = open();
    addTearDown(third.dispose);
    await third.ensureLoaded();
    expect(third.transcript, isEmpty);
    await second.append('command', 'board', revision: second.revision);
    expect(second.transcript.single['text'], 'board');
  });

  test('a clear waits for an in-progress write and fences a callback queued after it', () async {
    const scope = 'synthetic-clear-race';
    final gate = Completer<void>();
    final started = Completer<void>();
    final events = <String>[];
    final revision = CliHistoryWrites.revision(scope);
    final write = CliHistoryWrites.save(scope, revision, () async {
      started.complete();
      await gate.future;
      events.add('write');
    });
    await started.future;
    final clear = CliHistoryWrites.clear(scope, () async { events.add('clear'); });
    final late = CliHistoryWrites.save(scope, revision, () async { events.add('late'); });
    gate.complete();
    expect(await write, isTrue);
    await clear;
    expect(await late, isFalse);
    expect(events, ['write', 'clear']);
  });

  test('a failed clear preserves its revision and permits a subsequent write', () async {
    const scope = 'synthetic-clear-failure';
    final revision = CliHistoryWrites.revision(scope);
    await expectLater(CliHistoryWrites.clear(scope, () async {
      throw StateError('Synthetic SQL failure');
    }), throwsStateError);
    expect(CliHistoryWrites.revision(scope), revision);
    var saved = false;
    expect(await CliHistoryWrites.save(scope, revision, () async { saved = true; }), isTrue);
    expect(saved, isTrue);
  });
}
