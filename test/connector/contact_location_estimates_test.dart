import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mco_service/mco_service.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/storage/contact_location_estimate_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What the connector promises about the stored estimates of node positions,
// pinned before it stops clearing every located contact on every save. The
// map estimates where a node without coordinates is and stores the guess; a
// node that then reports coordinates must lose the guess, or the map shows
// the old one again when the node loses its coordinates later, and never
// recalculates it. A node without coordinates keeps its guess while other
// nodes are saved, and the app's discovered list follows the same rule as
// the node's contacts. The history goes into an in-memory database, so the
// tests are skipped on a host that cannot load a native sqlite3.

const int _timestamp = 1700000000;

Uint8List _key(int first) => Uint8List.fromList(
  List<int>.generate(32, (i) => i == 0 ? first : (i * 7 + first) & 0xFF),
);

/// A key as the estimate store spells it.
String _hexOf(Uint8List key) => pubKeyToHex(key).toLowerCase();

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

/// RESP_CODE_CONTACT, or PUSH_CODE_NEW_ADVERT under [code], for a node with
/// no route: the key, the type, the path byte, the name, the advert time and
/// the position in millionths of a degree (0,0 for none).
Uint8List _contactFrame(
  Uint8List key,
  String name, {
  int code = respCodeContact,
  int type = advTypeChat,
  double? latitude,
  double? longitude,
  int advertTime = _timestamp,
}) {
  final data = ByteData(1 + 32 + 3 + 64 + 32 + 4 + 12);
  final bytes = data.buffer.asUint8List();
  bytes[0] = code;
  bytes.setRange(1, 33, key);
  bytes[33] = type;
  bytes[35] = 0xFF; // path unknown
  bytes.setRange(100, 100 + name.length, name.codeUnits);
  data.setUint32(132, advertTime, Endian.little);
  data.setInt32(136, ((latitude ?? 0) * 1e6).round(), Endian.little);
  data.setInt32(140, ((longitude ?? 0) * 1e6).round(), Endian.little);
  return bytes;
}

/// Lets a frame run to the end: the handlers write the store and clear the
/// estimates on the event queue.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

