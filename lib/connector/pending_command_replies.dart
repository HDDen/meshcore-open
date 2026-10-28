import 'dart:async';

import 'package:flutter/foundation.dart';

import 'meshcore_protocol.dart';

/// The node's RESP_CODE_ERR to a command whose sender waited for its reply.
class CommandFailedException implements Exception {
  const CommandFailedException(this.errCode);

  /// The firmware's ERR_CODE_* value, or -1 when the frame carried none.
  final int errCode;

  @override
  String toString() => 'Exception: Command failed with error code $errCode';
}

/// A command waiting for its reply from the companion firmware.
class PendingCommandReply {
  final int commandCode;

  /// Response code the firmware sends on success (RESP_CODE_OK or a specific
  /// RESP_CODE_*). Any command may instead be answered with RESP_CODE_ERR.
  final int replyCode;

  /// For GET_CONTACT_BY_KEY: only a CONTACT frame for this key is the reply.
  final Uint8List? matchKey;
  final Uint8List? cliPrefix;
  final String? channelSendQueueId;
  final Completer<void>? completer;
  final DateTime createdAt;

  /// Set when the sender gave up waiting. The entry then stays queued as a
  /// tombstone so the firmware's late reply is absorbed here instead of being
  /// credited to the next command.
  DateTime? timedOutAt;

  bool get isTombstone => timedOutAt != null;

  PendingCommandReply({
    required this.commandCode,
    required this.replyCode,
    this.matchKey,
    this.cliPrefix,
    this.channelSendQueueId,
    this.completer,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
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
    // Sent by this fork only; tracked so their OK/ERR is not taken for the
    // reply to another command. CMD_EXPORT_PRIVATE_KEY stays out: a node
    // built without the export answers RESP_CODE_DISABLED, which no entry
    // pairs, and the entry left behind would take the next ERR.
    case cmdSignData:
    case cmdSetDefaultFloodScope:
    case cmdSendRawPacket:
      return respCodeOk;
    case cmdSignStart:
      return respCodeSignStart;
    case cmdSignFinish:
      return respCodeSignature;
    case cmdGetDefaultFloodScope:
      return respCodeDefaultFloodScope;
    case cmdRunCliCommand:
      return respCodeCliReply;
  }
  return null;
}

/// FIFO of commands awaiting a reply. The firmware handles commands in order
/// and answers each with OK, ERR or a specific RESP_CODE, so an ERR belongs
/// to the oldest pending command and an OK to the oldest one expecting OK.
class PendingCommandReplies {
  PendingCommandReplies({
    required this.staleAfter,
    this.tombstoneLifetime = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Entries older than this are dropped so a lost reply cannot swallow a
  /// later, unrelated OK/ERR. Awaited entries time out in sendFrame first.
  final Duration staleAfter;

  /// How long a timed-out entry waits for its late reply. Kept short so a
  /// reply that never comes swallows at most a brief window of replies.
  final Duration tombstoneLifetime;
  final DateTime Function() _clock;
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
      cliPrefix: data[0] == cmdRunCliCommand && data.length >= 4 && data[3] == 0x7c
          ? Uint8List.fromList(data.sublist(1, 4)) : null,
      channelSendQueueId: channelSendQueueId,
      completer: waitForReply ? Completer<void>() : null,
      createdAt: _clock(),
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

  void abandonCli(String prefix) {
    for (final pending in _queue) {
      if (pending.commandCode == cmdRunCliCommand &&
          listEquals(pending.cliPrefix, [...prefix.codeUnits, 0x7c])) {
        markTimedOut(pending);
      }
    }
  }

  /// Marks [pending] as abandoned by its sender. It keeps its place in the
  /// FIFO so a late reply is consumed by it rather than misattributed.
  void markTimedOut(PendingCommandReply pending) {
    if (!_queue.contains(pending)) return;
    pending.timedOutAt = _clock();
  }

  void clear() => _queue.clear();

  /// Completes the oldest command whose success reply is [frame]'s code.
  bool completeReply(Uint8List frame) {
    if (frame.isEmpty) return false;
    _pruneStale();
    final code = frame[0];
    if (code == respCodeOk || code == respCodeErr) return false;
    final key = code == respCodeContact && frame.length >= 1 + pubKeySize
        ? frame.sublist(1, 1 + pubKeySize)
        : null;
    final index = _queue.indexWhere(
      (p) =>
          p.replyCode == code &&
          (p.cliPrefix == null || (frame.length >= 4 &&
            listEquals(p.cliPrefix, frame.sublist(1, 4)))) &&
          (p.matchKey == null || listEquals(p.matchKey, key)),
    );
    if (index < 0) return false;
    _queue.removeAt(index).completer?.complete();
    return true;
  }

  /// Attributes RESP_CODE_OK; commands expecting a specific reply are skipped.
  /// Returns null when no command matches or a timed-out entry absorbed it.
  PendingCommandReply? takeOk() {
    _pruneStale();
    final index = _queue.indexWhere((p) => p.replyCode == respCodeOk);
    if (index < 0) return null;
    final pending = _queue.removeAt(index);
    if (pending.isTombstone) return null;
    pending.completer?.complete();
    return pending;
  }

  /// Attributes RESP_CODE_ERR to the oldest pending command.
  /// Returns null when nothing is pending or a timed-out entry absorbed it.
  PendingCommandReply? takeErr(int errCode) {
    _pruneStale();
    if (_queue.isEmpty) return null;
    final pending = _queue.removeAt(0);
    if (pending.isTombstone) return null;
    pending.completer?.completeError(CommandFailedException(errCode));
    return pending;
  }

  void _pruneStale() {
    final now = _clock();
    final cutoff = now.subtract(staleAfter);
    final tombstoneCutoff = now.subtract(tombstoneLifetime);
    _queue.removeWhere(
      (p) =>
          p.createdAt.isBefore(p.commandCode == cmdRunCliCommand
            ? now.subtract(const Duration(seconds: 30)) : cutoff) ||
          (p.timedOutAt?.isBefore(tombstoneCutoff) ?? false),
    );
  }
}
