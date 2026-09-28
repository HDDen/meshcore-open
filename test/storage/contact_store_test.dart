import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/storage/contact_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What ContactStore promises, pinned on its preference form before the
// contacts move into the database: every field of a contact survives a
// save, each node keeps its own list, a save replaces the list whole.

const nodeA = '7020f1bd19aabbccddeeff00112233445566778899aabbccddeeff0011223344';
const nodeB = 'afdad95d3a00112233445566778899aabbccddeeff00112233445566778899aa';

Contact contact(
  int n, {
  int pathLength = 1,
  int pathHashWidth = 1,
  int? pathOverride,
  Uint8List? pathOverrideBytes,
  double? latitude,
  double? longitude,
  DateTime? lastModified,
  bool hasMessages = false,
  bool isActive = true,
  Uint8List? rawPacket,
}) => Contact(
  publicKey: Uint8List.fromList(
    List<int>.generate(32, (i) => (n * 7 + i) & 0xFF),
  ),
  name: 'Node $n',
  type: n % 4,
  flags: n,
  pathLength: pathLength,
  path: Uint8List.fromList(
    List<int>.generate(
      pathLength < 0 ? 0 : pathLength * pathHashWidth,
      (i) => 0xA0 + i,
    ),
  ),
  pathHashWidth: pathHashWidth,
  pathOverride: pathOverride,
  pathOverrideBytes: pathOverrideBytes,
  latitude: latitude,
  longitude: longitude,
  lastSeen: DateTime.fromMillisecondsSinceEpoch(1758000000000 + n * 1000),
  lastModified: lastModified,
  lastMessageAt: DateTime.fromMillisecondsSinceEpoch(1758100000000 + n * 1000),
  hasMessages: hasMessages,
  isActive: isActive,
  rawPacket: rawPacket,
);

void expectSameContact(Contact actual, Contact expected) {
  expect(actual.publicKey, expected.publicKey);
  expect(actual.name, expected.name);
  expect(actual.type, expected.type);
  expect(actual.flags, expected.flags);
  expect(actual.pathLength, expected.pathLength);
  expect(actual.path, expected.path);
  expect(actual.pathHashWidth, expected.pathHashWidth);
  expect(actual.pathOverride, expected.pathOverride);
  expect(actual.pathOverrideBytes, expected.pathOverrideBytes);
  expect(actual.latitude, expected.latitude);
  expect(actual.longitude, expected.longitude);
  expect(actual.lastSeen, expected.lastSeen);
  expect(actual.lastModified, expected.lastModified);
  expect(actual.lastMessageAt, expected.lastMessageAt);
  expect(actual.hasMessages, expected.hasMessages);
  expect(actual.isActive, expected.isActive);
  expect(actual.rawPacket, expected.rawPacket);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  ContactStore forNode(String node) => ContactStore()..setPublicKeyHex = node;

  test('contacts come back with every field, in the order they were saved',
      () async {
    final store = forNode(nodeA);
    final saved = [
      // A flood contact: no route, no bytes.
      contact(1, pathLength: -1),
      // Heard directly.
      contact(2, pathLength: 0, latitude: 55.75, longitude: 37.62),
      // Two hops, one-byte hashes, forced to flood by the user.
      contact(3, pathLength: 2, pathOverride: -1, hasMessages: true),
      // Three hops in two-byte hashes, a pinned route, and everything else.
      contact(
        4,
        pathLength: 3,
        pathHashWidth: 2,
        pathOverride: 1,
        pathOverrideBytes: Uint8List.fromList([0x0B, 0x0C]),
        latitude: -12.5,
        longitude: 130.25,
        lastModified: DateTime.fromMillisecondsSinceEpoch(1758200000000),
        isActive: false,
        rawPacket: Uint8List.fromList(List<int>.generate(40, (i) => i)),
      ),
    ];

    await store.saveContacts(saved);

    final loaded = await store.loadContacts();
    expect(loaded, hasLength(saved.length));
    for (var i = 0; i < saved.length; i++) {
      expectSameContact(loaded[i], saved[i]);
    }
    expect(loaded[0].path, isEmpty);
    expect(loaded[3].path, hasLength(6));
    expect(loaded[3].publicKeyHex, saved[3].publicKeyHex);
  });

  test('each node keeps its own list', () async {
    final a = forNode(nodeA);
    final b = forNode(nodeB);
    await a.saveContacts([contact(1), contact(2)]);

    expect(await b.loadContacts(), isEmpty);

    await b.saveContacts([contact(3)]);
    expect((await a.loadContacts()).map((c) => c.name), ['Node 1', 'Node 2']);
    expect((await b.loadContacts()).map((c) => c.name), ['Node 3']);
  });

  test('a save replaces the list whole, and an empty save leaves nothing',
      () async {
    final store = forNode(nodeA);
    await store.saveContacts([contact(1), contact(2), contact(3)]);
    await store.saveContacts([contact(2)]);
    expect((await store.loadContacts()).map((c) => c.name), ['Node 2']);

    await store.saveContacts(const []);
    expect(await store.loadContacts(), isEmpty);
  });

  test('a changed contact is stored in place of the old one', () async {
    final store = forNode(nodeA);
    await store.saveContacts([contact(1, pathLength: 1), contact(2)]);
    await store.saveContacts([
      contact(1, pathLength: 2, hasMessages: true),
      contact(2),
    ]);

    final loaded = await store.loadContacts();
    expect(loaded, hasLength(2));
    expect(loaded[0].pathLength, 2);
    expect(loaded[0].hasMessages, isTrue);
  });

  test('without a node key nothing is loaded or saved', () async {
    final store = ContactStore();
    expect(await store.loadContacts(), isEmpty);

    await store.saveContacts([contact(1)]);

    expect(await forNode(nodeA).loadContacts(), isEmpty);
    expect(
      PrefsManager.instance.getKeys().where((k) => k.startsWith('contacts')),
      isEmpty,
    );
  });

  test('a contact list that will not decode reads as empty, one bad entry '
      'costs one contact', () async {
    SharedPreferences.setMockInitialValues({
      'contacts7020f1bd19': 'not json',
    });
    PrefsManager.reset();
    await PrefsManager.initialize();
    expect(await forNode(nodeA).loadContacts(), isEmpty);

    final store = forNode(nodeB);
    await store.saveContacts([contact(1), contact(2)]);
    final stored =
        jsonDecode(PrefsManager.instance.getString(store.keyFor)!)
            as List<dynamic>;
    await PrefsManager.instance.setString(
      store.keyFor,
      jsonEncode([
        {'publicKey': 5, 'name': 'Bad'},
        stored[1],
      ]),
    );
    expect((await store.loadContacts()).map((c) => c.name), ['Node 2']);
  });
}
