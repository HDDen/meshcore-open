import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/models/path_history.dart';
import 'package:meshcore_open/services/message_retry_service.dart';
import 'package:meshcore_open/services/path_history_service.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The route a direct message was delivered along, as the connector records
// it on the message once the node confirms the delivery
// (`Message.deliveryPathBytes`). The node is played by the test: it takes
// each attempt with RESP_CODE_SENT, naming the ACK hash as the firmware
// computes it, and confirms a delivery with PUSH_CODE_SEND_CONFIRMED. A bare
// acknowledgement names an attempt, and the route recorded is that attempt's
// even when a retry has since gone out by another route, which is what the
// message's own path shows. An acknowledgement inside a path return comes
// with the node's PUSH_CODE_PATH_UPDATED in the frame before it, and the
// route recorded is the one the node read back, the path the flood took to
// the recipient; a path return announced earlier is not its carrier. A
// delivery without repeaters is an empty route, not an unknown one, and a
// flood acknowledged without a path return keeps no route rather than the
// contact's current one. A send stopped by hand records its route too. The
// fifth attempt shares the first one's ACK hash, and the acknowledgement
// packet heard in the RX log right before the confirmation says which of
// the two was answered. The messages go into an in-memory database, so the
// tests are skipped on a host that cannot load a native sqlite3.

final _selfKey = Uint8List.fromList(List<int>.generate(32, (i) => 0x40 + i));
final _aliceKey = Uint8List.fromList(
  List<int>.generate(32, (i) => (i * 7 + 2) & 0xFF),
);

/// RESP_CODE_SELF_INFO: the node's type, TX power, key, position, flags,
/// radio parameters (SF7 at 500 kHz, so the physics timeouts are short) and
/// name.
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
  data.setUint32(52, 500000, Endian.little);
  header[56] = 7; // sf
  header[57] = 5; // cr
  return Uint8List.fromList([...header, ...utf8.encode(name), 0]);
}

/// RESP_CODE_CONTACT for [key]: hops of [width] bytes along [route], or no
/// known route with [noRoute].
Uint8List _contactFrame(
  Uint8List key,
  String name, {
  List<int> route = const [],
  int width = 1,
  bool noRoute = false,
}) {
  final data = ByteData(1 + 32 + 3 + 64 + 32 + 4 + 12);
  final bytes = data.buffer.asUint8List();
  bytes[0] = respCodeContact;
  bytes.setRange(1, 33, key);
  bytes[33] = advTypeChat;
  bytes[35] = noRoute ? 0xFF : ((width - 1) << 6) | (route.length ~/ width);
  bytes.setRange(36, 36 + route.length, route);
  bytes.setRange(100, 100 + name.length, name.codeUnits);
  data.setUint32(132, 1700000000, Endian.little);
  return bytes;
}

Uint8List _le32(int value) => Uint8List.fromList([
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
]);

/// The ACK hash the node expects for the text message [frame] the connector
/// wrote, computed as the firmware computes it: from the frame's timestamp,
/// attempt byte and text, with our key.
int _ackHashOf(Uint8List frame) {
  // [cmd][txt_type][attempt][timestamp(4)][prefix(6)][text][0]
  final timestamp = ByteData.sublistView(
    frame,
    3,
    7,
  ).getUint32(0, Endian.little);
  final text = utf8.decode(frame.sublist(13, frame.length - 1));
  return MessageRetryService.computeExpectedAckHash(
    timestamp,
    frame[2],
    text,
    _selfKey,
  );
}

/// RESP_CODE_SENT for the attempt [frame]: whether the packet floods, the ACK
/// hash the node expects and its timeout estimate.
Uint8List _sentFrame(
  Uint8List frame, {
  required bool flood,
  int timeoutMs = 5000,
}) => Uint8List.fromList([
  respCodeSent,
  flood ? 1 : 0,
  ..._le32(_ackHashOf(frame)),
  ..._le32(timeoutMs),
]);

/// PUSH_CODE_SEND_CONFIRMED for the attempt [frame].
Uint8List _confirmedFrame(Uint8List frame) => Uint8List.fromList([
  pushCodeSendConfirmed,
  ..._le32(_ackHashOf(frame)),
  ..._le32(1200),
]);