Future<void> _waitUntil(
  Future<bool> Function() condition,
  String what,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<String?> _sqliteProblem() async {
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
}

/// A connected connector whose frames go nowhere: the node is played by the
/// test through [handleFrameForTest].
class _Connector extends MeshCoreConnector {
  @override
  bool get isConnected => true;

  @override
  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {}
}

/// A connector past its handshake, with the estimate store the map writes.
class _Harness {
  _Harness(this.connector);

  final _Connector connector;
  final ContactLocationEstimateStore store = ContactLocationEstimateStore();

  static Future<_Harness> start() async {
    final connector = _Connector();
    // The handshake as a connection runs it: the request marks the answer
    // as the one that binds the stores to the node.
    await connector.refreshDeviceInfo();
    connector.handleFrameForTest(_selfInfoFrame(_key(1), 'Me'));
    await _settle();
    expect(connector.selfPublicKeyHex, isNotEmpty);
    return _Harness(connector);
  }

  /// The node reports [name] as a stored contact, with [latitude] and
  /// [longitude] when it has them.
  Future<Contact> contact(
    Uint8List key,
    String name, {
    double? latitude,
    double? longitude,
  }) async {
    connector.handleFrameForTest(
      _contactFrame(key, name, latitude: latitude, longitude: longitude),
    );
    final hex = pubKeyToHex(key);
    await _waitUntil(
      () async =>
          connector.getContactByPubKeyHex(hex) != null &&
          connector.getContactByPubKeyHex(hex)!.hasLocation ==
              (latitude != null),
      'the contact $name',
    );
    await _settle();
    return connector.getContactByPubKeyHex(hex)!;
  }

  /// The node heard an advert of [name], a node it does not store.
  Future<Contact> advert(
    Uint8List key,
    String name, {
    double? latitude,
    double? longitude,
    int advertTime = _timestamp,
  }) async {
    connector.handleFrameForTest(
      _contactFrame(
        key,
        name,
        code: pushCodeNewAdvert,
        latitude: latitude,
        longitude: longitude,
        advertTime: advertTime,
      ),
    );
    final hex = pubKeyToHex(key);
    Contact? found() => connector.discoveredContacts
        .cast<Contact?>()
        .firstWhere((c) => c?.publicKeyHex == hex, orElse: () => null);
    await _waitUntil(
      () async => found()?.hasLocation == (latitude != null),
      'the discovered node $name',
    );
    await _settle();
    return found()!;
  }

  /// Stores the map's estimate for [key], a node it found no coordinates for.
  Future<void> plantEstimate(Uint8List key, String name) =>
      store.saveContactLocations(
        candidates: [
          McoContactLocationCandidate(
            publicKey: key,
            name: name,
            contactType: advTypeRepeater,
            pathBytes: const [],
            lastSeen: DateTime.fromMillisecondsSinceEpoch(_timestamp * 1000),
          ),
        ],
        estimates: [
          McoEstimatedContactLocation(
            publicKeyHex: pubKeyToHex(key),
            name: name,
            contactType: advTypeRepeater,
            latitude: 55.7,
            longitude: 37.6,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(_timestamp * 1000),
            anchorPublicKeys: [_key(9)],
            anchorLatitudes: const [55.8],
            anchorLongitudes: const [37.5],
            highConfidence: true,
          ),
        ],
        clearEstimateKeys: const [],
      );

  Future<Set<String>> estimatedKeys() async => {
    for (final estimate in await store.loadEstimates())
      estimate.publicKeyHex.toLowerCase(),
  };
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = await _sqliteProblem();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final tempDir = Directory.systemTemp.createTempSync('mco_estimates_');
  final aliceKey = _key(2);
  final bobKey = _key(3);
  final dieterKey = _key(4);

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
    await MessageHistoryStorage.instance.resetForTesting();
    PrefsManager.reset();
  });

  group('the node\'s contacts', () {
    test('a contact that reports coordinates loses its estimate', () async {
      final harness = await _Harness.start();
      await harness.contact(aliceKey, 'Alice');
      await harness.plantEstimate(aliceKey, 'Alice');
      expect(await harness.estimatedKeys(), {_hexOf(aliceKey)});

      final alice = await harness.contact(
        aliceKey,
        'Alice',
        latitude: 55.2,
        longitude: 37.2,
      );
      expect(alice.hasLocation, isTrue);

      await _waitUntil(
        () async => (await harness.estimatedKeys()).isEmpty,
        'the estimate to go',
      );
      // The row stays, with the estimate gone.
      final row = (await MessageHistoryStorage.instance
              .loadContactLocationCache())
          .single;
      expect(row.publicKeyHex, _hexOf(aliceKey));
      expect(row.estimatedLatitude, isNull);
    });

    test('a contact without coordinates keeps its estimate while others are '
        'saved', () async {
      final harness = await _Harness.start();
      await harness.contact(aliceKey, 'Alice');
      await harness.plantEstimate(aliceKey, 'Alice');

      // Bob arrives with coordinates: his save clears him, not Alice.
      await harness.contact(bobKey, 'Bob', latitude: 55.3, longitude: 37.3);
      // Alice heard again without coordinates: still nothing to clear.
      await harness.contact(aliceKey, 'Alice');
      await _settle();

      expect(await harness.estimatedKeys(), {_hexOf(aliceKey)});
    });
  }, skip: skip);

  group('the app\'s discovered nodes', () {
    test('a discovered node that reports coordinates loses its estimate',
        () async {
      final harness = await _Harness.start();
      await harness.advert(dieterKey, 'Dieter');
      await harness.plantEstimate(dieterKey, 'Dieter');
      expect(await harness.estimatedKeys(), {_hexOf(dieterKey)});

      final dieter = await harness.advert(
        dieterKey,
        'Dieter',
        latitude: 55.4,
        longitude: 37.4,
        advertTime: _timestamp + 60,
      );
      expect(dieter.hasLocation, isTrue);

      await _waitUntil(
        () async => (await harness.estimatedKeys()).isEmpty,
        'the estimate to go',
      );
    });

    test('a discovered node without coordinates keeps its estimate while '
        'others are heard', () async {
      final harness = await _Harness.start();
      await harness.advert(dieterKey, 'Dieter');
      await harness.plantEstimate(dieterKey, 'Dieter');

      await harness.advert(bobKey, 'Bob', latitude: 55.3, longitude: 37.3);
      await harness.advert(dieterKey, 'Dieter', advertTime: _timestamp + 60);
      await _settle();

      expect(await harness.estimatedKeys(), {_hexOf(dieterKey)});
    });
  }, skip: skip);
}
