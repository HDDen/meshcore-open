import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';

final _sourceKey = List.filled(32, 'ab').join();
final _contactKey = List.filled(32, 'cd').join();
final _psk = List.filled(16, 'ef').join();

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
}
