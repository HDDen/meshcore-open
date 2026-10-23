import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/storage/channel_identity_store.dart';
import 'package:meshcore_open/storage/channel_message_store.dart';
import 'package:meshcore_open/storage/channel_name_keyed_store.dart';
import 'package:meshcore_open/storage/contact_identity_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/message_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic preferences without a directory');
  }
}

const _node = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
final _contact = 'ab' * 32;
final _directKey = 'messages_0123456789$_contact';
const _channelKey = 'channel_messages_01234567892';

String _entry(String id, {String text = 'synthetic', int at = 1000}) =>
    jsonEncode([{
      'messageId': id, 'text': text, 'timestamp': at, 'receivedAt': at,
      'isOutgoing': false, 'status': 1,
    }]);

class _Gate {
  _Gate(this.operation, this.key);
  final String operation;
  final String key;
  final started = Completer<void>();
  final release = Completer<void>();
}

// Задержка только перед входом в настоящий метод БД. После release реальные
// Drift/SQLite и caches MessageHistoryStorage выполняются без подмены SQL.
class _HeldDatabase extends MessageHistoryDatabase {
  _HeldDatabase() : super.withExecutor(NativeDatabase.memory());
  final gates = <_Gate>[];
  final allGates = <_Gate>[];
  final calls = <String>[];

  _Gate hold(String operation, String key) {
    final gate = _Gate(operation, key);
    gates.add(gate);
    allGates.add(gate);
    return gate;
  }

  Future<void> _before(String operation, String key) async {
    calls.add('$operation:$key');
    final index = gates.indexWhere((g) => g.operation == operation && g.key == key);
    if (index < 0) return;
    final gate = gates.removeAt(index);
    gate.started.complete();
    await gate.release.future;
  }

  @override
  Future<bool> upsertMessages(int kind, String storageKey,
      List<Map<String, dynamic>> messages) async {
    await _before('upsert', storageKey);
    return super.upsertMessages(kind, storageKey, messages);
  }

  @override
  Future<bool> replaceMessages(int kind, String storageKey,
      List<Map<String, dynamic>> messages) async {
    await _before('replace', storageKey);
    return super.replaceMessages(kind, storageKey, messages);
  }

  @override
  Future<MessageHistoryState> deleteMessage(int kind, String storageKey,
      String messageId) async {
    await _before('delete', storageKey);
    return super.deleteMessage(kind, storageKey, messageId);
  }

  @override
  Future<void> removeHistory(int kind, String storageKey) async {
    await _before('remove', storageKey);
    return super.removeHistory(kind, storageKey);
  }

  Future<List<String>> ids(MessageHistoryKind kind, String key) async {
    final rows = await customSelect(
      'SELECT message_id FROM history_messages '
      'WHERE kind = ? AND storage_key = ? ORDER BY message_id',
      variables: [Variable<int>(kind.index), Variable<String>(key)],
    ).get();
    return rows.map((row) => row.read<String>('message_id')).toList();
  }
}

class _Result {
  _Result(Future<void> operation) {
    settled = operation.then<void>((_) {
      completed = true;
    }, onError: (Object failure, StackTrace stack) {
      error = failure;
      completed = true;
    });
  }
  late final Future<void> settled;
  bool completed = false;
  Object? error;
}

