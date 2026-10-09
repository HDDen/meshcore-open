import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The path an incoming direct message or room post is stored with is the
// packet's own, as the node reports it in the CONTACT_MSG_RECV frame: a
// packet routed to us (path byte 0xFF) is direct, with no hops known, since
// the repeaters consumed its route on the way; a flood packet carries the
// number of hops it travelled. The route the app or the user holds for the
// contact, a pinned one above all, is the route of our sends and says
// nothing about how the contact's packet reached us, so it stays off the
// message. The messages go into an in-memory database, so the tests are
// skipped on a host that cannot load a native sqlite3.

final _selfKey = Uint8List.fromList(List<int>.generate(32, (i) => 0x40 + i));
final _aliceKey = Uint8List.fromList(
  List<int>.generate(32, (i) => (i * 7 + 2) & 0xFF),
);

/// RESP_CODE_SELF_INFO: the node's type, TX power, key, position, flags,
/// radio parameters and name.
Uint8List _selfInfoFrame(Uint8List key, String name) {
  final data = ByteData(58);
  final header = data.buffer.asUint8List();
  header[0] = respCodeSelfInfo;
  header[1] = advTypeChat;
  header[2] = 20; // tx power
  header[3] = 22; // max tx power
  header.setRange(4, 36, key);
  data.setInt32(36, 55700000, Endian.little);
  data.setInt32(40, 37600000, Endian.little);
  data.setUint32(48, 869525000, Endian.little);
  data.setUint32(52, 250000, Endian.little);
  header[56] = 10; // sf
  header[57] = 5; // cr
  return Uint8List.fromList([...header, ...utf8.encode(name), 0]);
}

/// RESP_CODE_CONTACT for [key] with one-byte hops along [route], or no route.
Uint8List _contactFrame(Uint8List key, String name, {List<int>? route}) {
  final data = ByteData(1 + 32 + 3 + 64 + 32 + 4 + 12);
  final bytes = data.buffer.asUint8List();
  bytes[0] = respCodeContact;
  bytes.setRange(1, 33, key);
  bytes[33] = advTypeChat;
  if (route == null) {
    bytes[35] = 0xFF;
  } else {
    bytes[35] = route.length;
    bytes.setRange(36, 36 + route.length, route);
  }
  bytes.setRange(100, 100 + name.length, name.codeUnits);
  data.setUint32(132, 1700000000, Endian.little);
  return bytes;
}

/// CONTACT_MSG_RECV_V3 as the node delivers a direct message it decrypted:
/// the SNR, two reserved bytes, the sender's six-byte prefix, the path byte
/// as the node writes it (0xFF for a packet routed to us, the packed path
/// length of a flood otherwise), the text type, the packet timestamp and
/// the text.
Uint8List _messageFrame({
  required Uint8List senderKey,
  required int pathByte,
  required int timestampSeconds,
  required String text,
}) {
  final timestamp = ByteData(4)..setUint32(0, timestampSeconds, Endian.little);
  return Uint8List.fromList([
    respCodeContactMsgRecvV3,
    32, // snr * 4
    0,
    0,
    ...senderKey.sublist(0, 6),
    pathByte,
    txtTypePlain,
    ...timestamp.buffer.asUint8List(),
    ...utf8.encode(text),
    0,
  ]);
}

