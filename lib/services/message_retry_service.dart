import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../models/message_compression.dart';
import '../models/path_selection.dart';
import '../helpers/direct_message_progress_helper.dart';
import '../helpers/mcmp_app_codec.dart';
import '../helpers/mesh_compressor.dart';
import 'app_settings_service.dart';
import 'app_debug_log_service.dart';

class _AckHistoryEntry {
  final String messageId;
  final List<int> ackHashes;
  final DateTime timestamp;

  _AckHistoryEntry({
    required this.messageId,
    required this.ackHashes,
    required this.timestamp,
  });
}

/// (messageId, timestamp, attemptIndex, pathSelection) — stored per ACK hash
/// for O(1) lookup.  [pathSelection] snapshots the route used for this
/// specific attempt so that a late PUSH_CODE_SEND_CONFIRMED credits the
/// correct path even when the message has since been retried on a different
/// route.
typedef AckHashMapping = ({
  String messageId,
  DateTime timestamp,
  int attemptIndex,
  PathSelection? pathSelection,
});

class RetryServiceConfig {
  final Future<DateTime?> Function(Contact, String, int, int) sendMessage;
  final void Function(String, Message) addMessage;
  final void Function(Message) updateMessage;
  final Function(Contact)? clearContactPath;
  final Function(Contact, Uint8List, int)? setContactPath;
  final int Function(
    int pathLength,
    int messageBytes, {
    String? contactKey,
    int? deviceTimeoutMs,
  })?
  calculateTimeout;
  final int Function(
    int pathLength,
    int pathBytes,
    int messageBytes,
    int attempt,
  )?
  calculatePhysicsMaxTimeout;
  final Uint8List? Function()? getSelfPublicKey;
  final String Function(Contact, String)? prepareContactOutboundText;
  final AppSettingsService? appSettingsService;
  final AppDebugLogService? debugLogService;
  final void Function(String, PathSelection, bool, int?)? recordPathResult;
  final void Function(String, int, int, int)? onDeliveryObserved;
  final PathSelection? Function(
    String contactKey,
    int attemptIndex,
    int maxRetries,
    List<PathSelection> recentSelections,
  )?
  selectRetryPath;

  const RetryServiceConfig({
    required this.sendMessage,
    required this.addMessage,
    required this.updateMessage,
    this.clearContactPath,
    this.setContactPath,
    this.calculateTimeout,
    this.calculatePhysicsMaxTimeout,
    this.getSelfPublicKey,
    this.prepareContactOutboundText,
    this.appSettingsService,
    this.debugLogService,
    this.recordPathResult,
    this.onDeliveryObserved,
    this.selectRetryPath,
  });
}

class MessageRetryService extends ChangeNotifier {
  static const int maxAckHistorySize = 100;

  /// Global cap on concurrent in-flight messages across ALL contacts.
  /// The firmware's expected_ack_table is a single 8-entry circular buffer
  /// shared globally; cap at 6 to leave two slots of headroom.
  static const int _maxGlobalInFlight = 6;

  /// Fallback for a transport write that never happened. The fixed sent
  /// fallback is retained only for integrations without an airtime calculator
  /// and legacy pending state that has no stored estimate.
  static const int _failedSendRetryMs = 2000;
  static const int _sentRespFallbackMs = 15000;

  /// How long a failed message stays matchable after its last attempt timed
  /// out, so an ACK that arrives late (recovered path, congested return leg)
  /// can still mark it delivered.
  static const Duration _lateAckGracePeriod = Duration(seconds: 60);

  int _maxRetries = 5;
  int get maxRetries => _maxRetries;

  final Map<String, Timer> _timeoutTimers = {};
  final Map<String, Message> _pendingMessages = {};
  final Map<String, Contact> _pendingContacts = {};

  /// Exact wire text prepared (and possibly signed) once at compose time.
  /// Automatic retries must reuse it byte-for-byte: re-encoding a signed MCMP
  /// container would produce a new timestamp and invalidate the signature.
  final Map<String, String> _preparedOutboundTexts = {};
  final Map<String, List<PathSelection>> _attemptPathHistory = {};
  final Map<String, AckHashMapping> _ackHashToMessageId = {};
  final Map<String, List<int>> _expectedAckHashes = {};
  final List<_AckHistoryEntry> _ackHistory = [];
  final Map<String, List<String>> _sendQueue = {};
  final Set<String> _activeMessages = {};
  final Set<String> _resolvedMessages = {};
  final Map<String, String> _expectedHashToMessageId = {};
  final Map<String, DirectMessageProgressTracker> _progressTrackers = {};
  final Map<String, List<Uint8List>> _retiredProgressPayloads = {};
  bool _sendingPaused = false;
  int _sendingGeneration = 0;

  RetryServiceConfig? _config;

  MessageRetryService();

  void initialize(RetryServiceConfig config) {
    _config = config;
  }

  void setMaxRetries(int value) {
    _maxRetries = value.clamp(2, 10);
  }

