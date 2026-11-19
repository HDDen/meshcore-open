import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/backup_node_identity.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/services/backup_snapshot.dart';

const _privateKey =
    '307c83864f2833cb427a2ef1c00a013cfdff2768d980c0a3a520f006904de94f'
    '9b4f0afe280b746a778684e75442502057b7473a03f08f96f5a38e9287e01f8f';

void main() {
  const planner = BackupImportPlanner();
  late BackupNodeIdentity identity;
  setUp(() async {
    identity = await BackupNodeIdentity.read(
      _privateKey, hexadecimal: true, publicKeys: const [],
    );
  });

  test('encrypted MCOa key export restores through the upstream privateKey item', () async {
    final key = hex2Uint8List(_privateKey);
    final snapshot = BackupSnapshot(
      sourcePublicKey: identity.publicKey,
      nodePrivateKey: base64Encode(key),
      createdAt: DateTime.utc(2026, 11, 19),
    );
    final encoded = await snapshot.encode(password: 'backup password');
    expect(encoded, isNot(contains(_privateKey)));
    final restored = await planner.inspectSections(encoded, password: 'backup password');
    expect(restored.invalid, isEmpty);
    expect(restored.sections[BackupRestoreSection.nodeIdentity]!.nodeIdentity!.publicKey,
        identity.publicKey);
  });

  test('plain upstream and official keys keep the same expanded identity', () async {
    final bytes = hex2Uint8List(_privateKey);
    final upstream = {
      'format': BackupFileCodec.payloadFormat, 'version': 1,
      'sourcePublicKey': identity.publicKey, 'items': ['privateKey'],
      'sections': {'nodeSettings': {'privateKey': base64Encode(bytes)}},
    };
    final official = {
      'public_key': identity.publicKey, 'private_key': _privateKey,
    };
    for (final payload in [upstream, official]) {
      final restored = await planner.inspectSections(jsonEncode(payload), password: '');
      expect(restored.invalid, isEmpty);
      expect(restored.sections[BackupRestoreSection.nodeIdentity]!.nodeIdentity!
          .identity.privateKeyHex, _privateKey);
    }
    expect(buildImportPrivateKeyFrame(bytes), [24, ...bytes]);
    expect(() => buildImportPrivateKeyFrame(Uint8List(32)), throwsArgumentError);
  });

  test('a wrong public key rejects identity restore and keeps other sections', () async {
    final payload = {
      'format': BackupFileCodec.payloadFormat, 'version': 1,
      'sourcePublicKey': 'ab' * 32, 'items': ['privateKey', 'deviceName'],
      'sections': {'nodeSettings': {
        'name': 'Usable name',
        'privateKey': base64Encode(hex2Uint8List(_privateKey)),
      }},
    };
    final restored = await planner.inspectSections(jsonEncode(payload), password: '');
    expect(restored.invalid, {BackupRestoreSection.nodeIdentity});
    expect(restored.sections[BackupRestoreSection.nodeProfile]!.nodeProfile!.nodeName,
        'Usable name');
  });

  test('malformed keys and unselected key payloads never enter a restore plan', () async {
    for (final value in [base64Encode(Uint8List(32)), base64Encode(Uint8List(64)), 'bad data']) {
      await expectLater(BackupNodeIdentity.read(
        value, hexadecimal: false, publicKeys: const [],
      ), throwsFormatException);
    }
    final payload = {
      'format': BackupFileCodec.payloadFormat, 'version': 1,
      'sourcePublicKey': identity.publicKey, 'items': <String>[],
      'sections': {'nodeSettings': {
        'privateKey': base64Encode(hex2Uint8List(_privateKey)),
      }},
    };
    final restored = await planner.inspectSections(jsonEncode(payload), password: '');
    expect(restored.sections, isEmpty);
  });
}