/// PUSH_CODE_LOG_RX_DATA for the acknowledgement of the attempt [frame] as
/// the radio heard it: a direct packet over one hop whose payload is the
/// hash, the attempt byte the recipient copied from our packet and a random
/// byte.
Uint8List _heardAckFrame(Uint8List frame, {required int attemptByte}) =>
    Uint8List.fromList([
      pushCodeLogRxData,
      40, // snr * 4
      (-70) & 0xFF,
      (payloadTypeACK << 2) | 0x02, // direct route
      1, // one hop
      0x10,
      ..._le32(_ackHashOf(frame)),
      attemptByte,
      0x5A,
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
/// the test as the node.
class _Node {
  _Node(this.connector, this.retry);

  final _Connector connector;
  final MessageRetryService retry;

  static Future<_Node> start() async {
    final connector = _Connector();
    connector.attachPathHistoryServiceForTest(
      PathHistoryService(_FakeStorage()),
    );
    final retry = MessageRetryService()..retryBackoffMs = (_) => 0;
    connector.attachRetryServiceForTest(retry);
    // The handshake as a connection runs it: the request marks the answer
    // as the one that binds the stores to the node.
    await connector.refreshDeviceInfo();
    connector.handleFrameForTest(_selfInfoFrame(_selfKey, 'Me'));
    await _settle();
    expect(connector.selfPublicKeyHex, isNotEmpty);
    return _Node(connector, retry);
  }

  Contact get alice => connector.getContactByPubKeyHex(pubKeyToHex(_aliceKey))!;

  /// The node reports Alice with [route] in hops of [width] bytes, or with
  /// no route; this is also how it answers the re-read a path change starts.
  Future<void> contact({
    List<int> route = const [],
    int width = 1,
    bool noRoute = false,
  }) async {
    connector.handleFrameForTest(
      _contactFrame(
        _aliceKey,
        'Alice',
        route: route,
        width: width,
        noRoute: noRoute,
      ),
    );
    await _waitFor(() {
      final contact = connector.getContactByPubKeyHex(pubKeyToHex(_aliceKey));
      return contact != null &&
          contact.pathLength == (noRoute ? -1 : route.length ~/ width) &&
          listEquals(contact.path, route);
    }, 'the contact Alice');
  }

  List<Uint8List> get textFrames => [
    for (final frame in connector.written)
      if (frame[0] == cmdSendTxtMsg) frame,
  ];

  /// Sends [text] to Alice and hands back the attempt as the node got it.
  Future<Uint8List> send(String text) async {
    final before = textFrames.length;
    unawaited(retry.sendMessageWithRetry(contact: alice, text: text));
    await _waitFor(() => textFrames.length > before, 'the attempt');
    return textFrames.last;
  }

  /// The retry the service sends by itself after the ACK of the attempt
  /// before it timed out.
  Future<Uint8List> retryAfter(int attempts) async {
    await _waitFor(() => textFrames.length > attempts, 'the retry');
    return textFrames.last;
  }

  /// The node took the attempt [frame]. After a flood the connector asks
  /// the node for its default scope, to stamp the message's region, and the
  /// node answers that it has none.
  void sent(Uint8List frame, {bool flood = false, int timeoutMs = 5000}) {
    connector.handleFrameForTest(
      _sentFrame(frame, flood: flood, timeoutMs: timeoutMs),
    );
    if (flood) connector.handleFrameForTest([respCodeDefaultFloodScope]);
  }

  /// The node confirms the delivery of the attempt [frame].
  void confirmed(Uint8List frame) =>
      connector.handleFrameForTest(_confirmedFrame(frame));

  /// The radio heard the acknowledgement of the attempt [frame], which the
  /// node logs before it confirms the delivery.
  void heardAck(Uint8List frame, {required int attemptByte}) =>
      connector.handleFrameForTest(
        _heardAckFrame(frame, attemptByte: attemptByte),
      );

  /// The node announces that it took a new route for Alice from her answer.
  void pathUpdated() =>
      connector.handleFrameForTest([pushCodePathUpdated, ..._aliceKey]);

  Message get message => connector.getMessages(alice).single;
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final tempDir = Directory.systemTemp.createTempSync('mco_delivery_route_');
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

  group('a bare acknowledgement', () {
    test('records the route of the attempt it answers', () async {
      final node = await _Node.start();
      addTearDown(node.retry.dispose);
      await node.contact(route: [0x10]);

      final attempt = await node.send('hi');
      node.sent(attempt);
      node.confirmed(attempt);
      await _waitFor(() => node.message.deliveryPathBytes != null, 'the route');

      expect(node.message.status, MessageStatus.delivered);
      expect(node.message.deliveryPathBytes, [0x10]);
      expect(node.message.deliveryPathHashWidth, 1);
    });

    test('keeps the width of the hops', () async {
      final node = await _Node.start();
      addTearDown(node.retry.dispose);
      await node.contact(route: [0x12, 0x34, 0x56, 0x78], width: 2);

      final attempt = await node.send('hi');
      node.sent(attempt);
      node.confirmed(attempt);
      await _waitFor(() => node.message.deliveryPathBytes != null, 'the route');

      expect(node.message.deliveryPathBytes, [0x12, 0x34, 0x56, 0x78]);
      expect(node.message.deliveryPathHashWidth, 2);
    });

    test('records a delivery without repeaters as an empty route', () async {
      final node = await _Node.start();
      addTearDown(node.retry.dispose);
      await node.contact(route: []);

      final attempt = await node.send('hi');
      node.sent(attempt);
      node.confirmed(attempt);
      await _waitFor(() => node.message.deliveryPathBytes != null, 'the route');

      expect(node.message.deliveryPathBytes, isEmpty);
    });

    test('of the first attempt, arriving after a retry went out by another '
        'route, records the first attempt\'s route', () async {
      final node = await _Node.start();
      addTearDown(node.retry.dispose);
      await node.contact(route: [0x10]);

      final first = await node.send('hi');
      // The node's estimate is clamped up to the physics minimum, under a
      // second at SF7, which is how long the retry takes to go out.
      node.sent(first, timeoutMs: 1);
      // Meanwhile the recipient's answer to something else leaves another
      // route on the node, which the retry takes.
      node.pathUpdated();
      await node.contact(route: [0x20]);
      final retry = await node.retryAfter(1);
      expect(retry[2], 1, reason: 'the attempt byte');
      node.sent(retry);
      expect(node.message.pathBytes, [0x20]);

      node.confirmed(first);
      await _waitFor(() => node.message.deliveryPathBytes != null, 'the route');

      expect(node.message.status, MessageStatus.delivered);
      expect(node.message.deliveryPathBytes, [0x10]);
      expect(node.message.pathBytes, [0x20]);
    });

    test('of a flood, with no path return announced, leaves the message '
        'without a route rather than with the contact\'s', () async {
      final node = await _Node.start();
      addTearDown(node.retry.dispose);
      await node.contact(noRoute: true);

      final attempt = await node.send('hi');
      node.sent(attempt, flood: true);
      node.confirmed(attempt);
      await _waitFor(
        () => node.message.status == MessageStatus.delivered,
        'the delivery',
      );
      await _settle();

      expect(node.message.deliveryPathBytes, isNull);
    });
  }, skip: skip);

  group('an acknowledgement inside a path return', () {
    test('records the route the recipient returned', () async {
      final node = await _Node.start();
      addTearDown(node.retry.dispose);
      await node.contact(noRoute: true);

      final attempt = await node.send('hi');
      node.sent(attempt, flood: true);
      // The recipient's answer: the node stores the returned route,
      // announces it and confirms the delivery in the next frame; the route
      // itself reaches the app with the re-read the announcement started.
      node.pathUpdated();
      node.confirmed(attempt);
      await node.contact(route: [0x33]);
      await _waitFor(() => node.message.deliveryPathBytes != null, 'the route');

      expect(node.message.status, MessageStatus.delivered);
      expect(node.message.deliveryPathBytes, [0x33]);
      expect(node.message.deliveryPathHashWidth, 1);
    });

    test('is told from a bare one by the frame before it: a path return '
        'announced earlier is not its carrier', () async {
      final node = await _Node.start();
      addTearDown(node.retry.dispose);
      await node.contact(route: [0x10]);

      final attempt = await node.send('hi');
      node.sent(attempt);
      // A path return with nothing in it for us, a CLI reply's say: the
      // node announces it and the app reads the new route back.
      node.pathUpdated();
      await node.contact(route: [0x33]);
      node.confirmed(attempt);
      await _waitFor(() => node.message.deliveryPathBytes != null, 'the route');

      expect(node.message.deliveryPathBytes, [0x10]);
    });
  }, skip: skip);

  test('the attempt byte of an acknowledgement heard in the RX log tells the '
      'first attempt from the fifth, which shares its hash', () async {
    final node = await _Node.start();
    addTearDown(node.retry.dispose);
    node.retry.setMaxRetries(6);
    await node.contact(route: [0x10]);

    final first = await node.send('hi');
    var attempt = first;
    for (var number = 1; number <= 4; number++) {
      node.sent(attempt, timeoutMs: 1);
      if (number == 4) {
        // The recipient's answer to something else leaves another route on
        // the node before the fifth attempt, which goes by it.
        node.pathUpdated();
        await node.contact(route: [0x33]);
      }
      attempt = await node.retryAfter(number);
      expect(attempt[2], number, reason: 'the attempt byte');
    }
    final fifth = attempt;
    node.sent(fifth);
    expect(_ackHashOf(fifth), _ackHashOf(first));
    expect(node.message.pathBytes, [0x33]);

    node.heardAck(first, attemptByte: 0);
    node.confirmed(first);
    await _waitFor(() => node.message.deliveryPathBytes != null, 'the route');

    expect(node.message.status, MessageStatus.delivered);
    expect(node.message.deliveryPathBytes, [0x10]);
  }, skip: skip);

  test('a send stopped by hand records the route when its acknowledgement '
      'comes after all', () async {
    final node = await _Node.start();
    addTearDown(node.retry.dispose);
    await node.contact(route: [0x10]);

    final attempt = await node.send('hi');
    node.sent(attempt);
    await node.connector.stopSending(node.alice, node.message);
    expect(node.message.status, MessageStatus.sent);

    node.confirmed(attempt);
    await _waitFor(() => node.message.deliveryPathBytes != null, 'the route');

    expect(node.message.status, MessageStatus.delivered);
    expect(node.message.deliveryPathBytes, [0x10]);
  }, skip: skip);
}