/// A connected connector whose frames go nowhere: the node is played by the
/// test through [handleFrameForTest].
class _Connector extends MeshCoreConnector {
  @override
  bool get isConnected => true;

  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {}
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

Future<void> _waitFor(bool Function() condition, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// The connector past its handshake, with notifications off.
class _Node {
  _Node(this.connector);

  final _Connector connector;

  static Future<_Node> start() async {
    final connector = _Connector();
    final settings = AppSettingsService();
    await settings.updateSettings(
      settings.settings.copyWith(notificationsEnabled: false),
    );
    connector.attachAppSettingsServiceForTest(settings);
    // The handshake as a connection runs it: the request marks the answer
    // as the one that binds the stores to the node.
    await connector.refreshDeviceInfo();
    connector.handleFrameForTest(_selfInfoFrame(_selfKey, 'Me'));
    await _settle();
    expect(connector.selfPublicKeyHex, isNotEmpty);
    return _Node(connector);
  }

  Contact get alice => connector.getContactByPubKeyHex(pubKeyToHex(_aliceKey))!;

  /// The node reports Alice with [route], or without one.
  Future<void> contact({List<int>? route}) async {
    connector.handleFrameForTest(
      _contactFrame(_aliceKey, 'Alice', route: route),
    );
    await _waitFor(
      () => connector.getContactByPubKeyHex(pubKeyToHex(_aliceKey)) != null,
      'the contact Alice',
    );
  }

  /// Alice's message arrives with [pathByte] in its frame.
  Future<Message> receive(String text, {required int pathByte}) async {
    connector.handleFrameForTest(
      _messageFrame(
        senderKey: _aliceKey,
        pathByte: pathByte,
        timestampSeconds: 1700000000,
        text: text,
      ),
    );
    await _waitFor(
      () => connector.getMessages(alice).any((m) => m.text == text),
      'the message "$text"',
    );
    await _settle();
    return connector.getMessages(alice).singleWhere((m) => m.text == text);
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final tempDir = Directory.systemTemp.createTempSync('mco_incoming_path_');
  final skip = await () async {
    try {
      final database = MessageHistoryDatabase.withExecutor(
        NativeDatabase.memory(),
      );
      await database.customSelect('SELECT 1').get();
      await database.close();
      return null;
    } catch (error) {
      return 'sqlite3 is not available to this test host: $error';
    }
  }();

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    tempDir.deleteSync(recursive: true);
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await MessageHistoryStorage.instance.resetForTesting();
    await MessageHistoryStorage.instance.initializeAndMigrate(
      databaseFactory: () =>
          MessageHistoryDatabase.withExecutor(NativeDatabase.memory()),
    );
  });

  tearDown(() async {
    // The connector saves messages and contacts without awaiting the
    // database; a batch still running when the database closes fails after
    // the test, so the writes get a moment to land first.
    await _settle();
    await MessageHistoryStorage.instance.resetForTesting();
    PrefsManager.reset();
  });

  group('a message routed to us', () {
    test('is stored as direct with no hops, not with the route the node '
        'holds for the contact', () async {
      final node = await _Node.start();
      await node.contact(route: [0x10]);

      final message = await node.receive('hi', pathByte: 0xFF);

      expect(message.isOutgoing, isFalse);
      expect(message.pathLength, 0);
      expect(message.pathBytes, isEmpty);
      expect(message.sentByFlood, isFalse);
    });

    test('is stored as direct with no hops when the user pinned a route to '
        'the contact', () async {
      final node = await _Node.start();
      await node.contact();
      await node.connector.setPathOverride(
        node.alice,
        pathLen: 1,
        pathBytes: Uint8List.fromList([0x10]),
      );
      expect(node.alice.pathOverride, 1);

      final message = await node.receive('hi', pathByte: 0xFF);

      expect(message.pathLength, 0);
      expect(message.pathBytes, isEmpty);
    });
  }, skip: skip);

  group('a flood message', () {
    test('keeps the hop count the node reports and no hop bytes', () async {
      final node = await _Node.start();
      await node.contact(route: [0x10]);

      final message = await node.receive('hi', pathByte: 2);

      expect(message.pathLength, 2);
      expect(message.pathBytes, isEmpty);
      expect(message.sentByFlood, isTrue);
    });

    test('reads the hop count out of the packed path byte', () async {
      final node = await _Node.start();
      await node.contact();

      final message = await node.receive('hi', pathByte: (1 << 6) | 3);

      expect(message.pathLength, 3);
      expect(message.sentByFlood, isTrue);
    });
  }, skip: skip);
}
