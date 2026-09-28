import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Invariants of what the RX log feeds into the two repeater lists behind the
// SNR indicators and the routing sheet, and of what an overheard advert does
// to a stored contact. Pinned before the notifications around them change:
// the data must keep arriving whichever signal carries it to the widgets.

Uint8List _key(int first) => Uint8List.fromList(
  List<int>.generate(32, (i) => i == 0 ? first : (i * 7 + first) & 0xFF),
);

Uint8List _contactFrame(
  int code,
  Uint8List key,
  String name, {
  int type = advTypeChat,
}) {
  final data = ByteData(1 + 32 + 3 + 64 + 32 + 4 + 12);
  final bytes = data.buffer.asUint8List();
  bytes[0] = code;
  bytes.setRange(1, 33, key);
  bytes[33] = type;
  bytes[35] = 0xFF; // path unknown
  bytes.setRange(100, 100 + name.length, name.codeUnits);
  data.setUint32(132, 1700000000, Endian.little);
  return bytes;
}

/// `PUSH_CODE_LOG_RX_DATA` as the companion writes it: the SNR and RSSI
/// bytes, the packet header (route type in the low two bits, payload type
/// above it), the packed path byte (hash width in the top two bits, hop count
/// below), the hops and the payload. A flood route carries no transport bytes.
Uint8List _rxLogFrame({
  required int payloadType,
  required List<List<int>> hops,
  required List<int> payload,
  int hashWidth = 1,
  double snr = 10,
}) {
  final pathLenRaw = hops.isEmpty ? 0 : (((hashWidth - 1) << 6) | hops.length);
  return Uint8List.fromList([
    pushCodeLogRxData,
    (snr * 4).round(),
    (-60) & 0xFF,
    (payloadType << 2) | 0x01,
    pathLenRaw,
    for (final hop in hops) ...hop,
    ...payload,
  ]);
}