Future<String?> _sqliteProblem() async {
  final database = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
  try {
    await database.customSelect('SELECT 1').get();
    await database.close();
    return null;
  } catch (error) {
    return 'sqlite3 is not available to this test host: $error';
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sqliteProblem = await _sqliteProblem();
  final storage = MessageHistoryStorage.instance;
  late PathProviderPlatform savedPaths;
  late _HeldDatabase database;
  final operations = <_Result>[];

  setUpAll(() {
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
  });
  tearDownAll(() {
    PathProviderPlatform.instance = savedPaths;
  });

  _Result observe(Future<void> operation) {
    final result = _Result(operation);
    operations.add(result);
    return result;
  }

  group('history persistence baseline (SQLite in memory)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      PrefsManager.reset();
      await PrefsManager.initialize();
      await storage.resetForTesting();
      ContactIdentities.instance.resetForTesting();
      ChannelIdentities.instance.resetForTesting();
      database = _HeldDatabase();
      await storage.initializeAndMigrate(databaseFactory: () => database);
      database.calls.clear();
      operations.clear();
    });

    tearDown(() async {
      for (final gate in database.allGates) {
        if (!gate.release.isCompleted) {
          gate.release.complete();
        }
      }
      await Future.wait(operations.map((result) => result.settled));
      await storage.resetForTesting();
      ContactIdentities.instance.resetForTesting();
      ChannelIdentities.instance.resetForTesting();
      PrefsManager.reset();
    });

    for (final kind in MessageHistoryKind.values) {
      test('point $kind write and key cache wait for the database Future', () async {
        final key = kind == MessageHistoryKind.direct ? _directKey : _channelKey;
        final gate = database.hold('upsert', key);
        final result = observe(storage.setString(kind, key, _entry('a')));
        await gate.started.future;
        expect(result.completed, isFalse);
        expect(storage.getKeys(kind), isNot(contains(key)));
        expect(await database.ids(kind, key), isEmpty);
        gate.release.complete();
        await result.settled;
        expect(result.error, isNull);
        expect(storage.getKeys(kind), contains(key));
        expect(await database.ids(kind, key), ['a']);
      });
    }

    test('caller timeout does not cancel the original point write', () async {
      final gate = database.hold('upsert', _directKey);
      final operation = storage.setString(MessageHistoryKind.direct, _directKey, _entry('a'));
      final actual = observe(operation);
      await gate.started.future;
      await expectLater(operation.timeout(Duration.zero), throwsA(isA<TimeoutException>()));
      expect(actual.completed, isFalse);
      expect(await database.ids(MessageHistoryKind.direct, _directKey), isEmpty);
      gate.release.complete();
      await actual.settled;
      expect(actual.error, isNull);
      expect(await database.ids(MessageHistoryKind.direct, _directKey), ['a']);
    });

    test('database failure retains identity and publishes no key or marker cache', () async {
      final gate = database.hold('upsert', _directKey);
      final failure = StateError('synthetic database failure');
      final result = observe(storage.setString(
        MessageHistoryKind.direct, _directKey, _entry('a', text: 'prefix m: synthetic'),
      ));
      await gate.started.future;
      gate.release.completeError(failure);
      await result.settled;
      expect(result.error, same(failure));
      expect(storage.getKeys(MessageHistoryKind.direct), isNot(contains(_directKey)));
      expect(storage.mayContainMarker(_directKey), isFalse);
      expect(await database.ids(MessageHistoryKind.direct, _directKey), isEmpty);
    });

    test('parallel point writes can complete independently', () async {
      final firstGate = database.hold('upsert', _directKey);
      final secondGate = database.hold('upsert', _channelKey);
      final first = observe(storage.setString(MessageHistoryKind.direct, _directKey, _entry('a')));
      final second = observe(storage.setString(MessageHistoryKind.channel, _channelKey, _entry('b')));
      await Future.wait([firstGate.started.future, secondGate.started.future]);
      secondGate.release.complete();
      await second.settled;
      expect(second.error, isNull);
      expect(first.completed, isFalse);
      expect(await database.ids(MessageHistoryKind.channel, _channelKey), ['b']);
      expect(storage.getKeys(MessageHistoryKind.direct), isNot(contains(_directKey)));
      firstGate.release.complete();
      await first.settled;
      expect(first.error, isNull);
      expect(await database.ids(MessageHistoryKind.direct, _directKey), ['a']);
    });

    test('point upsert updates one identity without replacing unrelated history', () async {
      await storage.setString(MessageHistoryKind.direct, _directKey, _entry('a'));
      await storage.setString(MessageHistoryKind.direct, _directKey, _entry('b', at: 2000));
      await storage.setString(MessageHistoryKind.direct, _directKey, _entry('a', text: 'updated'));
      final decoded = jsonDecode((await storage.getString(MessageHistoryKind.direct, _directKey))!) as List<dynamic>;
      expect(await database.ids(MessageHistoryKind.direct, _directKey), ['a', 'b']);
      expect(decoded.cast<Map<String, dynamic>>().singleWhere((m) => m['messageId'] == 'a')['text'], 'updated');
    });

    test('replacement waits and an empty replacement removes the history key', () async {
      await storage.setString(MessageHistoryKind.direct, _directKey, _entry('old', text: 'prefix m: synthetic'));
      final gate = database.hold('replace', _directKey);
      final result = observe(storage.replaceString(MessageHistoryKind.direct, _directKey, _entry('new')));
      await gate.started.future;
      expect(result.completed, isFalse);
      expect(await database.ids(MessageHistoryKind.direct, _directKey), ['old']);
      expect(storage.mayContainMarker(_directKey), isTrue);
      gate.release.complete();
      await result.settled;
      expect(result.error, isNull);
      expect(await database.ids(MessageHistoryKind.direct, _directKey), ['new']);
      expect(storage.mayContainMarker(_directKey), isFalse);
      await storage.replaceString(MessageHistoryKind.direct, _directKey, '[]');
      expect(await database.ids(MessageHistoryKind.direct, _directKey), isEmpty);
      expect(storage.getKeys(MessageHistoryKind.direct), isNot(contains(_directKey)));
    });

    test('deleting the last row waits before clearing key and marker caches', () async {
      await storage.setString(MessageHistoryKind.direct, _directKey, _entry('a', text: 'prefix m: synthetic'));
      final gate = database.hold('delete', _directKey);
      final result = observe(storage.deleteMessage(MessageHistoryKind.direct, _directKey, 'a'));
      await gate.started.future;
      expect(result.completed, isFalse);
      expect(storage.getKeys(MessageHistoryKind.direct), contains(_directKey));
      expect(await database.ids(MessageHistoryKind.direct, _directKey), ['a']);
      gate.release.complete();
      await result.settled;
      expect(result.error, isNull);
      expect(storage.getKeys(MessageHistoryKind.direct), isNot(contains(_directKey)));
      expect(storage.mayContainMarker(_directKey), isFalse);
    });

    test('removing a history waits before clearing its key', () async {
      await storage.setString(MessageHistoryKind.channel, _channelKey, _entry('a'));
      final gate = database.hold('remove', _channelKey);
      final result = observe(storage.remove(MessageHistoryKind.channel, _channelKey));
      await gate.started.future;
      expect(result.completed, isFalse);
      expect(await database.ids(MessageHistoryKind.channel, _channelKey), ['a']);
      expect(storage.getKeys(MessageHistoryKind.channel), contains(_channelKey));
      gate.release.complete();
      await result.settled;
      expect(result.error, isNull);
      expect(storage.getKeys(MessageHistoryKind.channel), isNot(contains(_channelKey)));
    });

    test('detached write still completes after its caller has stopped awaiting', () async {
      final gate = database.hold('upsert', _directKey);
      final actual = observe(storage.setString(MessageHistoryKind.direct, _directKey, _entry('a')));
      unawaited(actual.settled);
      await gate.started.future;
      expect(actual.completed, isFalse);
      gate.release.complete();
      await actual.settled;
      expect(actual.error, isNull);
      expect(await database.ids(MessageHistoryKind.direct, _directKey), ['a']);
    });

    test('direct model store keeps waiting for the point write', () async {
      final store = MessageStore()..setPublicKeyHex = _node;
      final gate = database.hold('upsert', _directKey);
      final result = observe(store.saveMessage(_contact, Message.outgoing(
        Uint8List(32), 'synthetic', messageId: 'direct',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      )));
      await gate.started.future;
      expect(result.completed, isFalse);
      gate.release.complete();
      await result.settled;
      expect(result.error, isNull);
      expect(await database.ids(MessageHistoryKind.direct, _directKey), ['direct']);
    });

    test('channel model store keeps waiting under the registered name', () async {
      final store = ChannelMessageStore()..setPublicKeyHex = _node;
      store.registerChannel(Channel(index: 2, name: 'synthetic', psk: Uint8List(16)));
      final key = ChannelNameKeyedStore.nameStorageKey(store.keyFor, 'synthetic');
      final gate = database.hold('upsert', key);
      final at = DateTime.fromMillisecondsSinceEpoch(1000);
      final result = observe(store.saveChannelMessage(2, ChannelMessage(
        senderName: 'synthetic', text: 'synthetic', timestamp: at,
        receivedAt: at, isOutgoing: false, messageId: 'channel',
      )));
      await gate.started.future;
      expect(result.completed, isFalse);
      gate.release.complete();
      await result.settled;
      expect(result.error, isNull);
      expect(await database.ids(MessageHistoryKind.channel, key), ['channel']);
    });

    test('empty point input and malformed JSON never enter the database writer', () async {
      await storage.setString(MessageHistoryKind.direct, _directKey, '[]');
      await expectLater(storage.setString(MessageHistoryKind.direct, _directKey, '{}'), throwsFormatException);
      await expectLater(storage.setString(MessageHistoryKind.direct, _directKey, '[1]'), throwsFormatException);
      expect(database.calls, isEmpty);
      expect(storage.getKeys(MessageHistoryKind.direct), isEmpty);
    });
  }, skip: sqliteProblem);
}