  void setSendingPaused(bool paused) {
    if (_sendingPaused == paused) return;
    _sendingPaused = paused;
    if (paused) {
      _sendingGeneration++;
      for (final timer in _timeoutTimers.values) {
        timer.cancel();
      }
      _timeoutTimers.clear();
      return;
    }

    for (final messageId in List<String>.from(_activeMessages)) {
      final pendingMessage = _pendingMessages[messageId];
      if (pendingMessage == null) continue;
      if (pendingMessage.status == MessageStatus.sent) {
        _startTimeoutTimer(
          messageId,
          pendingMessage.estimatedTimeoutMs ?? _sentRespFallbackMs,
        );
        continue;
      }
      unawaited(
        _attemptSend(messageId).catchError((e) {
          debugPrint('_attemptSend threw for $messageId after resume: $e');
          if (_sendingPaused) return;
          final message = _pendingMessages[messageId];
          final contactKey = _pendingContacts[messageId]?.publicKeyHex;
          if (message != null) {
            final failed = message.copyWith(status: MessageStatus.failed);
            _pendingMessages[messageId] = failed;
            _config?.updateMessage(failed);
          }
          if (contactKey != null) {
            _onMessageResolved(messageId, contactKey);
          }
        }),
      );
    }
    for (final contactKey in List<String>.from(_sendQueue.keys)) {
      _sendNextForContact(contactKey);
    }
  }

  /// Compute expected ACK hash using same algorithm as firmware:
  /// SHA256([timestamp(4)][attempt(1)][text][sender_pubkey(32)]) -> first 4 bytes
  static int computeExpectedAckHash(
    int timestampSeconds,
    int attempt,
    String text,
    Uint8List senderPubKey,
  ) {
    final textBytes = utf8.encode(text);
    final buffer = Uint8List(4 + 1 + textBytes.length + senderPubKey.length);
    int offset = 0;

    // timestamp (4 bytes, little-endian)
    buffer[offset++] = timestampSeconds & 0xFF;
    buffer[offset++] = (timestampSeconds >> 8) & 0xFF;
    buffer[offset++] = (timestampSeconds >> 16) & 0xFF;
    buffer[offset++] = (timestampSeconds >> 24) & 0xFF;

    // attempt (1 byte)
    buffer[offset++] = attempt & 0x03;

    // text
    buffer.setRange(offset, offset + textBytes.length, textBytes);
    offset += textBytes.length;

    // sender public key (32 bytes)
    buffer.setRange(offset, offset + senderPubKey.length, senderPubKey);

    // Compute SHA256 and return first 4 bytes
    final hash = sha256.convert(buffer);
    final bytes = Uint8List.fromList(hash.bytes.sublist(0, 4));
    return (bytes[3] << 24) | (bytes[2] << 16) | (bytes[1] << 8) | bytes[0];
  }

  Future<void> sendMessageWithRetry({
    required Contact contact,
    required String text,
    String? messageId,
    DateTime? timestamp,
    String? preparedOutboundText,
    String? originalText,
    String? translatedLanguageCode,
    String? translationModelId,
    MessageCompressionType? compressionType,
    int? compressionSavingsPercent,
    int? compressionOriginalBytes,
    int? compressionPayloadBytes,
    McmpSignatureStatus mcmpSignatureStatus = McmpSignatureStatus.none,
    int? mcmpTimestamp,
    String? mcmpSenderName,
    bool mcmpIsSigned = false,
    Uint8List? mcmpSignature,
    Uint8List? pathBytes,
    int? pathLength,
  }) async {
    final resolvedMessageId = messageId ?? const Uuid().v4();
    final resolved = resolvePathSelection(contact);
    final messagePathBytes =
        pathBytes ?? Uint8List.fromList(resolved.pathBytes);
    final messagePathLength =
        pathLength ?? (resolved.useFlood ? -1 : resolved.hopCount);
    final effectiveOutbound =
        preparedOutboundText ??
        _config?.prepareContactOutboundText?.call(contact, text) ??
        text;
    final message = Message(
      senderKey: contact.publicKey,
      text: text,
      rawText: effectiveOutbound,
      originalText: originalText,
      translatedLanguageCode: translatedLanguageCode,
      translationModelId: translationModelId,
      wasMcmpCompressed:
          compressionType == MessageCompressionType.mcmp ||
          MeshCompressor.instance.hasPrefix(effectiveOutbound) ||
          McmpAppCodec.isTextPayload(effectiveOutbound),
      compressionType: compressionType,
      compressionSavingsPercent: compressionSavingsPercent,
      compressionOriginalBytes: compressionOriginalBytes,
      compressionPayloadBytes: compressionPayloadBytes,
      mcmpSignatureStatus: mcmpSignatureStatus,
      mcmpTimestamp: mcmpTimestamp,
      mcmpSenderName: mcmpSenderName,
      mcmpIsSigned: mcmpIsSigned,
      mcmpSignature: mcmpSignature,
      timestamp: timestamp ?? DateTime.now(),
      isOutgoing: true,
      status: MessageStatus.pending,
      messageId: resolvedMessageId,
      retryCount: 0,
      pathLength: messagePathLength,
      pathBytes: messagePathBytes,
    );

    _pendingMessages[resolvedMessageId] = message;
    _pendingContacts[resolvedMessageId] = contact;
    if (preparedOutboundText != null) {
      _preparedOutboundTexts[resolvedMessageId] = preparedOutboundText;
    }

    _config?.addMessage(contact.publicKeyHex, message);

    // Queue per contact — one message in-flight per contact at a time, and
    // bounded globally by _maxGlobalInFlight across all contacts so we never
    // overflow the firmware's 8-entry global expected_ack_table.
    final contactKey = contact.publicKeyHex;
    _sendQueue[contactKey] ??= [];
    _sendQueue[contactKey]!.add(resolvedMessageId);

    if (!_activeMessages.any(
      (id) => _pendingContacts[id]?.publicKeyHex == contactKey,
    )) {
      _sendNextForContact(contactKey);
    }
  }