/// An advert payload: key, timestamp, an unchecked signature, the flags byte
/// (type, no location) and the name.
List<int> _advert(
  Uint8List key, {
  required int timestamp,
  int type = advTypeRepeater,
  String? name,
}) => [
  ...key,
  timestamp & 0xFF,
  (timestamp >> 8) & 0xFF,
  (timestamp >> 16) & 0xFF,
  (timestamp >> 24) & 0xFF,
  ...List<int>.filled(64, 0),
  type | (name != null ? 0x80 : 0),
  if (name != null) ...name.codeUnits,
  if (name != null) 0,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final tempDir = Directory.systemTemp.createTempSync('mco_repeater_activity_');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  void relayedAck(
    MeshCoreConnector connector,
    List<List<int>> hops, {
    int hashWidth = 1,
    double snr = 10,
  }) {
    connector.handleFrameForTest(
      _rxLogFrame(
        payloadType: payloadTypeACK,
        hops: hops,
        hashWidth: hashWidth,
        snr: snr,
        payload: const [1, 2, 3, 4, 5, 6],
      ),
    );
  }

  group('repeater activity from the RX log', () {
    test('a directly heard packet records no repeater', () {
      final connector = MeshCoreConnector();
      relayedAck(connector, const []);
      expect(connector.activeRepeaters, isEmpty);
    });

    test('a relayed packet records its last hop with the reading', () {
      final connector = MeshCoreConnector();
      relayedAck(connector, const [
        [0x11],
        [0x22],
      ], snr: 7.5);

      final entry = connector.activeRepeaters.single;
      expect(entry.pubkeyPrefix, [0x22]);
      expect(entry.pathHashWidth, 1);
      expect(entry.snr, 7.5);
      expect(entry.contactKeyHex, isNull);
    });

    test('the same hop again updates the entry in place', () {
      final connector = MeshCoreConnector();
      relayedAck(connector, const [
        [0x22],
      ], snr: 7.5);
      relayedAck(connector, const [
        [0x11],
        [0x22],
      ], snr: 3);

      final entry = connector.activeRepeaters.single;
      expect(entry.pubkeyPrefix, [0x22]);
      expect(entry.snr, 3);
    });

    test('two-byte hashes keep the last two bytes as the hop', () {
      final connector = MeshCoreConnector();
      relayedAck(connector, const [
        [0x11, 0x12],
        [0x22, 0x23],
      ], hashWidth: 2);

      final entry = connector.activeRepeaters.single;
      expect(entry.pubkeyPrefix, [0x22, 0x23]);
      expect(entry.pathHashWidth, 2);
    });

    test('the hop is attributed to the one repeater contact sharing its prefix',
        () {
      final connector = MeshCoreConnector();
      connector.handleFrameForTest(
        _contactFrame(respCodeContact, _key(0x22), 'Rep', type: advTypeRepeater),
      );
      connector.handleFrameForTest(
        _contactFrame(respCodeContact, _key(0x33), 'Bob'),
      );
      connector.handleFrameForTest(
        _contactFrame(respCodeContact, _key(0x44), 'RepA', type: advTypeRepeater),
      );
      connector.handleFrameForTest(
        _contactFrame(
          respCodeContact,
          Uint8List.fromList([0x44, ..._key(0x45).sublist(1)]),
          'RepB',
          type: advTypeRepeater,
        ),
      );
      final rep = connector.contacts.firstWhere((c) => c.name == 'Rep');

      relayedAck(connector, const [
        [0x22],
      ]);
      relayedAck(connector, const [
        [0x33],
      ]);
      relayedAck(connector, const [
        [0x44],
      ]);

      final byPrefix = {
        for (final r in connector.activeRepeaters) r.pubkeyPrefix.first: r,
      };
      expect(byPrefix[0x22]?.contactKeyHex, rep.publicKeyHex);
      // A chat contact is never a relay, and two repeaters sharing the prefix
      // leave it unattributed.
      expect(byPrefix[0x33]?.contactKeyHex, isNull);
      expect(byPrefix[0x44]?.contactKeyHex, isNull);
    });

    test('activity is capped at ten repeaters', () {
      final connector = MeshCoreConnector();
      for (var hop = 1; hop <= 11; hop++) {
        relayedAck(connector, [
          [hop],
        ]);
      }
      expect(connector.activeRepeaters.length, 10);
      expect(
        connector.activeRepeaters.map((r) => r.pubkeyPrefix.first),
        contains(11),
      );
    });

    test('relayed packets leave the contact lists alone', () {
      final connector = MeshCoreConnector();
      connector.handleFrameForTest(
        _contactFrame(respCodeContact, _key(0x22), 'Rep', type: advTypeRepeater),
      );
      connector.handleFrameForTest(
        _contactFrame(pushCodeNewAdvert, _key(0x33), 'Bob'),
      );
      final contactsBefore = connector.contactsRevision;
      final discoveredBefore = connector.discoveredRevision;
      // The discovered list mirrors the node's contacts as active entries, so
      // it holds Rep as well as Bob here; only its shape matters below.
      final discoveredNames = connector.discoveredContacts
          .map((c) => c.name)
          .toList();
      expect(discoveredNames, contains('Bob'));

      relayedAck(connector, const [
        [0x22],
      ]);
      relayedAck(connector, const [
        [0x33],
      ]);
      relayedAck(connector, const [
        [0x22],
      ], snr: 1);

      expect(connector.contactsRevision, contactsBefore);
      expect(connector.discoveredRevision, discoveredBefore);
      expect(connector.contacts.single.name, 'Rep');
      expect(
        connector.discoveredContacts.map((c) => c.name).toList(),
        discoveredNames,
      );
    });
  });

  group('direct repeaters from adverts', () {
    const later = 1700001000;

    test('a stored repeater heard directly enters the direct repeaters and '
        'refreshes the contact', () {
      final connector = MeshCoreConnector();
      connector.handleFrameForTest(
        _contactFrame(respCodeContact, _key(0x22), 'Rep', type: advTypeRepeater),
      );
      final rep = connector.contacts.single;

      connector.handleFrameForTest(
        _rxLogFrame(
          payloadType: payloadTypeADVERT,
          hops: const [],
          snr: 6,
          payload: _advert(_key(0x22), timestamp: later, name: 'Rep'),
        ),
      );

      final direct = connector.directRepeaters.single;
      expect(direct.pubkeyPrefix, [0x22]);
      expect(direct.contactKeyHex, rep.publicKeyHex);
      expect(direct.snr, 6);
      expect(
        connector.contacts.single.lastSeen,
        DateTime.fromMillisecondsSinceEpoch(later * 1000),
      );
    });

    test('an advert with a new name updates the stored contact and bumps the '
        'revision', () {
      final connector = MeshCoreConnector();
      connector.handleFrameForTest(
        _contactFrame(respCodeContact, _key(0x22), 'Rep', type: advTypeRepeater),
      );
      final before = connector.contactsRevision;

      connector.handleFrameForTest(
        _rxLogFrame(
          payloadType: payloadTypeADVERT,
          hops: const [],
          payload: _advert(_key(0x22), timestamp: later, name: 'Rep2'),
        ),
      );

      expect(connector.contacts.single.name, 'Rep2');
      expect(connector.contactsRevision, isNot(before));
    });

    test('a chat advert heard directly adds nothing to the direct repeaters',
        () {
      final connector = MeshCoreConnector();
      connector.handleFrameForTest(
        _rxLogFrame(
          payloadType: payloadTypeADVERT,
          hops: const [],
          payload: _advert(
            _key(0x33),
            timestamp: later,
            type: advTypeChat,
            name: 'Bob',
          ),
        ),
      );

      expect(connector.directRepeaters, isEmpty);
      expect(connector.discoveredContacts.map((c) => c.name), contains('Bob'));
    });

    test('a relayed advert of an unknown node records the relaying hop', () {
      final connector = MeshCoreConnector();
      connector.handleFrameForTest(
        _rxLogFrame(
          payloadType: payloadTypeADVERT,
          hops: const [
            [0x55],
          ],
          payload: _advert(
            _key(0x33),
            timestamp: later,
            type: advTypeChat,
            name: 'Bob',
          ),
        ),
      );

      expect(connector.directRepeaters.single.pubkeyPrefix, [0x55]);
      expect(connector.activeRepeaters.single.pubkeyPrefix, [0x55]);
    });

    test('a fresh advert of a stored contact reaches the connector listeners',
        () async {
      final connector = MeshCoreConnector();
      connector.handleFrameForTest(
        _contactFrame(respCodeContact, _key(0x22), 'Rep', type: advTypeRepeater),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final before = connector.uiRevision;

      connector.handleFrameForTest(
        _rxLogFrame(
          payloadType: payloadTypeADVERT,
          hops: const [],
          payload: _advert(_key(0x22), timestamp: later, name: 'Rep'),
        ),
      );
      // Notifications are coalesced into a 50 ms window.
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(connector.uiRevision, greaterThan(before));
    });
  });
}
