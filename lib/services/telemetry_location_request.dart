import 'dart:async';

import 'package:flutter/foundation.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/cayenne_lpp.dart';
import '../helpers/contact_telemetry_location.dart';
import '../helpers/request_sent_tags.dart';
import '../models/contact.dart';
import '../models/path_selection.dart';
import '../utils/app_logger.dart';

enum TelemetryLocationResult { located, noLocation, failed, cancelled }

/// One explicit map action, with no retries or background polling. Cancel on
/// leaving the map. A frame handed to the transport cannot be recalled;
/// cancellation skips command-lock queued requests and ignores late replies.
class TelemetryLocationRequest {
  final Completer<void> _cancellation = Completer<void>();
  bool _started = false;

  void cancel() {
    if (!_cancellation.isCompleted) _cancellation.complete();
  }

  Future<TelemetryLocationResult> run(
    MeshCoreConnector connector,
    Contact contact,
  ) async {
    if (_started) throw StateError('A location request can only run once');
    _started = true;
    if (_cancellation.isCompleted) return TelemetryLocationResult.cancelled;
    if (!contact.isActive ||
        (contact.type != advTypeChat && contact.type != advTypeSensor)) {
      return TelemetryLocationResult.failed;
    }
    final nodeKey = connector.selfPublicKeyHex;
    final done = Completer<List<Map<String, dynamic>>?>();
    final tags = RequestSentTags();
    Timer? timeout;
    PathSelection? selection;
    var closed = false;
    var sent = false;

    bool isCurrent() => !closed && !_cancellation.isCompleted &&
        connector.isConnected && nodeKey.isNotEmpty &&
        connector.selfPublicKeyHex == nodeKey &&
        connector.getContactByPubKeyHex(contact.publicKeyHex) != null;
    void finish(List<Map<String, dynamic>>? parsed) {
      if (done.isCompleted) return;
      timeout?.cancel();
      done.complete(parsed);
    }
    bool canSend() {
      if (!done.isCompleted && isCurrent()) return true;
      finish(null);
      return false;
    }
    void arm(Duration duration) {
      timeout?.cancel();
      timeout = Timer(duration, () => finish(null));
    }
    void connectionChanged() {
      if (!isCurrent()) finish(null);
    }

    if (!isCurrent()) return TelemetryLocationResult.cancelled;
    connector.addListener(connectionChanged);
    final subscription = connector.receivedFrames.listen((frame) {
      if (done.isCompleted || frame.isEmpty) return;
      if (!isCurrent()) {
        finish(null);
        return;
      }
      // Ignore all telemetry/SENT while path preparation, command locking
      // or SET_FLOOD_SCOPE is still pending. None can be our response yet.
      if (!tags.isWaiting) return;
      try {
        final reader = BufferReader(frame);
        final code = reader.readByte();
        if (code == respCodeSent) {
          reader.skipBytes(1);
          final tag = reader.readUInt32LE();
          final estimate = Duration(milliseconds: reader.readUInt32LE());
          final nextTimeout = tags.recordSent(tag, estimate);
          if (nextTimeout != null) arm(nextTimeout);
        } else if (code == respCodeErr && !tags.hasDeadline) {
          finish(null);
        } else if (code == pushCodeBinaryResponse) {
          reader.skipBytes(1);
          if (!tags.matches(reader.readUInt32LE())) return;
          finish(CayenneLpp.parseByChannel(reader.readRemainingBytes()));
        } else if (code == pushCodeTelemetryResponse && contact.type == advTypeChat) {
          reader.skipBytes(1);
          if (!listEquals(reader.readBytes(6), contact.publicKey.sublist(0, 6))) return;
          finish(CayenneLpp.parseByChannel(reader.readRemainingBytes()));
        }
      } catch (error) {
        // An incomplete/unrelated frame must not consume this request.
        appLogger.warn('Malformed telemetry location response: $error');
      }
    }, onDone: () => finish(null));
    unawaited(_cancellation.future.then<void>((_) => finish(null)));

    Future<void> send() async {
      try {
        selection = await connector.preparePathForContactSend(
          connector.getContactByPubKeyHex(contact.publicKeyHex) ?? contact,
        );
        if (!canSend()) return;
        final frame = contact.type == advTypeChat
            ? buildSendTelemetryReq(contact.publicKey)
            : buildSendBinaryReq(contact.publicKey, payload: buildTelemetryBinaryPayload());
        await connector.sendContactFrame(
          contact, frame, useFlood: selection!.useFlood,
          canSend: canSend,
          onSending: () {
            sent = true;
            tags.start();
            arm(const Duration(seconds: 10));
          },
        );
      } catch (error) {
        if (!done.isCompleted) {
          appLogger.warn('Telemetry location request failed: $error');
          finish(null);
        }
      }
    }

    try {
      // Cancellation can complete immediately even if route preparation or
      // another writer is held. The guarded continuation cannot send later.
      unawaited(send());
      final parsed = await done.future;
      if (!isCurrent()) return TelemetryLocationResult.cancelled;
      final path = selection;
      if (sent && path != null) {
        connector.recordRepeaterPathResult(contact, path, parsed != null, null);
      }
      if (parsed == null) return TelemetryLocationResult.failed;
      final fix = telemetryGpsFix(parsed);
      if (fix == null) return TelemetryLocationResult.noLocation;
      final applied = connector.updateContactLocationFromTelemetry(
        contact.publicKeyHex, fix.latitude, fix.longitude,
        expectedNodeKey: nodeKey,
      );
      return applied ? TelemetryLocationResult.located : TelemetryLocationResult.cancelled;
    } finally {
      closed = true;
      tags.clear();
      timeout?.cancel();
      connector.removeListener(connectionChanged);
      await subscription.cancel();
    }
  }
}