  void _sendNextForContact(String contactKey) {
    if (_sendingPaused) return;
    if (_activeMessages.any(
      (id) => _pendingContacts[id]?.publicKeyHex == contactKey,
    )) {
      return;
    }
    // Enforce the global in-flight cap before starting a new send.
    // The firmware's expected_ack_table is a single 8-entry circular buffer
    // shared across all contacts; exceeding it silently evicts an older slot.
    if (_activeMessages.length >= _maxGlobalInFlight) return;

    final queue = _sendQueue[contactKey];
    if (queue == null) return;

    // Drain stale entries iteratively instead of recursing.
    while (queue.isNotEmpty) {
      final messageId = queue.removeAt(0);
      if (_pendingMessages.containsKey(messageId)) {
        _activeMessages.add(messageId);
        _attemptSend(messageId).catchError((e) {
          debugPrint('_attemptSend threw for $messageId: $e');
          if (_sendingPaused) return;
          final msg = _pendingMessages[messageId];
          if (msg != null) {
            final failed = msg.copyWith(status: MessageStatus.failed);
            _pendingMessages[messageId] = failed;
            _config?.updateMessage(failed);
          }
          _onMessageResolved(messageId, contactKey);
        });
        return;
      }
    }
  }

  void _onMessageResolved(String messageId, String contactKey) {
    if (_resolvedMessages.contains(messageId)) return;
    _resolvedMessages.add(messageId);
    // If cleanup already removed this message from the active set, it has
    // already pumped the queues; avoid double-pumping.
    if (!_activeMessages.remove(messageId)) return;
    _pumpQueues(contactKey);
  }

  void _pumpQueues(String contactKey) {
    // Pump this contact's queue first, then any other contacts that are waiting.
    _sendNextForContact(contactKey);
    for (final key in _sendQueue.keys) {
      if (key == contactKey) continue;
      if (_activeMessages.length >= _maxGlobalInFlight) break;
      final queue = _sendQueue[key];
      if (queue != null && queue.isNotEmpty) {
        _sendNextForContact(key);
      }
    }
  }

  PathSelection? _selectPathForAttempt(Message message, Contact contact) {
    final config = _config;
    if (config == null) return null;
    final autoRotationEnabled =
        config.appSettingsService?.settings.autoRouteRotationEnabled == true;
    if (!autoRotationEnabled ||
        contact.pathOverride != null ||
        config.selectRetryPath == null) {
      return null;
    }

    final recentSelections = List<PathSelection>.from(
      _attemptPathHistory[message.messageId] ?? const <PathSelection>[],
    );
    return config.selectRetryPath!(
      contact.publicKeyHex,
      message.retryCount,
      maxRetries,
      recentSelections,
    );
  }

  void _recordAttemptPathHistory(String messageId, PathSelection selection) {
    if (selection.useFlood) return;
    final history = _attemptPathHistory.putIfAbsent(messageId, () => []);
    history.add(selection);
    if (history.length > recentAttemptDiversityWindow) {
      history.removeAt(0);
    }
  }

