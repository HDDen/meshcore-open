import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/channel_echo_recovery.dart';
import 'package:meshcore_open/helpers/direct_echo_crypto.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/models/path_history.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/message_retry_service.dart';
import 'package:meshcore_open/services/path_history_service.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A contact whose key starts with the byte ours starts with makes our own
// packets to them look like theirs to us: the destination hash is ours, the
// source hash is theirs, and the shared secret is the same both ways. The
// node drops the copy a repeater relays as a packet it has already seen; the
// RX log carries it all the same, and with direct echo recovery on the app
// decrypted it and showed our message as one from them, with the route bar,
// and acknowledged it. Such a copy is told apart by its content, the packet
// time and the text of a message we sent that contact, whether it comes
// through the RX log or, from a node that forgot its own packet, as an
// ordinary delivery; a message the contact really sent still arrives. The
// messages go into an in-memory database, so the tests are skipped on a
// host that cannot load a native sqlite3.

/// Both keys start with 0x40.
final _selfKey = Uint8List.fromList(List<int>.generate(32, (i) => 0x40 + i));
final _aliceKey = Uint8List.fromList([
  0x40,
  ...List<int>.generate(31, (i) => ((i + 1) * 7 + 2) & 0xFF),
]);

/// The X25519 scalar the node exports. The test's node never signs, so it
/// need not belong to [_selfKey]; the secret with Alice is derived from it
/// on both sides.
final _scalar = Uint8List.fromList(List<int>.generate(32, (i) => 0x11 + i));

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
  header[56] = 7; // sf
  header[57] = 5; // cr
  return Uint8List.fromList([...header, ...utf8.encode(name), 0]);
}

/// RESP_CODE_CONTACT for [key] with one-byte hops along [route].
Uint8List _contactFrame(Uint8List key, String name, {required List<int> route}) {
  final data = ByteData(1 + 32 + 3 + 64 + 32 + 4 + 12);
  final bytes = data.buffer.asUint8List();
  bytes[0] = respCodeContact;
  bytes.setRange(1, 33, key);
  bytes[33] = advTypeChat;
  bytes[35] = route.length;
  bytes.setRange(36, 36 + route.length, route);
  bytes.setRange(100, 100 + name.length, name.codeUnits);
  data.setUint32(132, 1700000000, Endian.little);
  return bytes;
}

/// RESP_CODE_PRIVATE_KEY: the 64-byte key the firmware exports, of which
/// the connector keeps the scalar in front.
Uint8List _privateKeyFrame() =>
    Uint8List.fromList([respCodePrivateKey, ..._scalar, ...Uint8List(32)]);

/// CONTACT_MSG_RECV_V3 as the node delivers a direct message routed to us.
Uint8List _deliveredFrame({
  required Uint8List senderKey,
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
    0xFF,
    txtTypePlain,
    ...timestamp.buffer.asUint8List(),
    ...utf8.encode(text),
    0,
  ]);
}

/// PUSH_CODE_LOG_RX_DATA for a TXT_MSG copy a repeater relayed: routed, one
/// hop still ahead, the [destination] and [source] hashes, then
/// `[timestamp][attempt][text][NUL]` encrypted under [secret] as the firmware
/// encrypts it.
Uint8List _heardTextFrame({
  required int destination,
  required int source,
  required Uint8List secret,
  required int timestampSeconds,
  required List<int> text,
}) {
  final timestamp = ByteData(4)..setUint32(0, timestampSeconds, Endian.little);
  final plaintext = Uint8List.fromList([
    ...timestamp.buffer.asUint8List(),
    txtTypePlain << 2, // attempt 0
    ...text,
    0,
  ]);
  return Uint8List.fromList([
    pushCodeLogRxData,
    40, // snr * 4
    (-70) & 0xFF,
    (payloadTypeTXTMSG << 2) | 0x02, // direct route
    1, // one hop still ahead, one-byte hashes
    0x20,
    destination,
    source,
    ...ChannelEchoRecovery.encryptedPayloadFor(secret, plaintext),
  ]);
}

