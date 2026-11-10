import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/backup_discovered_contacts.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';

final _node = 'ab' * 32;
final _scope = _node.substring(0, 10);

Map<String, Object?> _entry(int key, String name) => {
  'publicKey': base64Encode(List.filled(32, key)),
  'name': name,
  'type': 2,
  'lastSeen': 1700000000000,
  'pathLength': 1,
  'path': base64Encode([0x52]),
  'isActive': true,
  'hasMessages': true,
};

Future<BackupImportPlan> _inspect(String file, {String password = ''}) =>
    const BackupImportPlanner().inspect(
      file,
      password: password,
      discoveredContactsOnly: true,
    );

void main() {
  test('reads only the source node discovery section in upstream v1', () async {
    const codec = BackupFileCodec();
    const password = 'synthetic password';
    final file = await codec.encode({
      'format': BackupFileCodec.payloadFormat,
      'version': BackupFileCodec.formatVersion,
      'sourcePublicKey': _node,
      'items': ['contacts', 'discoveredContacts'],
      'sections': {
        'contacts': {
          'preferences': {'contacts$_scope': 'not a valid list'},
        },
        'discoveredContacts': {
          'preferences': {
            'discovered_contacts$_scope': jsonEncode([_entry(1, 'Found')]),
            'discovered_contacts0123456789': [_entry(2, 'Foreign')],
          },
        },
      },
    }, password: password);
    await expectLater(_inspect(file), throwsA(isA<BackupPasswordException>()));
    final plan = await _inspect(file, password: password);
    expect(plan.contacts, isNull);
    final entries = jsonDecode(plan.discoveredContactsJson!) as List<dynamic>;
    expect(entries.single['name'], 'Found');
  });

  test('the export writes the same scoped v1 discovery list', () async {
    final snapshot = BackupSnapshot(
      sourcePublicKey: _node,
      nodeName: 'Node',
      discoveredContactsJson: jsonEncode([_entry(1, 'Found')]),
      createdAt: DateTime.utc(2026),
    );
    final file = await snapshot.encode(password: '');
    final envelope = await const BackupFileCodec().decode(file, password: '');
    expect(envelope['items'], ['discoveredContacts']);
    final plan = await _inspect(file);
    expect(jsonDecode(plan.discoveredContactsJson!).single['name'], 'Found');
  });

  test('preview respects capacity and strips foreign state', () {
    final current = [
      Contact(
        publicKey: Uint8List.fromList(List.filled(32, 8)),
        name: 'Keep',
        type: 2,
        pathLength: -1,
        path: Uint8List(0),
        lastSeen: DateTime.utc(2026),
      ),
    ];
    final preview = BackupDiscoveredContactsPreview(
      sourceJson: jsonEncode([
        _entry(1, 'Add'),
        _entry(1, 'Duplicate'),
        _entry(2, 'No room'),
        _entry(3, 'On this radio'),
        _entry(8, 'Older copy of Keep'),
        _entry(0xab, 'Self'),
        'malformed',
      ]),
      current: current,
      knownContactKeys: {'03' * 32},
      nodeKey: _node,
      capacity: 2,
      session: Object(),
    );
    final added = preview.contacts.single;
    expect(added.name, 'Add');
    expect(added.pathLength, -1);
    expect(added.path, isEmpty);
    expect(added.isActive, isFalse);
    expect(added.hasMessages, isFalse);
    expect(preview.skipped, 4);
    expect(preview.noRoom, 1);
    expect(preview.invalid, 1);
    expect(current.single.name, 'Keep');
  });
}
