import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/image_chunk_transport.dart' show cmdSendChannelData;
import 'meshcore_protocol.dart';

/// A command waiting for its reply from the companion firmware.
class PendingCommandReply {
  final int commandCode;

  /// Response code the firmware sends on success (RESP_CODE_OK or a specific
  /// RESP_CODE_*). Any command may instead be answered with RESP_CODE_ERR.
  final int replyCode;

  /// For GET_CONTACT_BY_KEY: only a CONTACT frame for this key is the reply.
  final Uint8List? matchKey;
  final String? channelSendQueueId;
  final Completer<void>? completer;
  final DateTime createdAt = DateTime.now();

  PendingCommandReply({
    required this.commandCode,
    required this.replyCode,
    this.matchKey,
    this.channelSendQueueId,
    this.completer,
  });
}

/// Success reply for each command whose single reply is OK/ERR or a specific
/// RESP_CODE (companion MyMesh.cpp handleCmdFrame). Commands with no reply
/// (REBOOT) or a multi-code reply (SYNC_NEXT_MESSAGE) are not tracked.
int? replyCodeForCommand(Uint8List data) {
  switch (data[0]) {
    case cmdSendChannelTxtMsg:
    case cmdSetDeviceTime:
    case cmdSendSelfAdvert:
    case cmdSetAdvertName:
    case cmdAddUpdateContact:
    case cmdSetRadioParams:
    case cmdSetRadioTxPower:
    case cmdResetPath:
    case cmdSetAdvertLatLon:
    case cmdRemoveContact:
    case cmdShareContact:
    case cmdImportContact:
    case cmdSetChannel:
    case cmdSetOtherParams:
    case cmdSetCustomVar:
    case cmdSetFloodScope:
    case cmdSendControlData:
    case cmdSetAutoAddConfig:
    case cmdSetPathHashMode:
    case cmdSendChannelData:
      return respCodeOk;
    case cmdSendTxtMsg:
    case cmdSendLogin:
    case cmdSendStatusReq:
    case cmdSendTracePath:
    case cmdSendBinaryReq:
    case cmdSendAnonReq:
      return respCodeSent;
    case cmdSendTelemetryReq:
      // The 4-byte 'self' form answers with PUSH_CODE_TELEMETRY_RESPONSE.
      return data.length > 4 ? respCodeSent : null;
    case cmdAppStart:
      return respCodeSelfInfo;
    case cmdDeviceQuery:
      return respCodeDeviceInfo;
    case cmdGetContacts:
      return respCodeContactsStart;
    case cmdGetContactByKey:
      return respCodeContact;
    case cmdGetDeviceTime:
      return respCodeCurrTime;
    case cmdExportContact:
      return respCodeExportContact;
    case cmdGetBattAndStorage:
      return respCodeBattAndStorage;
    case cmdGetChannel:
      return respCodeChannelInfo;
    case cmdGetCustomVar:
      return respCodeCustomVars;
    case cmdGetStats:
      return respCodeStats;
    case cmdGetAutoAddConfig:
      return respCodeAutoAddConfig;
    case cmdGetAllowedRepeatFreq:
      return respCodeAllowedRepeatFreq;
  }
  return null;
}

/// FIFO of commands awaiting a reply. The firmware handles commands in order
/// and answers each with OK, ERR or a specific RESP_CODE, so an ERR belongs
/// to the oldest pending command and an OK to the oldest one expecting OK.
class PendingCommandReplies {
  PendingCommandReplies({required this.staleAfter});

  /// Entries older than this are dropped so a lost reply cannot swallow a
  /// later, unrelated OK/ERR. Awaited entries time out in sendFrame first.
  final Duration staleAfter;
  final List<PendingCommandReply> _queue = [];

  int get length => _queue.length;

  PendingCommandReply? track(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsOk = false,
    bool waitForReply = false,
  }) {
    if (data.isEmpty) return null;
    final replyCode =
        replyCodeForCommand(data) ?? (expectsOk ? respCodeOk : null);
    if (replyCode == null) return null;
    final pending = PendingCommandReply(
      commandCode: data[0],
      replyCode: replyCode,
      matchKey: data[0] == cmdGetContactByKey && data.length >= 1 + pubKeySize
          ? Uint8List.fromList(data.sublist(1, 1 + pubKeySize))
          : null,
      channelSendQueueId: channelSendQueueId,
      completer: waitForReply ? Completer<void>() : null,
    );
    if (pending.completer != null) {
      // The sender awaits this future after transport I/O; attach an error
      // handler now in case the ERR arrives first.
      unawaited(pending.completer!.future.catchError((_) {}));
    }
    _queue.add(pending);
    return pending;
  }

  void remove(PendingCommandReply pending) => _queue.remove(pending);

  void clear() => _queue.clear();

  /// Completes the oldest command whose success reply is [frame]'s code.
  bool completeReply(Uint8List frame) {
    if (frame.isEmpty) return false;
    final code = frame[0];
    if (code == respCodeOk || code == respCodeErr) return false;
    final key = code == respCodeContact && frame.length >= 1 + pubKeySize
        ? frame.sublist(1, 1 + pubKeySize)
        : null;
    final index = _queue.indexWhere(
      (p) =>
          p.replyCode == code &&
          (p.matchKey == null || listEquals(p.matchKey, key)),
    );
    if (index < 0) return false;
    _queue.removeAt(index).completer?.complete();
    return true;
  }

  /// Attributes RESP_CODE_OK; commands expecting a specific reply are skipped.
  PendingCommandReply? takeOk() {
    _pruneStale();
    final index = _queue.indexWhere((p) => p.replyCode == respCodeOk);
    if (index < 0) return null;
    final pending = _queue.removeAt(index);
    pending.completer?.complete();
    return pending;
  }

  /// Attributes RESP_CODE_ERR to the oldest pending command.
  PendingCommandReply? takeErr(int errCode) {
    _pruneStale();
    if (_queue.isEmpty) return null;
    final pending = _queue.removeAt(0);
    pending.completer?.completeError(
      Exception('Command failed with error code $errCode'),
    );
    return pending;
  }

  void _pruneStale() {
    final cutoff = DateTime.now().subtract(staleAfter);
    _queue.removeWhere((p) => p.createdAt.isBefore(cutoff));
  }
}
