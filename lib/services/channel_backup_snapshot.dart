import 'dart:convert';

import '../connector/meshcore_protocol.dart';
import '../models/channel.dart';
import 'backup_file_codec.dart';

/// An immutable export of one radio's channel definitions.
class ChannelBackupSnapshot {
  ChannelBackupSnapshot({
    required String sourcePublicKey,
    required this.nodeName,
    required Iterable<Channel> channels,
    required DateTime createdAt,
  }) : sourcePublicKey = sourcePublicKey.toLowerCase(),
       createdAt = createdAt.toUtc(),
       _rows = _snapshotRows(channels) {
    if (sourcePublicKey.length != pubKeySize * 2 ||
        _nonHex.hasMatch(sourcePublicKey)) {
      throw const FormatException('Invalid backup source key');
    }
  }

  static final _nonHex = RegExp(r'[^0-9a-fA-F]');
  static final _invalidFileNameChars = RegExp(r'[\x00-\x1f<>:"/\\|?*]+');
  final String sourcePublicKey;
  final String nodeName;
  final DateTime createdAt;
  final List<({int index, String name, String psk})> _rows;

  int get channelCount => _rows.length;

  String get fileName {
    final safeName = nodeName.replaceAll(_invalidFileNameChars, '-').trim();
    final stem = String.fromCharCodes(safeName.runes.take(40)).trim();
    final stamp = createdAt.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final name = ['meshcore-channels', if (stem.isNotEmpty) stem, stamp].join('-');
    return '$name.json';
  }

  Future<String> encode({required String password}) =>
      const BackupFileCodec().encode({
        'format': BackupFileCodec.payloadFormat,
        'version': BackupFileCodec.formatVersion,
        'createdAt': createdAt.toIso8601String(),
        'sourcePublicKey': sourcePublicKey,
        'items': ['channels'],
        'sections': {
          'channels': {
            'preferences': {
              'channels${sourcePublicKey.substring(0, 10)}': _rows.isEmpty
                  ? '[]'
                  : [
                      for (final row in _rows)
                        {
                          'index': row.index,
                          'name': row.name,
                          'psk': row.psk,
                          'unreadCount': 0,
                        },
                    ],
            },
          },
        },
      }, password: password);

  static List<({int index, String name, String psk})> _snapshotRows(
    Iterable<Channel> channels,
  ) {
    final usedSlots = <int>{};
    final rows = <({int index, String name, String psk})>[];
    for (final channel in channels) {
      if (channel.isEmpty) continue;
      if (channel.index < 0 ||
          channel.index > 255 ||
          !usedSlots.add(channel.index) ||
          channel.name.contains('\u0000') ||
          utf8.encode(channel.name).length >= maxNameSize ||
          channel.psk.length != 16 ||
          channel.psk.every((byte) => byte == 0)) {
        throw const FormatException('Invalid channel in backup snapshot');
      }
      rows.add((
        index: channel.index,
        name: channel.name,
        psk: base64Encode(channel.psk),
      ));
    }
    rows.sort((a, b) => a.index.compareTo(b.index));
    return List.unmodifiable(rows);
  }
}
