import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';

/// Runs one full-key zero-hop discovery request and records matching replies.
class ZeroHopDeviceDiscovery {
  static const responseWindow = Duration(seconds: 60);
  static const ownerRequestThrottle = Duration(milliseconds: 1500);
  static const ownerRequestFallbackTimeout = Duration(seconds: 10);
  static const ownerRequestTimeoutPadding = Duration(seconds: 2);

  final MeshCoreConnector connector;
  final Random _random = Random();

  StreamSubscription<Uint8List>? _framesSubscription;
  Timer? _responseTimer;
  Completer<void>? _completion;
  Completer<String?>? _ownerCompletion;
  int? _tag;
  bool _cancelled = false;

  ZeroHopDeviceDiscovery(this.connector);

  Future<void> run() async {
    if (_completion != null) return;

    final completion = Completer<void>();
    _completion = completion;
    _tag = _random.nextInt(0x7ffffffe) + 1;
    _framesSubscription = connector.receivedFrames.listen(_handleFrame);

    try {
      final payload = buildDiscoveryRequestPayload(
        _tag!,
        prefixOnly: false,
        // The filter is one byte. Request every node type understood by the
        // responder, including future types that fit the current mask.
        typeMask: 0xFF,
      );
      await connector.sendFrame(
        buildSendControlDataFrame(payload),
        waitForGenericAck: true,
      );
      if (_cancelled) return;

      _responseTimer = Timer(responseWindow, () {
        if (!completion.isCompleted) completion.complete();
      });
      await completion.future;
      await _framesSubscription?.cancel();
      _framesSubscription = null;
      _responseTimer?.cancel();
      _responseTimer = null;
    } finally {
      await _framesSubscription?.cancel();
      _framesSubscription = null;
      _responseTimer?.cancel();
      _responseTimer = null;
      _completion = null;
      _tag = null;
    }
  }

  void cancel() {
    _cancelled = true;
    final completion = _completion;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
    final ownerCompletion = _ownerCompletion;
    if (ownerCompletion != null && !ownerCompletion.isCompleted) {
      ownerCompletion.complete(null);
    }
  }

  void _handleFrame(Uint8List frame) {
    // Companion firmware writes:
    // [PUSH_CODE_CONTROL_DATA][SNR*4][RSSI][path_len][control payload].
    if (_cancelled || frame.length < 4 + 6 + pubKeySize) return;
    if (frame[0] != pushCodeControlData) return;

    const payloadOffset = 4;
    final flags = frame[payloadOffset];
    if (((flags >> 4) & 0x0F) != controlSubtypeDiscoverResp) return;

    final responseTag =
        frame[payloadOffset + 2] |
        (frame[payloadOffset + 3] << 8) |
        (frame[payloadOffset + 4] << 16) |
        (frame[payloadOffset + 5] << 24);
    if (responseTag != _tag) return;

    final publicKeyOffset = payloadOffset + 6;
    final publicKey = Uint8List.fromList(
      frame.sublist(publicKeyOffset, publicKeyOffset + pubKeySize),
    );
    connector.recordZeroHopDiscoveredContact(
      publicKey: publicKey,
      type: flags & 0x0F,
    );
  }

  Future<String?> requestRepeaterName(Uint8List publicKey) async {
    if (_cancelled ||
        !connector.isConnected ||
        publicKey.length != pubKeySize) {
      return null;
    }
    await Future<void>.delayed(ownerRequestThrottle);
    if (_cancelled || !connector.isConnected) return null;

    final name = await _requestOwnerName(publicKey);
    if (name == null || name.isEmpty) return null;
    connector.recordZeroHopDiscoveredContact(
      publicKey: publicKey,
      type: advTypeRepeater,
      name: name,
    );
    return name;
  }

  Future<String?> _requestOwnerName(Uint8List publicKey) async {
    StreamSubscription<Uint8List>? subscription;
    Timer? timeout;
    final completion = Completer<String?>();
    _ownerCompletion = completion;
    int? expectedTag;
    var awaitingSentResponse = true;

    void complete(String? name) {
      if (completion.isCompleted) return;
      timeout?.cancel();
      completion.complete(name);
    }

    void restartTimeout(Duration duration) {
      timeout?.cancel();
      timeout = Timer(duration, () => complete(null));
    }

    subscription = connector.receivedFrames.listen((frame) {
      if (_cancelled || frame.isEmpty || completion.isCompleted) return;

      if (frame[0] == respCodeErr) {
        if (awaitingSentResponse && expectedTag == null) complete(null);
        return;
      }

      if (frame[0] == respCodeSent) {
        if (!awaitingSentResponse || expectedTag != null || frame.length < 10) {
          return;
        }
        awaitingSentResponse = false;
        if (frame[1] != 0) {
          complete(null);
          return;
        }
        expectedTag = readUint32LE(frame, 2);
        final estimatedTimeoutMs = readUint32LE(frame, 6);
        restartTimeout(
          estimatedTimeoutMs > 0
              ? Duration(milliseconds: estimatedTimeoutMs) +
                    ownerRequestTimeoutPadding
              : ownerRequestFallbackTimeout,
        );
        return;
      }

      if (frame[0] != pushCodeBinaryResponse ||
          expectedTag == null ||
          frame.length < 10 ||
          readUint32LE(frame, 2) != expectedTag) {
        return;
      }

      // The companion strips the echoed request tag. The remaining owner
      // response starts with the repeater clock, followed by "name\nowner".
      var text = utf8.decode(frame.sublist(10), allowMalformed: true);
      final nulIndex = text.indexOf('\u0000');
      if (nulIndex >= 0) text = text.substring(0, nulIndex);
      final newlineIndex = text.indexOf('\n');
      complete(
        (newlineIndex >= 0 ? text.substring(0, newlineIndex) : text).trim(),
      );
    });

    restartTimeout(ownerRequestFallbackTimeout);
    try {
      await connector.sendFrame(
        buildSendAnonReqFrame(
          publicKey,
          requestType: anonReqTypeOwner,
        ),
      );
      return await completion.future;
    } catch (_) {
      complete(null);
      return await completion.future;
    } finally {
      timeout?.cancel();
      await subscription.cancel();
      if (identical(_ownerCompletion, completion)) {
        _ownerCompletion = null;
      }
    }
  }
}
