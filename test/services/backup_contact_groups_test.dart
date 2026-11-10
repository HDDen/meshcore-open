import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/contact_group.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';

final _node = 'ab' * 32;

Future<String> _upstreamFile(List<Object?> groups) => const BackupFileCodec().encode({
  'format': BackupFileCodec.payloadFormat,
  'version': BackupFileCodec.formatVersion,
  'sourcePublicKey': _node,
  'items': ['contacts', 'contactGroups'],
  'sections': {
    'contacts': {
      'preferences': {
        'contactsababababab': 'unrelated invalid contact data',
        'contact_groupsababababab': jsonEncode(groups),
        'contact_groups0123456789': [
          {'name': 'Other scope', 'members': []},
        ],
      },
    },
  },
}, password: '');

void main() {
  test('reads only the selected upstream groups and normalizes member keys', () async {
    final contents = await _upstreamFile([
      {'name': ' Local ', 'members': ['CD' * 32, 'cd' * 32]},
      {'name': 'Empty group'},
    ]);
    final plan = await const BackupImportPlanner().inspect(
      contents,
      password: '',
      contactGroupsOnly: true,
    );
    expect(plan.contacts, isNull);
    expect(plan.contactGroups!.map((group) => group.name), ['Local', 'Empty group']);
    expect(plan.contactGroups!.first.memberKeys, ['cd' * 32]);
    expect(plan.contactGroups!.last.memberKeys, isEmpty);
  });

  test('contacts and groups share the section and keep distinct preferences', () async {
    final backup = BackupSnapshot(
      sourcePublicKey: _node,
      contacts: const [],
      contactGroups: const [ContactGroup(name: 'Group', memberKeys: [])],
      createdAt: DateTime.utc(2026),
    );
    final contents = await backup.encode(password: '');
    final payload = await const BackupFileCodec().decode(contents, password: '');
    final sections = payload['sections'] as Map<String, Object?>;
    expect(sections.keys, ['contacts']);
    final contacts = sections['contacts'] as Map<String, Object?>;
    expect((contacts['preferences'] as Map).keys, [
      'contactsababababab',
      'contact_groupsababababab',
    ]);
    final plan = await const BackupImportPlanner().inspect(
      contents,
      password: '',
      contactGroupsOnly: true,
    );
    expect(plan.contactGroups!.single.name, 'Group');
  });

  test('rejects reserved names and malformed member keys', () async {
    for (final group in [
      {'name': '__ALL__', 'members': []},
      {'name': 'Group', 'members': ['deadbeef']},
    ]) {
      final contents = await _upstreamFile([group]);
      await expectLater(
        const BackupImportPlanner().inspect(
          contents,
          password: '',
          contactGroupsOnly: true,
        ),
        throwsFormatException,
      );
    }
  });
}