  Future<void> _attemptSend(String messageId) async {
    if (_sendingPaused) return;
    final sendingGeneration = _sendingGeneration;
    final message = _pendingMessages[messageId];
    final contact = _pendingContacts[messageId];
    final config = _config;

    if (message == null || contact == null || config == null) return;

    final currentSelection = _selectPathForAttempt(message, contact);

    if (currentSelection != null) {
      final updatedMessage = message.copyWith(
        pathLength: currentSelection.useFlood ? -1 : currentSelection.hopCount,
        pathBytes: currentSelection.useFlood
            ? Uint8List(0)
            : Uint8List.fromList(currentSelection.pathBytes),
      );
      _pendingMessages[messageId] = updatedMessage;
    } else if (message.retryCount > 0) {
      // No schedule entry for this retry — re-resolve path from current contact
      // state so user's path override changes are picked up between retries.
      final resolved = resolvePathSelection(contact);
      final updatedMessage = message.copyWith(
        pathLength: resolved.useFlood ? -1 : resolved.hopCount,
        pathBytes: Uint8List.fromList(resolved.pathBytes),
      );
      _pendingMessages[messageId] = updatedMessage;
    }

    // Re-read after potential schedule update
    final effectiveMessage = _pendingMessages[messageId] ?? message;
    final attemptStartedAt = DateTime.now();
    final hopCount = effectiveMessage.pathLength ?? -1;
    final progressMessage = effectiveMessage.copyWith(
      deliveryProgressTotalSteps: hopCount >= 0 ? hopCount + 1 : 0,
      deliveryProgressCompletedSteps: 0,
    );
    _pendingMessages[messageId] = progressMessage;
    _retireProgressTracker(messageId);
    config.updateMessage(progressMessage);

    // Sync path settings with device before sending
    if (config.setContactPath != null && config.clearContactPath != null) {
      final bool useFlood = currentSelection != null
          ? currentSelection.useFlood
          : (effectiveMessage.pathLength != null &&
                effectiveMessage.pathLength! < 0);
      final List<int> pathBytes = currentSelection != null
          ? currentSelection.pathBytes
          : effectiveMessage.pathBytes;
      final int hopCount = currentSelection != null
          ? currentSelection.hopCount
          : (effectiveMessage.pathLength ?? 0);

      if (useFlood) {
        await config.clearContactPath!(contact);
      } else if (effectiveMessage.pathLength != null) {
        await config.setContactPath!(
          contact,
          Uint8List.fromList(pathBytes),
          hopCount,
        );
      }
    }

    // Re-validate after async gap — a timer or ACK could have resolved/retried
    // this message while we were awaiting the path callback.
    final currentMessage = _pendingMessages[messageId];
    if (currentMessage == null || _resolvedMessages.contains(messageId)) {
      debugPrint(
        '_attemptSend: message $messageId resolved during path sync, aborting',
      );
      return;
    }
    if (currentMessage.retryCount != message.retryCount) {
      debugPrint(
        '_attemptSend: message $messageId retryCount changed during path sync, aborting',
      );
      return;
    }
    if (_sendingPaused || sendingGeneration != _sendingGeneration) return;

    if (currentSelection != null) {
      _recordAttemptPathHistory(messageId, currentSelection);
    }

    final attempt = message.retryCount;
    final timestampSeconds = message.timestamp.millisecondsSinceEpoch ~/ 1000;

    // Compute expected ACK hash that device will return in RESP_CODE_SENT
    // IMPORTANT: Use the transformed text (with SMAZ encoding if enabled) to match device's hash
    final selfPubKey = config.getSelfPublicKey?.call();
    if (selfPubKey != null) {
      final outboundText =
          _preparedOutboundTexts[messageId] ??
          config.prepareContactOutboundText?.call(contact, message.text) ??
          message.text;
      final expectedHash = MessageRetryService.computeExpectedAckHash(
        timestampSeconds,
        attempt,
        outboundText,
        selfPubKey,
      );
      final expectedHashHex = expectedHash.toRadixString(16).padLeft(8, '0');
      _expectedHashToMessageId[expectedHashHex] = messageId;

      final shortText = message.text.length > 20
          ? '${message.text.substring(0, 20)}...'
          : message.text;
      config.debugLogService?.info(
        'Sent "$shortText" to ${contact.name} → expect ACK hash $expectedHashHex (attempt $attempt)',
        tag: 'AckHash',
      );
    }

    // Send the exact prepared wire text when available; the connector's
    // prepare step is a no-op on already-encoded containers, so automatic
    // retries reuse the signed body byte-for-byte.
    final sentByRadioAt = await config.sendMessage(
      contact,
      _preparedOutboundTexts[messageId] ?? message.text,
      attempt,
      timestampSeconds,
    );
    if (_sendingPaused || sendingGeneration != _sendingGeneration) return;
    if (sentByRadioAt != null) {
      final currentMessage = _pendingMessages[messageId];
      if (currentMessage != null) {
        final waitSeconds = sentByRadioAt
            .difference(attemptStartedAt)
            .inSeconds;
        final clampedWaitSeconds = waitSeconds < 0 ? 0 : waitSeconds;
        // Store the real TX anchor separately from the visible compose time.
        final updatedMessage = currentMessage.copyWith(
          receivedAt: contact.type == advTypeRoom
              ? currentMessage.receivedAt ?? sentByRadioAt
              : null,
          sentByRadioAt: sentByRadioAt,
          sentByRadioWaitSeconds: [
            ...currentMessage.sentByRadioWaitSeconds,
            clampedWaitSeconds,
          ],
        );
        _pendingMessages[messageId] = updatedMessage;
        config.updateMessage(updatedMessage);
      }
    }

    // updateMessageFromSent (RESP_CODE_SENT) is the only place that arms the
    // retry timer. If the send silently failed or the response was lost to a
    // disconnect, the message would stay pending forever and leak its
    // in-flight slot — arm a fallback so every pending message always has a
    // live timer.
    final finalMessage = _pendingMessages[messageId];
    if (finalMessage != null &&
        !_resolvedMessages.contains(messageId) &&
        finalMessage.status == MessageStatus.pending &&
        finalMessage.retryCount == attempt) {
      final fallbackTimeoutMs = sentByRadioAt == null
          ? _failedSendRetryMs
          : _calculateSentResponseFallbackTimeout(finalMessage, contact);
      _startTimeoutTimer(
        messageId,
        fallbackTimeoutMs,
      );
    }
  }

