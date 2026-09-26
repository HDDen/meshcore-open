import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/path_helper.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/storage/contact_discovery_store.dart';
import 'package:meshcore_open/storage/contact_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _contactFrame(int pathLen, List<int> path) {
  final writer = BytesBuilder();
  writer.addByte(respCodeContact);
  writer.add(List.generate(32, (i) => i + 1));
  writer.addByte(advTypeRepeater);
  writer.addByte(0);
  writer.addByte(pathLen);
  writer.add(Uint8List(64)..setRange(0, path.length, path));
  writer.add(Uint8List(32)..setRange(0, 4, 'Node'.codeUnits));
  writer.add([0x01, 0x00, 0x00, 0x00]);
  writer.add(Uint8List(12));
  return writer.toBytes();
}

Contact _contact({required int pathHashWidth}) => Contact(
  publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
  name: 'Node',
  type: advTypeRepeater,
  pathLength: 2,
  path: Uint8List.fromList([0xA1, 0xA2, 0xB1, 0xB2]),
  pathHashWidth: pathHashWidth,
  lastSeen: DateTime.fromMillisecondsSinceEpoch(1000),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  group('Contact.fromFrame keeps the path hash width', () {
    test('2-byte hops', () {
      final contact = Contact.fromFrame(
        _contactFrame((1 << 6) | 2, [0xA1, 0xA2, 0xB1, 0xB2]),
      )!;
      expect(contact.pathLength, 2);
      expect(contact.pathHashWidth, 2);
      expect(contact.path, [0xA1, 0xA2, 0xB1, 0xB2]);
      expect(PathHelper.splitPathBytes(contact.path, contact.pathHashWidth), [
        [0xA1, 0xA2],
        [0xB1, 0xB2],
      ]);
    });

    test('3-byte hops', () {
      final contact = Contact.fromFrame(
        _contactFrame((2 << 6) | 1, [0xA1, 0xA2, 0xA3]),
      )!;
      expect(contact.pathLength, 1);
      expect(contact.pathHashWidth, 3);
      expect(contact.path, [0xA1, 0xA2, 0xA3]);
    });

    test('flood defaults to width 1', () {
      final contact = Contact.fromFrame(_contactFrame(0xFF, const []))!;
      expect(contact.pathLength, -1);
      expect(contact.pathHashWidth, 1);
    });

    test('copyWith preserves width', () {
      final contact = _contact(pathHashWidth: 2).copyWith(name: 'Renamed');
      expect(contact.pathHashWidth, 2);
    });
  });

  group('Contact.inferPathHashWidth', () {
    test('divides bytes by hops', () {
      expect(Contact.inferPathHashWidth(2, 4), 2);
      expect(Contact.inferPathHashWidth(1, 3), 3);
    });

    test('falls back to 1', () {
      expect(Contact.inferPathHashWidth(0, 0), 1);
      expect(Contact.inferPathHashWidth(-1, 0), 1);
      expect(Contact.inferPathHashWidth(2, 3), 1);
      expect(Contact.inferPathHashWidth(1, 4), 1);
    });
  });

  group('Contact stores persist the path hash width', () {
    test('ContactStore round-trip', () async {
      final store = ContactStore()..publicKeyHex = '1234567890';
      await store.saveContacts([_contact(pathHashWidth: 2)]);
      final loaded = await store.loadContacts();
      expect(loaded.single.pathHashWidth, 2);
      expect(loaded.single.path, [0xA1, 0xA2, 0xB1, 0xB2]);
    });

    test('ContactDiscoveryStore round-trip', () async {
      final store = ContactDiscoveryStore()..setPublicKeyHex = 'AABBCCDDEEFF00';
      await store.saveContacts([_contact(pathHashWidth: 2)]);
      final loaded = await store.loadContacts();
      expect(loaded.single.pathHashWidth, 2);
    });

    test('legacy data without width is inferred from hops', () async {
      final store = ContactStore()..publicKeyHex = '1234567890';
      final json = {
        'publicKey': base64Encode(List.generate(32, (i) => i + 1)),
        'name': 'Legacy',
        'type': advTypeRepeater,
        'pathLength': 2,
        'path': base64Encode([0xA1, 0xA2, 0xB1, 0xB2]),
        'lastSeen': 1000,
      };
      await PrefsManager.instance.setString(store.keyFor, jsonEncode([json]));
      final loaded = await store.loadContacts();
      expect(loaded.single.pathHashWidth, 2);
    });

    test('legacy flood data without width falls back to 1', () async {
      final store = ContactStore()..publicKeyHex = '1234567890';
      final json = {
        'publicKey': base64Encode(List.generate(32, (i) => i + 1)),
        'name': 'Legacy',
        'type': advTypeRepeater,
        'pathLength': -1,
        'path': base64Encode(const <int>[]),
        'lastSeen': 1000,
      };
      await PrefsManager.instance.setString(store.keyFor, jsonEncode([json]));
      final loaded = await store.loadContacts();
      expect(loaded.single.pathHashWidth, 1);
    });

    test('legacy mode-encoded pathLength yields its width', () async {
      final store = ContactStore()..publicKeyHex = '1234567890';
      final json = {
        'publicKey': base64Encode(List.generate(32, (i) => i + 1)),
        'name': 'Legacy',
        'type': advTypeRepeater,
        'pathLength': (2 << 6) | 1,
        'path': base64Encode([0xA1, 0xA2, 0xA3]),
        'lastSeen': 1000,
      };
      await PrefsManager.instance.setString(store.keyFor, jsonEncode([json]));
      final loaded = await store.loadContacts();
      expect(loaded.single.pathLength, 1);
      expect(loaded.single.pathHashWidth, 3);
    });
  });

  group('ChannelMessage.fromFrame path_len 0xFF (direct)', () {
    Uint8List frame({required bool v3}) {
      final writer = BytesBuilder();
      if (v3) {
        writer.add([respCodeChannelMsgRecvV3, 0x10, 0x01, 0x00]);
      } else {
        writer.addByte(respCodeChannelMsgRecv);
      }
      writer.addByte(3); // channel index
      writer.addByte(0xFF);
      writer.addByte(txtTypePlain);
      writer.add([0x01, 0x00, 0x00, 0x00]);
      writer.add(utf8.encode('Alice: hi'));
      writer.addByte(0);
      return writer.toBytes();
    }

    test('V3 does not read 63 x 4-byte hops', () {
      final message = ChannelMessage.fromFrame(frame(v3: true))!;
      expect(message.text, 'hi');
      expect(message.senderName, 'Alice');
      expect(message.pathLength, isNull);
      expect(message.pathBytes, isEmpty);
      expect(message.pathHashWidth, isNull);
      expect(message.channelIndex, 3);
    });

    test('non-V3 reads path_len unsigned', () {
      final message = ChannelMessage.fromFrame(frame(v3: false))!;
      expect(message.text, 'hi');
      expect(message.pathLength, isNull);
    });
  });

  test('PathHelper treats width 4 as invalid and clamps to 3', () {
    expect(PathHelper.splitPathBytes([1, 2, 3, 4], 4), [
      [1, 2, 3],
      [4],
    ]);
  });

  test('buildSetPathHashModeFrame rejects reserved mode 3', () {
    expect(buildSetPathHashModeFrame(3), [cmdSetPathHashMode, 0, 2]);
  });
}
