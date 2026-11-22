import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/bookmarked_message.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';

final _node = 'aa' * 32;
BookmarkedMessage _bookmark() => BookmarkedMessage(
  sourceType: BookmarkSourceType.contact, sourceId: 'bb' * 32,
  sourceName: 'Peer', messageId: 'identity:${'cc' * 32}:7', senderName: 'Peer', text: 'saved',
  timestamp: DateTime(2026), receivedAt: DateTime(2026), isOutgoing: false,
);
void main() {
  test('bookmark snapshots round-trip in the upstream-compatible section', () async {
    final snapshot = BackupSnapshot(sourcePublicKey: _node, createdAt: DateTime(2026), bookmarks: [_bookmark()]);
    final file = await snapshot.encode(password: '');
    final decoded = await const BackupFileCodec().decode(file, password: '');
    expect((decoded['sections'] as Map)['discoveredContacts'], isNotNull);
    final plans = await const BackupImportPlanner().inspectSections(file, password: '');
    expect(plans.invalid, isEmpty);
    final restored = plans.sections[BackupRestoreSection.bookmarks]!.bookmarks!.single;
    expect(restored.toJson(), _bookmark().toJson());
    expect(jsonDecode(snapshot.encodeOfficial()).toString(), isNot(contains('message_bookmarks_')));
  });

  test('a malformed bookmark section cannot hide another valid section', () async {
    final file = await const BackupFileCodec().encode({
      'format': BackupFileCodec.payloadFormat, 'version': BackupFileCodec.formatVersion,
      'sourcePublicKey': _node, 'items': ['bookmarks', 'regions'],
      'sections': {
        'discoveredContacts': {'preferences': {'message_bookmarks_${_node.substring(0, 10)}': [42]}},
        'nodeSettings': {'preferences': {'regions': ['#north']}},
      },
    }, password: '');
    final plans = await const BackupImportPlanner().inspectSections(file, password: '');
    expect(plans.invalid, contains(BackupRestoreSection.bookmarks));
    expect(plans.sections[BackupRestoreSection.regions]!.regions, ['#north']);
  });
}