  int _calculateSentResponseFallbackTimeout(
    Message message,
    Contact contact,
  ) {
    final config = _config;
    final calculate = config?.calculatePhysicsMaxTimeout;
    if (config == null || calculate == null) return _sentRespFallbackMs;
    final outboundText =
        _preparedOutboundTexts[message.messageId] ??
        config.prepareContactOutboundText?.call(contact, message.text) ??
        message.text;
    return calculate(
      message.pathLength ?? contact.pathLength,
      message.pathBytes.length,
      utf8.encode(outboundText).length,
      message.retryCount,
    );
  }

  bool updateMessageFromSent(int ackHash, int timeoutMs) {
    // Firmware sets expected_ack = 0 for CLI/command sends (TXT_TYPE_CLI_DATA).
    // No ACK will ever be issued for these, so arming a retry timer is wrong.
    if (ackHash == 0) return false;

    final config = _config;
    if (config == null) return false;

    final ackHashHex = ackHash.toRadixString(16).padLeft(8, '0');

    // Try hash-based matching (fixes LoRa message drops causing mismatches)
    String? messageId = _expectedHashToMessageId.remove(ackHashHex);
    Contact? contact;

    if (messageId != null) {
      contact = _pendingContacts[messageId];
      final message = _pendingMessages[messageId];

      if (contact != null && message != null) {
        final shortText = message.text.length > 20
            ? '${message.text.substring(0, 20)}...'
            : message.text;
        config.debugLogService?.info(
          'RESP_CODE_SENT received: ACK hash $ackHashHex ✓ matched "$shortText" to ${contact.name}',
          tag: 'AckHash',
        );
      } else {
        config.debugLogService?.warn(
          'RESP_CODE_SENT: ACK hash $ackHashHex matched but message no longer pending',
          tag: 'AckHash',
        );
        messageId = null;
        contact = null;
      }
    }

    if (messageId == null || contact == null) {
      debugPrint('No pending message found for ACK hash: $ackHashHex');
      return false;
    }

    final message = _pendingMessages[messageId]!;
    _armProgressTracker(messageId, message, contact);
    _ackHashToMessageId[ackHashHex] = (
      messageId: messageId,
      timestamp: DateTime.now(),
      attemptIndex: message.retryCount,
      pathSelection: _selectionFromMessage(message),
    );

    // Add this ACK hash to the list of expected ACKs for this message (for history)
    _expectedAckHashes[messageId] ??= [];
    if (!_expectedAckHashes[messageId]!.any((hash) => hash == ackHash)) {
      _expectedAckHashes[messageId]!.add(ackHash);
    }

    // Calculate timeout: prefer ML prediction, then device-provided, then physics fallback
    final pathLengthValue = message.pathLength ?? contact.pathLength;
    final outboundTextForTimeout =
        _preparedOutboundTexts[messageId] ??
        config.prepareContactOutboundText?.call(contact, message.text) ??
        message.text;
    final messageBytesForTimeout = utf8.encode(outboundTextForTimeout).length;

    int actualTimeout = timeoutMs;
    if (config.calculateTimeout != null) {
      actualTimeout = config.calculateTimeout!(
        pathLengthValue,
        messageBytesForTimeout,
        contactKey: contact.publicKeyHex,
        deviceTimeoutMs: timeoutMs > 0 ? timeoutMs : null,
      );
    }

    final updatedMessage = message.copyWith(
      status: MessageStatus.sent,
      expectedAckHash: ackHash,
      estimatedTimeoutMs: actualTimeout,
      sentAt: DateTime.now(),
    );

    _pendingMessages[messageId] = updatedMessage;
    config.updateMessage(updatedMessage);

    _startTimeoutTimer(messageId, actualTimeout);
    return true;
  }

  bool get hasPendingMessages => _pendingMessages.isNotEmpty;

