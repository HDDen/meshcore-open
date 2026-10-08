import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/message_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What a stored direct message keeps of the route its delivery was confirmed
// along: the hops and their width come back as written, an empty route (a
// delivery without repeaters) stays an empty route rather than becoming
// unknown, a message that never got one reads as unknown, and so does a row
// written before the field existed. The route is set once: a copy made
// without naming it keeps it. The database needs a native sqlite3 the test
// host can load; when it cannot, the round trips are skipped rather than
// failed, and the two tests that need no database still run.

MessageHistoryDatabase _memoryDatabase() =>
    MessageHistoryDatabase.withExecutor(NativeDatabase.memory());

Future<String?> _sqliteProblem() async {
  try {
    final database = _memoryDatabase();
    await database.customSelect('SELECT 1').get();
    await database.close();
    return null;
  } catch (error) {
    return 'sqlite3 is not available to this test host: $error';
  }
}

const _node = '7020f1bd19aabbccddeeff00112233445566778899aabbccddeeff0011223344';
final _contactKey = Uint8List.fromList(
  List<int>.generate(32, (i) => (i * 7 + 3) & 0xFF),
);

Message _outgoing(
  String text, {
  Uint8List? deliveryPathBytes,
  int? deliveryPathHashWidth,
}) => Message(
  senderKey: _contactKey,
  text: text,
  timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  isOutgoing: true,
  status: MessageStatus.delivered,
  messageId: 'id-$text',
  deliveryPathBytes: deliveryPathBytes,
  deliveryPathHashWidth: deliveryPathHashWidth,
);

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = await _sqliteProblem();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(() async {
    await MessageHistoryStorage.instance.resetForTesting();
    PrefsManager.reset();
  });

  /// Writes [message] through the store and reads the conversation back.
  Future<Message> roundTrip(Message message) async {
    await MessageHistoryStorage.instance.initializeAndMigrate(
      databaseFactory: _memoryDatabase,
    );
    final store = MessageStore()..setPublicKeyHex = _node;
    final contactKeyHex = pubKeyToHex(_contactKey);
    await store.saveMessage(contactKeyHex, message);
    final stored = await store.loadMessages(contactKeyHex);
    expect(stored, hasLength(1));
    return stored.single;
  }

  group('the delivery route survives the round trip', () {
    test('with its hops and their width', () async {
      final stored = await roundTrip(
        _outgoing(
          'hi',
          deliveryPathBytes: Uint8List.fromList([0x12, 0x34, 0x56, 0x78]),
          deliveryPathHashWidth: 2,
        ),
      );

      expect(stored.deliveryPathBytes, [0x12, 0x34, 0x56, 0x78]);
      expect(stored.deliveryPathHashWidth, 2);
    });

    test('empty, a delivery without repeaters, rather than unknown', () async {
      final stored = await roundTrip(
        _outgoing(
          'hi',
          deliveryPathBytes: Uint8List(0),
          deliveryPathHashWidth: 1,
        ),
      );

      expect(stored.deliveryPathBytes, isNotNull);
      expect(stored.deliveryPathBytes, isEmpty);
      expect(stored.deliveryPathHashWidth, 1);
    });

    test('unknown for a message that never got one', () async {
      final stored = await roundTrip(_outgoing('hi'));

      expect(stored.deliveryPathBytes, isNull);
      expect(stored.deliveryPathHashWidth, isNull);
    });
  }, skip: skip);

  test('a row written before the field reads as unknown', () {
    final stored = MessageStore.decodeStoredMessage({
      'senderKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      'text': 'hi',
      'timestamp': 1700000000000,
      'isOutgoing': true,
      'status': MessageStatus.delivered.index,
      'messageId': 'old',
    });

    expect(stored.deliveryPathBytes, isNull);
    expect(stored.deliveryPathHashWidth, isNull);
  });

  test('a copy made without naming the route keeps it', () {
    final message = _outgoing(
      'hi',
      deliveryPathBytes: Uint8List.fromList([0x12]),
      deliveryPathHashWidth: 1,
    );

    final copy = message.copyWith(status: MessageStatus.delivered);

    expect(copy.deliveryPathBytes, [0x12]);
    expect(copy.deliveryPathHashWidth, 1);
  });
}
