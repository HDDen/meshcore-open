import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _contactFrame(int code, Uint8List key, String name) {
  final data = ByteData(1 + 32 + 3 + 64 + 32 + 4 + 12);
  final bytes = data.buffer.asUint8List();
  bytes[0] = code;
  bytes.setRange(1, 33, key);
  bytes[33] = advTypeChat;
  bytes[35] = 0xFF; // path unknown
  bytes.setRange(100, 100 + name.length, name.codeUnits);
  data.setUint32(132, 1700000000, Endian.little);
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  test('NEW_ADVERT is discovered only, not a firmware contact', () {
    final connector = MeshCoreConnector();
    connector.handleFrameForTest(_contactFrame(pushCodeNewAdvert, key, 'Bob'));

    expect(connector.contacts, isEmpty);
    expect(connector.discoveredContacts.map((c) => c.name), contains('Bob'));
  });

  test('CONTACT_DELETED removes the firmware contact', () {
    final connector = MeshCoreConnector();
    connector.handleFrameForTest(_contactFrame(respCodeContact, key, 'Bob'));
    expect(connector.contacts.length, 1);

    connector.handleFrameForTest([pushCodeContactDeleted, ...key]);
    expect(connector.contacts, isEmpty);
  });

  test('CONTACTS_FULL raises the storage-full signal', () async {
    final connector = MeshCoreConnector();
    final events = connector.contactsFullEvents.first;
    connector.handleFrameForTest([pushCodeContactsFull]);

    expect(connector.contactsStorageFull, isTrue);
    await events;
  });
}