  void handleRxLogFrame(Uint8List frame) {
    final echo = DirectMessageEcho.tryParse(frame);
    if (echo == null || _progressTrackers.isEmpty) return;

    final boundMatches = <(DirectMessageProgressTracker, int)>[];
    final unboundMatches = <(DirectMessageProgressTracker, int)>[];
    for (final tracker in _progressTrackers.values) {
      final stage = tracker.matchingStage(echo);
      if (stage == null) continue;
      (tracker.isBound ? boundMatches : unboundMatches).add((tracker, stage));
    }

    final matches = boundMatches.isNotEmpty ? boundMatches : unboundMatches;
    // The packet carries only one-byte source/destination hashes. Refuse an
    // ambiguous first match instead of crediting the wrong conversation.
    if (matches.length != 1) return;

    final (tracker, completedHops) = matches.single;
    final message = _pendingMessages[tracker.messageId];
    if (message == null || message.retryCount != tracker.attemptIndex) return;

    tracker.bind(echo);
    if (completedHops <= message.deliveryProgressCompletedSteps) return;
    final updatedMessage = message.copyWith(
      deliveryProgressCompletedSteps: completedHops.clamp(
        0,
        message.deliveryProgressTotalSteps,
      ).toInt(),
    );
    _pendingMessages[tracker.messageId] = updatedMessage;
    _config?.updateMessage(updatedMessage);
  }

  void _armProgressTracker(
    String messageId,
    Message message,
    Contact contact,
  ) {
    final existing = _progressTrackers[messageId];
    if (existing?.attemptIndex == message.retryCount) return;
    _retireProgressTracker(messageId);
    final hopCount = message.pathLength;
    final selfPublicKey = _config?.getSelfPublicKey?.call();
    if (hopCount == null ||
        hopCount <= 0 ||
        selfPublicKey == null ||
        selfPublicKey.isEmpty ||
        contact.publicKey.isEmpty ||
        message.pathBytes.isEmpty ||
        message.pathBytes.length % hopCount != 0) {
      return;
    }
    final pathHashWidth = message.pathBytes.length ~/ hopCount;
    if (pathHashWidth < 1 || pathHashWidth > 4) return;

    _progressTrackers[messageId] = DirectMessageProgressTracker(
      messageId: messageId,
      attemptIndex: message.retryCount,
      destinationHash: contact.publicKey.first,
      sourceHash: selfPublicKey.first,
      pathHashWidth: pathHashWidth,
      route: message.pathBytes,
      rejectedPayloads:
          _retiredProgressPayloads[messageId] ?? const <Uint8List>[],
    );
  }

  void _retireProgressTracker(String messageId) {
    final payload = _progressTrackers.remove(messageId)?.boundPayload;
    if (payload == null) return;
    _retiredProgressPayloads.putIfAbsent(messageId, () => []).add(payload);
  }

  /// Update the stored contact snapshot for all pending messages to this contact.
  /// Call this when the contact's pathOverride changes so retries use the new path.
  void updatePendingContact(Contact contact) {
    final keys = _pendingContacts.entries
        .where((e) => e.value.publicKeyHex == contact.publicKeyHex)
        .map((e) => e.key)
        .toList();
    for (final key in keys) {
      _pendingContacts[key] = contact;
    }
  }

  void clearPathAttemptHistory() {
    _attemptPathHistory.clear();
  }

  void _startTimeoutTimer(String messageId, int timeoutMs) {
    if (_sendingPaused) return;
    _timeoutTimers[messageId]?.cancel();
    _timeoutTimers[messageId] = Timer(Duration(milliseconds: timeoutMs), () {
      _handleTimeout(messageId);
    });
  }

  void untrack(String messageId) {
    _timeoutTimers[messageId]?.cancel();
    _cleanupMessage(messageId);
  }

  void _cleanupMessage(String messageId) {
    _moveAckHashesToHistory(messageId);
    _ackHashToMessageId.removeWhere(
      (_, mapping) => mapping.messageId == messageId,
    );
    _expectedHashToMessageId.removeWhere((_, msgId) => msgId == messageId);
    final contactKey = _pendingContacts[messageId]?.publicKeyHex;
    _pendingMessages.remove(messageId);
    _pendingContacts.remove(messageId);
    _preparedOutboundTexts.remove(messageId);
    _attemptPathHistory.remove(messageId);
    _progressTrackers.remove(messageId);
    _retiredProgressPayloads.remove(messageId);
    _timeoutTimers.remove(messageId);
    _resolvedMessages.remove(messageId);
    // Cancellation (and other cleanup paths) must release the active in-flight
    // slot and pump waiting queues so the global cap does not stall forever.
    if (_activeMessages.remove(messageId) && contactKey != null) {
      _pumpQueues(contactKey);
    }
  }