List<int> _le32(int value) => [
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

/// The packet timestamp of a CMD_SEND_TXT_MSG frame:
/// `[cmd][txt_type][attempt][timestamp(4)][prefix(6)][text][0]`.
int _timestampOf(Uint8List frame) =>
    ByteData.sublistView(frame, 3, 7).getUint32(0, Endian.little);

/// The text of a CMD_SEND_TXT_MSG frame as it went out.
List<int> _textOf(Uint8List frame) => frame.sublist(13, frame.length - 1);

/// RESP_CODE_SENT for the attempt [frame], with a timeout that outlives the
/// test so the service retries nothing meanwhile.
Uint8List _sentFrame(Uint8List frame) => Uint8List.fromList([
  respCodeSent,
  0,
  ..._le32(
    MessageRetryService.computeExpectedAckHash(
      _timestampOf(frame),
      frame[2],
      utf8.decode(_textOf(frame)),
      _selfKey,
    ),
  ),
  ..._le32(60000),
]);

class _FakeStorage extends StorageService {
  final Map<String, ContactPathHistory> _histories = {};

  @override
  Future<void> savePathHistory(
    String contactPubKeyHex,
    ContactPathHistory history,
  ) async {
    _histories[contactPubKeyHex] = history;
  }

  @override
  Future<ContactPathHistory?> loadPathHistory(String contactPubKeyHex) async =>
      _histories[contactPubKeyHex];
}

/// A connected connector whose frames are kept: the node is played by the
/// test through [handleFrameForTest].
class _Connector extends MeshCoreConnector {
  final written = <Uint8List>[];

  @override
  bool get isConnected => true;

  @override
  Future<void> sendFrame(
    Uint8List frame, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    written.add(frame);
  }
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

/// The connector past its handshake, with a retry service wired to it and
/// the test as the node. With [echoRecovery] the node answers the key
/// export the handshake triggers.
class _Node {
  _Node(this.connector, this.retry);

  final _Connector connector;
  final MessageRetryService retry;

  static Future<_Node> start({required bool echoRecovery}) async {
    final connector = _Connector();
    final settings = AppSettingsService();
    await settings.updateSettings(
      settings.settings.copyWith(
        notificationsEnabled: false,
        directEchoRecovery: echoRecovery,
      ),
    );
    connector.attachAppSettingsServiceForTest(settings);
    connector.attachPathHistoryServiceForTest(
      PathHistoryService(_FakeStorage()),
    );
    final retry = MessageRetryService()..retryBackoffMs = (_) => 0;
    connector.attachRetryServiceForTest(retry);
    await connector.refreshDeviceInfo();
    connector.handleFrameForTest(_selfInfoFrame(_selfKey, 'Me'));
    await _settle();
    expect(connector.selfPublicKeyHex, isNotEmpty);
    if (echoRecovery) {
      await _waitFor(
        () => connector.written.any(
          (frame) => frame.isNotEmpty && frame[0] == cmdExportPrivateKey,
        ),
        'the key export request',
      );
      connector.handleFrameForTest(_privateKeyFrame());
      await _settle();
    }
    return _Node(connector, retry);
  }

  Contact get alice => connector.getContactByPubKeyHex(pubKeyToHex(_aliceKey))!;

  /// The secret the node shares with Alice, as the app derives it from the
  /// exported scalar.
  Uint8List get secret => DirectEchoCrypto.sharedSecret(_scalar, _aliceKey);

  /// The node reports Alice two hops away.
  Future<void> contact() async {
    connector.handleFrameForTest(
      _contactFrame(_aliceKey, 'Alice', route: const [0x10, 0x20]),
    );
    await _waitFor(
      () => connector.getContactByPubKeyHex(pubKeyToHex(_aliceKey)) != null,
      'the contact Alice',
    );
  }

  List<Uint8List> get textFrames => [
    for (final frame in connector.written)
      if (frame.isNotEmpty && frame[0] == cmdSendTxtMsg) frame,
  ];

  List<Uint8List> get rawPackets => [
    for (final frame in connector.written)
      if (frame.isNotEmpty && frame[0] == cmdSendRawPacket) frame,
  ];

  /// Sends [text] to Alice, lets the node take it, and hands back the
  /// attempt as the node got it.
  Future<Uint8List> send(String text) async {
    final before = textFrames.length;
    unawaited(retry.sendMessageWithRetry(contact: alice, text: text));
    await _waitFor(() => textFrames.length > before, 'the attempt');
    final frame = textFrames.last;
    connector.handleFrameForTest(_sentFrame(frame));
    await _settle();
    return frame;
  }

  /// The radio heard a copy of the attempt [frame] from the first repeater,
  /// on its way to Alice: our hash as the source, hers as the destination.
  void heardOwnPacket(Uint8List frame) => connector.handleFrameForTest(
    _heardTextFrame(
      destination: _aliceKey[0],
      source: _selfKey[0],
      secret: secret,
      timestampSeconds: _timestampOf(frame),
      text: _textOf(frame),
    ),
  );

  /// The radio heard a copy of a message Alice sent us, one hop away: her
  /// hash as the source, ours as the destination, the same two bytes.
  void heardAlicePacket(String text) => connector.handleFrameForTest(
    _heardTextFrame(
      destination: _selfKey[0],
      source: _aliceKey[0],
      secret: secret,
      timestampSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      text: utf8.encode(text),
    ),
  );

  List<Message> get messages => connector.getMessages(alice);
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final tempDir = Directory.systemTemp.createTempSync('mco_own_echo_');
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

  group('heard through the RX log with direct echo recovery on', () {
    test('our own packet on its way to the contact is not a message from '
        'them and gets no acknowledgement', () async {
      final node = await _Node.start(echoRecovery: true);
      await node.contact();
      final frame = await node.send('Как ты?');

      node.heardOwnPacket(frame);
      await _settle();

      expect(node.messages.map((m) => m.isOutgoing), [true]);
      expect(node.rawPackets, isEmpty);
    });

    test('a message the contact sent still arrives', () async {
      final node = await _Node.start(echoRecovery: true);
      await node.contact();
      await node.send('Как ты?');

      node.heardAlicePacket('Нормально');
      await _waitFor(
        () => node.messages.any((m) => !m.isOutgoing),
        "Alice's message",
      );
      await _settle();

      final incoming = node.messages.singleWhere((m) => !m.isOutgoing);
      expect(incoming.text, 'Нормально');
      expect(incoming.deliveryProgressTotalSteps, 2);
    });
  }, skip: skip);

  group('delivered by the node with direct echo recovery off', () {
    test('our own packet is not a message from the contact', () async {
      final node = await _Node.start(echoRecovery: false);
      await node.contact();
      final frame = await node.send('Как ты?');

      node.connector.handleFrameForTest(
        _deliveredFrame(
          senderKey: _aliceKey,
          timestampSeconds: _timestampOf(frame),
          text: utf8.decode(_textOf(frame)),
        ),
      );
      await _settle();

      expect(node.messages.map((m) => m.isOutgoing), [true]);
    });

    test('the same text sent by the contact a second later is a message',
        () async {
      final node = await _Node.start(echoRecovery: false);
      await node.contact();
      final frame = await node.send('Как ты?');

      node.connector.handleFrameForTest(
        _deliveredFrame(
          senderKey: _aliceKey,
          timestampSeconds: _timestampOf(frame) + 1,
          text: utf8.decode(_textOf(frame)),
        ),
      );
      await _waitFor(
        () => node.messages.any((m) => !m.isOutgoing),
        "Alice's message",
      );

      expect(node.messages.where((m) => !m.isOutgoing).single.text, 'Как ты?');
    });
  }, skip: skip);
}
