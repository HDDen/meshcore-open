import 'dart:convert';
import 'package:convert/convert.dart';
import 'dart:typed_data';

import '../models/message.dart';
import '../services/additional_identity_inbox.dart';
import '../storage/message_history_storage.dart';
import '../connector/meshcore_protocol.dart';
import 'direct_echo_crypto.dart';

/// Identity-scoped history: never uses shared history or primary-node messages.
abstract final class CompanionProxyIdentityMessages {
  static Future<List<Map<String, Object>>> read(
    AdditionalIdentityInbox? inbox, String key, int afterRow,
  ) async {
    final entry = inbox?.entryFor(key);
    if (entry == null || inbox?.isUnlocked != true) throw StateError('Identity unavailable');
    final result = <Map<String, Object>>[];
    (int, int)? before;
    while (true) {
      final rows = await MessageHistoryStorage.instance.readAdditionalIdentityMessages(
        key, before: before, limit: 1000);
      if (inbox?.entryFor(key) == null) throw StateError('Identity removed');
      for (final row in rows) {
        if (row.isOutgoing) {
          if (row.status == MessageStatus.delivered) {
            final text = utf8.encode(row.wireText);
            final plain = Uint8List(5 + text.length)..setRange(5, 5 + text.length, text);
            ByteData.sublistView(plain).setUint32(0, row.timestampSeconds, Endian.little);
            final hash = DirectEchoCrypto.ackHash(plain, text.length, entry.identity.publicKey, randomByte: 0);
            result.add({'ack': ByteData.sublistView(hash).getUint32(0, Endian.little),
              'tripMs': row.tripTimeMs ?? 0});
          }
          continue;
        }
        if (row.rowId <= afterRow) continue;
        final sender = hexToPubKey(row.senderKey);
        final signed = row.roomAuthorHex;
        final frame = Uint8List.fromList([
          respCodeContactMsgRecvV3, 0, 0, 0, ...sender.take(6), 0xff,
          signed == null ? 0 : txtTypeSigned,
          ...[(row.timestampSeconds) & 255, (row.timestampSeconds >> 8) & 255,
            (row.timestampSeconds >> 16) & 255, (row.timestampSeconds >> 24) & 255],
          if (signed != null) ...hex.decode(signed).take(4),
          ...utf8.encode(row.wireText),
        ]);
        result.add({'id': row.rowId, 'frame': frame});
      }
      if (rows.length < 1000) break;
      final last = rows.last;
      before = (last.receivedAtMs, last.rowId);
    }
    return result;
  }
}