  void _handleTimeout(String messageId) {
    if (_sendingPaused) return;
    final message = _pendingMessages[messageId];
    final contact = _pendingContacts[messageId];
    final config = _config;
    final selection = message != null ? _selectionFromMessage(message) : null;

    if (message == null || contact == null) {
      debugPrint(
        'Timeout fired but message $messageId no longer pending (likely already delivered)',
      );
      return;
    }

    final shortText = message.text.length > 20
        ? '${message.text.substring(0, 20)}...'
        : message.text;
    config?.debugLogService?.warn(
      'Timeout: No ACK received for "$shortText" to ${contact.name} (attempt ${message.retryCount}) → retrying',
      tag: 'AckHash',
    );

    if (message.retryCount < maxRetries - 1) {
      final backoffMs = 1000 * (1 << message.retryCount);

      if (selection != null) {
        _recordPathResultFromMessage(
          contact.publicKeyHex,
          message,
          selection,
          false,
          null,
        );
      }

      final updatedMessage = message.copyWith(
        retryCount: message.retryCount + 1,
        status: MessageStatus.pending,
      );

      _pendingMessages[messageId] = updatedMessage;
      config?.updateMessage(updatedMessage);

      config?.debugLogService?.info(
        'Scheduling retry for "$shortText" to ${contact.name} after ${backoffMs}ms backoff',
        tag: 'AckHash',
      );

      _timeoutTimers[messageId] = Timer(Duration(milliseconds: backoffMs), () {
        if (_sendingPaused) return;
        if (!_pendingMessages.containsKey(messageId)) return;
        _attemptSend(messageId).catchError((e) {
          debugPrint('_attemptSend threw for $messageId: $e');
          if (_sendingPaused) return;
          final msg = _pendingMessages[messageId];
          if (msg != null) {
            final failed = msg.copyWith(status: MessageStatus.failed);
            _pendingMessages[messageId] = failed;
            _config?.updateMessage(failed);
          }
          _onMessageResolved(messageId, contact.publicKeyHex);
        });
      });
    } else {
      // Max retries reached - mark as failed
      final failedMessage = message.copyWith(status: MessageStatus.failed);
      _pendingMessages[messageId] = failedMessage;

      // A route the user pinned outranks this cleanup. Every other automatic
      // path decision steps aside for an override — `preparePathForContactSend`
      // and `_selectPathForAttempt` both bail on it, and `resolvePathSelection`
      // lets it win over `forceFlood` — while this branch would send
      // CMD_RESET_PATH to the node and drop it back to flood behind the user's
      // back. Forcing flood is a choice as much as picking hops is, so any
      // non-null override stops it.
      if (config?.appSettingsService?.settings.clearPathOnMaxRetry == true &&
          contact.pathOverride == null &&
          config?.clearContactPath != null) {
        config!.clearContactPath!(contact);
      }

      _recordPathResultFromMessage(
        contact.publicKeyHex,
        message,
        selection,
        false,
        null,
      );

      config?.updateMessage(failedMessage);

      notifyListeners();

      _onMessageResolved(messageId, contact.publicKeyHex);

      // Keep message in pending maps for a grace period after the final
      // attempt's ACK wait expired, so a late ACK can still match and flip the
      // message to delivered. The node reports delivery once and never repeats
      // it, so a window that closes too early leaves a delivered message shown
      // as failed for good.
      _timeoutTimers[messageId] = Timer(_lateAckGracePeriod, () {
        _cleanupMessage(messageId);
      });
    }
  }

  void _moveAckHashesToHistory(String messageId) {
    final ackHashes = _expectedAckHashes.remove(messageId);
    if (ackHashes != null && ackHashes.isNotEmpty) {
      _ackHistory.add(
        _AckHistoryEntry(
          messageId: messageId,
          ackHashes: ackHashes,
          timestamp: DateTime.now(),
        ),
      );

      while (_ackHistory.length > maxAckHistorySize) {
        _ackHistory.removeAt(0);
      }
    }
  }

  bool _checkAckHistory(int ackHash) {
    for (final entry in _ackHistory) {
      for (final expectedHash in entry.ackHashes) {
        if (expectedHash == ackHash) {
          return true;
        }
      }
    }
    return false;
  }

