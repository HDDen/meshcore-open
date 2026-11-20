import 'dart:typed_data';

import 'package:convert/convert.dart';

import '../services/additional_identity_vault.dart';

/// The outer v1 backup must be encrypted before serializing these entries.
class BackupAdditionalIdentities {
  BackupAdditionalIdentities(Iterable<AdditionalIdentityEntry> entries)
    : entries = List.unmodifiable(entries);

  static const section = 'mcoaAdditionalIdentities';

  final List<AdditionalIdentityEntry> entries;

  List<Map<String, Object>> toJson() => [
    for (final entry in entries)
      {
        'name': entry.name,
        'publicKey': entry.identity.publicKeyHex,
        'privateKey': entry.identity.privateKeyHex,
        'ackWithoutPath': entry.ackWithoutPath,
      },
  ];

  static Future<BackupAdditionalIdentities> read(Object? value) async {
    if (value is! List || value.length > 10000) {
      throw const FormatException('Invalid additional keys section');
    }
    final entries = <AdditionalIdentityEntry>[];
    final keys = <String>{};
    for (final row in value) {
      if (row is! Map<String, Object?> ||
          row['name'] is! String ||
          row['publicKey'] is! String ||
          row['privateKey'] is! String ||
          (row.containsKey('ackWithoutPath') && row['ackWithoutPath'] is! bool)) {
        throw const FormatException('Invalid additional key');
      }
      final publicKey = (row['publicKey'] as String).toLowerCase();
      final privateKey = row['privateKey'] as String;
      if (publicKey.length != 64 ||
          privateKey.length != 128 ||
          !keys.add(publicKey)) {
        throw const FormatException('Invalid additional key');
      }
      final bytes = Uint8List.fromList(hex.decode(privateKey));
      try {
        entries.add(await AdditionalIdentityEntry.fromRadio(
          name: row['name'] as String,
          privateKey: bytes,
          expectedPublicKey: publicKey,
          ackWithoutPath: row['ackWithoutPath'] != false,
        ));
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
    return BackupAdditionalIdentities(entries);
  }
}
