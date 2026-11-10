import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';

final _sourceNode = 'ab' * 32;
final _secret = base64Encode(List<int>.filled(32, 7));

Map<String, Object?> _community(String secret) => {
  'id': 'community-one',
  'name': 'Neighborhood mesh',
  'secret': secret,
  'created_at': 1735689600000,
  'hashtag_channels': ['weather'],
};

Future<String> _upstreamBackup(Object rows) => const BackupFileCodec().encode({
  'format': BackupFileCodec.payloadFormat,
  'version': BackupFileCodec.formatVersion,
  'sourcePublicKey': _sourceNode,
  'items': ['channels', 'communities'],
  'sections': {
    'channels': {
      'preferences': {
        'channelsababababab': 'unrelated invalid channel data',
        'communities_v1ababababab': rows,
        'communities_v1cdcdcdcdcd': [_community('other scope')],
      },
    },
  },
}, password: '');

void main() {
  test('reads communities in the upstream channels section by exact source scope', () async {
    for (final rows in [
      [_community(_secret)],
      jsonEncode([_community(_secret)]),
    ]) {
      final plan = await const BackupImportPlanner().inspect(
        await _upstreamBackup(rows),
        password: '',
        communitiesOnly: true,
      );
      expect(plan.channels, isNull);
      expect(plan.communities!.single.toJson(), _community(_secret));
    }
  });

  test('invalid shared keys reject the entire section without exposing input', () async {
    for (final secret in ['not a key!', base64Encode([1])]) {
      final contents = await _upstreamBackup([
        _community(_secret),
        _community(secret),
      ]);
      await expectLater(
        const BackupImportPlanner().inspect(
          contents,
          password: '',
          communitiesOnly: true,
        ),
        throwsA(isA<FormatException>().having(
          (error) => error.source,
          'error source',
          isNull,
        )),
      );
    }
  });
}