  void handleAckReceived(int ackHash, int tripTimeMs) {
    final config = _config;
    String? matchedMessageId;
    int? matchedAttemptIndex;
    PathSelection? matchedPathSelection;
    final ackHashHex = ackHash.toRadixString(16).padLeft(8, '0');

    // Clean up old ACK hash mappings (older than 15 minutes)
    final cutoffTime = DateTime.now().subtract(const Duration(minutes: 15));
    final hashesToRemove = <String>[];
    for (var entry in _ackHashToMessageId.entries) {
      if (entry.value.timestamp.isBefore(cutoffTime)) {
        hashesToRemove.add(entry.key);
      }
    }
    for (var hash in hashesToRemove) {
      _ackHashToMessageId.remove(hash);
    }

    // Use direct O(1) lookup via ACK hash mapping
    final mapping = _ackHashToMessageId[ackHashHex];
    if (mapping != null) {
      matchedMessageId = mapping.messageId;
      matchedAttemptIndex = mapping.attemptIndex;
      matchedPathSelection = mapping.pathSelection;
    } else {
      config?.debugLogService?.warn(
        'PUSH_CODE_SEND_CONFIRMED: ACK hash $ackHashHex not found in direct mapping, trying fallback',
        tag: 'AckHash',
      );
      // Fallback: Check against ALL expected ACK hashes (from all retry attempts)
      for (var entry in _expectedAckHashes.entries) {
        final messageId = entry.key;
        final expectedHashes = entry.value;

        for (final expectedHash in expectedHashes) {
          if (expectedHash == ackHash) {
            matchedMessageId = messageId;
            break;
          }
        }

        if (matchedMessageId != null) break;
      }
    }

    if (matchedMessageId != null) {
      final message = _pendingMessages[matchedMessageId];
      if (message == null) {
        _ackHashToMessageId.remove(ackHashHex);
        return;
      }
      final contact = _pendingContacts[matchedMessageId];
      final ackedAttempt = matchedAttemptIndex ?? message.retryCount;
      final selection = matchedPathSelection ?? _selectionFromMessage(message);

      final shortText = message.text.length > 20
          ? '${message.text.substring(0, 20)}...'
          : message.text;
      config?.debugLogService?.info(
        'PUSH_CODE_SEND_CONFIRMED: ACK hash $ackHashHex ✓ "$shortText" delivered to ${contact?.name ?? "unknown"} on attempt $ackedAttempt in ${tripTimeMs}ms',
        tag: 'AckHash',
      );

      _timeoutTimers[matchedMessageId]?.cancel();

      final deliveredMessage = message.copyWith(
        status: MessageStatus.delivered,
        deliveredAt: DateTime.now(),
        tripTimeMs: tripTimeMs,
        deliveryProgressCompletedSteps:
            message.deliveryProgressTotalSteps,
      );

      final wasAlreadyResolved = _resolvedMessages.contains(matchedMessageId);

      _cleanupMessage(matchedMessageId);

      config?.updateMessage(deliveredMessage);

      if (contact != null) {
        _recordPathResultFromMessage(
          contact.publicKeyHex,
          message,
          selection,
          true,
          tripTimeMs,
        );
        if (config?.onDeliveryObserved != null &&
            tripTimeMs > 0 &&
            message.pathLength != null) {
          final outboundTextForObserved =
              _preparedOutboundTexts[matchedMessageId] ??
              config!.prepareContactOutboundText?.call(contact, message.text) ??
              message.text;
          final messageBytesForObserved = utf8
              .encode(outboundTextForObserved)
              .length;
          config!.onDeliveryObserved!(
            contact.publicKeyHex,
            message.pathLength!,
            messageBytesForObserved,
            tripTimeMs,
          );
        }
        if (!wasAlreadyResolved) {
          _onMessageResolved(matchedMessageId, contact.publicKeyHex);
        }
      }

      notifyListeners();
    } else {
      if (_checkAckHistory(ackHash)) {
        config?.debugLogService?.info(
          'PUSH_CODE_SEND_CONFIRMED: ACK hash $ackHashHex matched a recently completed message (duplicate ACK)',
          tag: 'AckHash',
        );
      } else {
        config?.debugLogService?.error(
          'PUSH_CODE_SEND_CONFIRMED: ACK hash $ackHashHex has no matching message!',
          tag: 'AckHash',
        );
        debugPrint('No matching message found for ACK: $ackHashHex');
      }
    }
  }

  String? getContactKeyForAckHash(int ackHash) {
    for (var entry in _pendingMessages.entries) {
      final message = entry.value;
      if (message.expectedAckHash != null &&
          message.expectedAckHash == ackHash) {
        final contact = _pendingContacts[entry.key];
        return contact?.publicKeyHex;
      }
    }
    return null;
  }

  int calculateDefaultTimeout(Contact contact) {
    if (contact.pathLength < 0) {
      return 15000;
    } else {
      return 3000 + (3000 * contact.pathLength);
    }
  }

  void _recordPathResultFromMessage(
    String contactKey,
    Message message,
    PathSelection? selection,
    bool success,
    int? tripTimeMs,
  ) {
    final callback = _config?.recordPathResult;
    if (callback == null) return;
    final recordSelection = selection ?? _selectionFromMessage(message);
    if (recordSelection == null) return;
    callback(contactKey, recordSelection, success, tripTimeMs);
  }

  PathSelection? _selectionFromMessage(Message message) {
    if (message.pathLength != null && message.pathLength! < 0) {
      return const PathSelection(pathBytes: [], hopCount: -1, useFlood: true);
    }
    if (message.pathBytes.isEmpty && message.pathLength == null) {
      return null;
    }
    return PathSelection(
      pathBytes: message.pathBytes,
      hopCount: message.pathLength ?? message.pathBytes.length,
      useFlood: false,
    );
  }

  @override
  void dispose() {
    for (var timer in _timeoutTimers.values) {
      timer.cancel();
    }
    _timeoutTimers.clear();
    _pendingMessages.clear();
    _pendingContacts.clear();
    _preparedOutboundTexts.clear();
    _attemptPathHistory.clear();
    _expectedAckHashes.clear();
    _ackHistory.clear();
    _ackHashToMessageId.clear();
    _sendQueue.clear();
    _activeMessages.clear();
    _resolvedMessages.clear();
    _progressTrackers.clear();
    _retiredProgressPayloads.clear();
    super.dispose();
  }
}
