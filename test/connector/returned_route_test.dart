import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/path_history.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/services/path_history_service.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A route the recipient returns (the node's PUSH_CODE_PATH_UPDATED, then its
// answer to the contact re-read the app asks for) becomes the contact's route
// and joins its history once, a record already there refreshed rather than
// added twice, while an override the user set outlives it. The last two
// tests are the change: the history credits that route as having just
// worked, a record already there keeping what it had.

final _key = Uint8List.fromList(List<int>.generate(32, (i) => 0xAA + i));

/// RESP_CODE_CONTACT for [_key]: one-byte hops along [route], or no known
/// path when it is null.
Uint8List _contactFrame({List<int>? route}) {
  final data = ByteData(1 + 32 + 3 + 64 + 32 + 4 + 12);
  final bytes = data.buffer.asUint8List();
  bytes[0] = respCodeContact;
  bytes.setRange(1, 33, _key);
  bytes[33] = advTypeChat;
  if (route == null) {
    bytes[35] = 0xFF;
  } else {
    bytes[35] = route.length;
    bytes.setRange(36, 36 + route.length, route);
  }
  bytes.setRange(100, 105, 'Alice'.codeUnits);
  data.setUint32(132, 1700000000, Endian.little);
  return bytes;
}

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

/// A connected node that keeps what the app writes to it.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Connector connector;
  late PathHistoryService paths;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    connector = _Connector();
    paths = PathHistoryService(_FakeStorage());
    connector.attachPathHistoryServiceForTest(paths);
    connector.handleFrameForTest(_contactFrame());
    await pumpEventQueue();
  });

  /// The node took [route] from the recipient's answer and says so; the app
  /// asks for the contact and the node answers.
  Future<void> returnRoute(List<int> route) async {
    connector.handleFrameForTest([pushCodePathUpdated, ..._key]);
    await pumpEventQueue();
    connector.handleFrameForTest(_contactFrame(route: route));
    await pumpEventQueue();
  }

  List<List<int>> historyRoutes() => paths
      .getRecentPaths(connector.contacts.single.publicKeyHex)
      .map((record) => record.pathBytes)
      .toList();

  test('the node reporting a new route makes the app ask for the '
      'contact', () async {
    connector.handleFrameForTest([pushCodePathUpdated, ..._key]);
    await pumpEventQueue();

    final reads = connector.written.where(
      (frame) =>
          frame[0] == cmdGetContactByKey &&
          listEquals(frame.sublist(1, 33), _key),
    );
    expect(reads, hasLength(1));
  });

  test('the returned route becomes the contact\'s route and joins its '
      'history', () async {
    await returnRoute([0x33]);

    final contact = connector.contacts.single;
    expect(contact.pathLength, 1);
    expect(contact.path, [0x33]);
    expect(historyRoutes(), [
      [0x33],
    ]);
  });

  test('a route already in the history is refreshed, not added '
      'twice', () async {
    final known = connector.contacts.single;
    paths.handlePathUpdated(
      known.copyWith(pathLength: 1, path: Uint8List.fromList([0x33])),
    );
    paths.handlePathUpdated(
      known.copyWith(pathLength: 1, path: Uint8List.fromList([0x44])),
    );
    await pumpEventQueue();
    expect(historyRoutes(), [
      [0x44],
      [0x33],
    ]);

    await returnRoute([0x33]);

    expect(historyRoutes(), [
      [0x33],
      [0x44],
    ]);
  });

  test('an override the user set outlives the returned route', () async {
    await connector.setPathOverride(connector.contacts.single, pathLen: -1);

    await returnRoute([0x33]);

    final contact = connector.contacts.single;
    expect(contact.pathOverride, -1);
    expect(contact.path, [0x33]);
  });

  test('the returned route is credited as having just worked', () async {
    await returnRoute([0x33]);

    final record = paths
        .getRecentPaths(connector.contacts.single.publicKeyHex)
        .single;
    expect(record.pathBytes, [0x33]);
    expect(record.successCount, 1);
    expect(record.timestamp, isNotNull);
  });

  test('a route the history holds keeps its failures and gains the '
      'success', () async {
    final keyHex = connector.contacts.single.publicKeyHex;
    paths.recordPathResult(
      keyHex,
      const PathSelection(pathBytes: [0x33], hopCount: 1, useFlood: false),
      success: false,
    );
    await pumpEventQueue();
    expect(paths.getRecentPaths(keyHex).single.timestamp, isNull);

    await returnRoute([0x33]);

    final record = paths.getRecentPaths(keyHex).single;
    expect(record.failureCount, 1);
    expect(record.successCount, 1);
    expect(record.timestamp, isNotNull);
  });
}
