import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/backup_channel_restore.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';

final _sourceKey = List.filled(32, 'ab').join();
final _contactKey = List.filled(32, 'cd').join();
final _psk = List.filled(16, 'ef').join();

Channel _channel(int index, String name, int key) => Channel(
  index: index,
  name: name,
  psk: Uint8List.fromList(List.filled(16, key)),
);

Map<String, Object?> _officialContact(Object? path) => {
  'public_key': _contactKey,
  'name': 'Contact',
  'custom_name': 'Repeater',
  'type': 2,
  'flags': 1,
  'out_path_list': path,
  'latitude': '47.5',
  'longitude': 7.8,
  'last_advert': '123',
  'last_modified': 456,
};

Map<String, Object?> _upstream({
  required Map<String, Object?> sections,
  List<String> items = const ['contacts', 'channels'],
}) => {
  'format': 'meshcore-open-backup',
  'version': 1,
  'sourcePublicKey': _sourceKey,
  'items': items,
  'sections': sections,
};

void main() {
  const planner = BackupImportPlanner();

  test('export captures one v1 channel section and round-trips without unread state',
      () async {
    final channel = _channel(2, 'Mesh channel', 7)..unreadCount = 9;
    final snapshot = BackupSnapshot(
      sourcePublicKey: _sourceKey.toUpperCase(),
      nodeName: r'Нода:/\*',
      channels: [channel],
      contacts: null,
      createdAt: DateTime.utc(2026, 11, 10, 12, 30),
    );
    channel.psk.fillRange(0, channel.psk.length, 8);
    final contents = await snapshot.encode(password: '');
    final document = jsonDecode(contents) as Map<String, dynamic>;
    expect(document['items'], ['channels']);
    expect(document['sections'].keys, ['channels']);
    final preferences = document['sections']['channels']['preferences'] as Map;
    expect(preferences.keys, ['channelsababababab']);
    expect(snapshot.fileName, contains('Нода'));
    expect(snapshot.fileName, isNot(matches(r'[:/\\*]')));
    expect(snapshot.fileName, endsWith('.json'));
    final decoded = await planner.inspect(contents, password: '');
    expect(decoded.sourcePublicKey, _sourceKey);
    final restored = decoded.channels!.single;
    expect(restored.index, 2);
    expect(restored.name, 'Mesh channel');
    expect(restored.psk, List.filled(16, 7));
    expect(restored.unreadCount, 0);
  });

  test('contacts-only export preserves radio fields and omits local metadata', () async {
    final contact = Contact(
      publicKey: Uint8List.fromList(List.filled(32, 0xcd)),
      name: 'Radio contact',
      type: 1,
      flags: 1,
      pathLength: 1,
      pathHashWidth: 3,
      path: Uint8List.fromList([0x01, 0x02, 0x03]),
      pathOverride: -1,
      latitude: 51.5,
      longitude: -0.1,
      lastSeen: DateTime.utc(2026, 1, 2),
      lastModified: DateTime.utc(2026, 1, 3),
      hasMessages: true,
    );
    final snapshot = BackupSnapshot(
      sourcePublicKey: _sourceKey,
      nodeName: 'Source',
      channels: null,
      contacts: [contact],
      createdAt: DateTime.utc(2026),
    );
    contact.path[0] = 0xff;
    final contents = await snapshot.encode(password: '');
    final plan = await planner.inspect(contents, password: '');
    final restored = plan.contacts!.single;
    expect(plan.channels, isNull);
    expect(snapshot.fileName, startsWith('meshcore-contacts-'));
    expect(restored.publicKeyHex, _contactKey);
    expect(restored.name, 'Radio contact');
    expect(restored.type, 1);
    expect(restored.flags, 1);
    expect(restored.pathHashWidth, 3);
    expect(restored.path, [1, 2, 3]);
    expect(restored.latitude, 51.5);
    expect(restored.longitude, -0.1);
    expect(restored.lastSeen.millisecondsSinceEpoch,
        contact.lastSeen.millisecondsSinceEpoch);
    expect(restored.lastModified!.millisecondsSinceEpoch,
        contact.lastModified!.millisecondsSinceEpoch);
    expect(contents, isNot(contains('pathOverride')));
    expect(contents, isNot(contains('hasMessages')));
  });

  final routes = <(String?, int, int, List<int>)>[
    (null, -1, 1, []),
    ('', 0, 1, []),
    ('a1,b2', 2, 1, [0xa1, 0xb2]),
    ('a102,b203', 2, 2, [0xa1, 2, 0xb2, 3]),
    ('a10203,b20304', 2, 3, [0xa1, 2, 3, 0xb2, 3, 4]),
  ];
  for (final (raw, hops, width, bytes) in routes) {
    test('official contact preserves route ${raw ?? 'Flood'}', () async {
      final plan = await planner.inspect(
        jsonEncode({
          'public_key': _sourceKey.toUpperCase(),
          'contacts': [_officialContact(raw)],
        }),
        password: '',
      );
      expect(plan.isOfficial, isTrue);
      expect(plan.sourcePublicKey, _sourceKey);
      final contact = plan.contacts!.single;
      expect(contact.name, 'Repeater');
      expect(contact.publicKeyHex, _contactKey);
      expect(contact.pathLength, hops);
      expect(contact.pathHashWidth, width);
      expect(contact.path, bytes);
      expect(contact.latitude, 47.5);
      expect(contact.longitude, 7.8);
      expect(contact.lastSeen.millisecondsSinceEpoch, 123000);
      expect(contact.lastModified!.millisecondsSinceEpoch, 456000);
      expect(plan.channels, isNull);
    });
  }

  test('official channels keep slot indices across holes and empty slots',
      () async {
    final json = jsonEncode({
      'name': 'Test "node"',
      'public_key': _sourceKey,
      'channels': [
        {'name': '', 'secret': List.filled(32, '0').join()},
        null,
        {'name': 'Private', 'secret': _psk},
      ],
    }).replaceFirst(',"public_key"', '"public_key"');
    final plan = await planner.inspect(json, password: '');
    final channel = plan.channels!.single;
    expect(channel.index, 2);
    expect(channel.name, 'Private');
    expect(channel.pskHex, _psk);
  });

  test('reads selected upstream lists for the source key after decryption',
      () async {
    final key = base64Encode(List.filled(32, 0xcd));
    final secret = base64Encode(List.filled(16, 0xef));
    final payload = _upstream(sections: {
      'contacts': {
        'preferences': {
          'contactsABABABABAB': [
            {
              'publicKey': key,
              'name': 'Contact',
              'pathLength': 130,
              'path': base64Encode([1, 2, 3, 4, 5, 6]),
              'lastSeen': 123456,
            },
          ],
          'contacts0000000000': 'different node',
        },
      },
      'channels': {
        'preferences': {
          'channelsababababab': jsonEncode([
            {'index': 4, 'name': 'Private', 'psk': secret, 'unreadCount': 7},
          ]),
        },
      },
    });
    const password = 'fixture';
    final encoded = await const BackupFileCodec().encode(
      payload,
      password: password,
    );
    final plan = await planner.inspect(encoded, password: password);
    expect(plan.isOfficial, isFalse);
    expect(plan.contacts!.single.publicKeyHex, _contactKey);
    expect(plan.contacts!.single.pathLength, 2);
    expect(plan.contacts!.single.pathHashWidth, 3);
    expect(plan.contacts!.single.path, [1, 2, 3, 4, 5, 6]);
    expect(plan.contacts!.single.lastSeen.millisecondsSinceEpoch, 123456);
    expect(plan.channels!.single.index, 4);
    expect(plan.channels!.single.pskHex, _psk);
    expect(plan.channels!.single.unreadCount, 0);
  });

  test('only an explicit selected source list can be empty', () async {
    final plan = await planner.inspect(
      jsonEncode(_upstream(sections: {
        'contacts': {
          'preferences': {'contactsababababab': '[]'},
        },
        'channels': {
          'preferences': {'channels0000000000': '[]'},
        },
      })),
      password: '',
    );
    expect(plan.contacts, isEmpty);
    expect(plan.channels, isNull);

    final unselected = await planner.inspect(
      jsonEncode(_upstream(
        items: ['appSettings'],
        sections: {
          'contacts': {
            'preferences': {'contactsababababab': '[]'},
          },
        },
      )),
      password: '',
    );
    expect(unselected.contacts, isNull);
  });

  test('malformed rows and duplicate identities abort planning', () async {
    for (final lists in [
      {
        'contacts': [
          _officialContact(null),
          {..._officialContact('a1,0203'), 'public_key': List.filled(64, '9').join()},
        ],
      },
      {'contacts': [_officialContact(null), _officialContact('')]},
      {'channels': [{'name': 'Private', 'secret': 'too short'}]},
      {'channels': [{'name': List.filled(16, 'ж').join(), 'secret': _psk}]},
    ]) {
      await expectLater(
        planner.inspect(
          jsonEncode({'public_key': _sourceKey, ...lists}),
          password: '',
        ),
        throwsFormatException,
      );
    }
  });

  test('upstream backup cannot supply the same slot twice', () async {
    final channel = {
      'index': 1,
      'name': 'Private',
      'psk': base64Encode(List.filled(16, 0xef)),
    };
    await expectLater(
      planner.inspect(
        jsonEncode(_upstream(sections: {
          'channels': {
            'preferences': {
              'channelsababababab': [channel, channel],
            },
          },
        })),
        password: '',
      ),
      throwsFormatException,
    );
  });

  group('destination channel plan', () {
    test('a matching PSK takes the backup name in its current slot',
        () async {
      final plan = await planner.inspect(
        jsonEncode({
          'public_key': _sourceKey,
          'channels': [
            {'name': 'Old name', 'secret': _psk},
          ],
        }),
        password: '',
      );
      final moved = _channel(2, 'Current name', 0xef)..unreadCount = 7;
      final decision = plan.resolveChannels(
        destination: [_channel(0, 'Other channel', 1), moved],
        capacity: 3,
        unconfirmedSlots: const {},
      ).single;

      expect(decision.action, BackupChannelAction.rename);
      expect(decision.source.index, 0);
      expect(decision.destination!.index, 2);
      expect(decision.destination!.name, 'Old name');
      expect(decision.destination!.pskHex, _psk);
      expect(decision.destination!.unreadCount, 7);
      expect(moved.name, 'Current name');
    });

    test('matching name disambiguates live slots with the same PSK', () {
      final decisions = resolveBackupChannels(
        [_channel(0, 'main', 1)],
        destination: [_channel(1, 'Other label', 1), _channel(3, 'Main', 1)],
        capacity: 4,
        unconfirmedSlots: const {},
      );
      expect(decisions.single.action, BackupChannelAction.rename);
      expect(decisions.single.destination!.index, 3);
      expect(decisions.single.destination!.name, 'main');
    });

    test('a matching PSK and exact name need no write', () {
      final current = _channel(2, 'Current name', 1);
      final decision = resolveBackupChannels(
        [_channel(0, 'Current name', 1)],
        destination: [current],
        capacity: 3,
        unconfirmedSlots: const {},
      ).single;
      expect(decision.action, BackupChannelAction.alreadyPresent);
      expect(decision.destination, same(current));
    });

    test('a rename cannot take the name of a different PSK', () {
      final decision = resolveBackupChannels(
        [_channel(0, 'Backup name', 1)],
        destination: [
          _channel(1, 'Current name', 1),
          _channel(2, 'backup name', 2),
        ],
        capacity: 3,
        unconfirmedSlots: const {},
      ).single;
      expect(decision.action, BackupChannelAction.nameConflict);
      expect(decision.destination, isNull);
    });

    test('a rename and an addition cannot claim the same name', () {
      final decisions = resolveBackupChannels(
        [_channel(0, 'Backup name', 1), _channel(1, 'backup name', 2)],
        destination: [_channel(2, 'Current name', 1)],
        capacity: 3,
        unconfirmedSlots: const {},
      );
      expect(decisions.map((decision) => decision.action), [
        BackupChannelAction.nameConflict,
        BackupChannelAction.nameConflict,
      ]);
    });

    test('a rename needs a confirmed slot', () {
      final decision = resolveBackupChannels(
        [_channel(0, 'Backup name', 1)],
        destination: [_channel(2, 'Current name', 1)],
        capacity: 3,
        unconfirmedSlots: {2},
      ).single;
      expect(decision.action, BackupChannelAction.unconfirmedSlot);
      expect(decision.destination, isNull);
    });

    test('backup aliases propose at most one rename for a live slot', () {
      final decisions = resolveBackupChannels(
        [_channel(0, 'Backup name', 1), _channel(1, 'Other name', 1)],
        destination: [_channel(2, 'Current name', 1)],
        capacity: 3,
        unconfirmedSlots: const {},
      );
      expect(decisions.map((decision) => decision.action), [
        BackupChannelAction.rename,
        BackupChannelAction.duplicateInBackup,
      ]);
      expect(decisions.first.destination!.name, 'Backup name');
      expect(decisions.last.destination, same(decisions.first.destination));
    });

    test('a different PSK with the same name is a conflict', () {
      final decisions = resolveBackupChannels(
        [_channel(0, 'same name', 1)],
        destination: [_channel(2, 'Same Name', 2)],
        capacity: 3,
        unconfirmedSlots: const {},
      );
      expect(decisions.single.action, BackupChannelAction.nameConflict);
      expect(decisions.single.destination, isNull);
    });

    test('new channels keep free original slots before using fallbacks', () {
      final decisions = resolveBackupChannels(
        [
          _channel(0, 'Displaced', 1),
          _channel(1, 'Still free', 2),
          _channel(2, 'No room', 3),
        ],
        destination: [_channel(0, 'On node', 4)],
        capacity: 4,
        unconfirmedSlots: {2},
      );
      expect(decisions.map((decision) => decision.action), [
        BackupChannelAction.add,
        BackupChannelAction.add,
        BackupChannelAction.noFreeSlot,
      ]);
      expect(
        decisions.map((decision) => decision.destination?.index),
        [3, 1, null],
      );
    });

    test('backup aliases share one proposed addition', () {
      final decisions = resolveBackupChannels(
        [_channel(0, 'Original', 1), _channel(1, 'Alias', 1)],
        destination: const [],
        capacity: 2,
        unconfirmedSlots: const {},
      );
      expect(decisions.map((decision) => decision.action), [
        BackupChannelAction.add,
        BackupChannelAction.duplicateInBackup,
      ]);
      expect(decisions.last.source.name, 'Alias');
      expect(decisions.last.destination, same(decisions.first.destination));
    });

    test('an absent channel section plans no changes', () async {
      final plan = await planner.inspect(
        jsonEncode({'public_key': _sourceKey, 'contacts': []}),
        password: '',
      );
      expect(
        plan.resolveChannels(
          destination: [_channel(0, 'On node', 1)],
          capacity: 1,
          unconfirmedSlots: const {},
        ),
        isEmpty,
      );
    });
  });
}
