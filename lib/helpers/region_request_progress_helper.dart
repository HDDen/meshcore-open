import 'package:flutter/foundation.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

class RegionRequestProgress {
  final int completedHops;
  final int totalHops;
  final int outboundCompletedHops;
  final int inboundCompletedHops;
  final int hopCount;

  const RegionRequestProgress({
    required this.completedHops,
    required this.totalHops,
    required this.outboundCompletedHops,
    required this.inboundCompletedHops,
    required this.hopCount,
  });

  double get fraction => totalHops == 0
      ? 0.0
      : (completedHops / totalHops).clamp(0.0, 1.0).toDouble();

  int get outboundTotalHops => hopCount + 1;
  int get inboundTotalHops => hopCount;
  int get outboundTraversedHops => completedHops
      .clamp(0, outboundTotalHops)
      .toInt();
  int get inboundTraversedHops => (completedHops - outboundTotalHops)
      .clamp(0, inboundTotalHops)
      .toInt();
}

/// Tracks a routed region request using raw radio echoes. Missing echoes only
/// leave progress at its last confirmed stage and never affect the request.
class RegionRequestProgressTracker {
  final Uint8List targetPublicKey;
  final Uint8List senderPublicKey;
  final Uint8List outboundPath;
  final Uint8List inboundPath;
  final int pathHashWidth;

  Uint8List? _outboundPayload;
  Uint8List? _inboundPayload;
  var _outboundCompletedHops = 0;
  var _inboundCompletedHops = 0;
  var _responseDetected = false;
  var _completed = false;

  RegionRequestProgressTracker({
    required Uint8List targetPublicKey,
    required Uint8List senderPublicKey,
    required Uint8List outboundPath,
    required this.pathHashWidth,
  }) : targetPublicKey = Uint8List.fromList(targetPublicKey),
       senderPublicKey = Uint8List.fromList(senderPublicKey),
       outboundPath = Uint8List.fromList(outboundPath),
       inboundPath = _reversePath(outboundPath, pathHashWidth);

  int get hopCount => outboundPath.length ~/ pathHashWidth;
  RegionRequestProgress get progress => _snapshot();

  RegionRequestProgress markCompleted() {
    _outboundCompletedHops = hopCount;
    _responseDetected = true;
    _inboundCompletedHops = hopCount;
    _completed = true;
    return _snapshot();
  }

  RegionRequestProgress? observe(Uint8List frame) {
    final echo = _RegionRequestEcho.tryParse(frame);
    if (echo == null || echo.pathHashWidth != pathHashWidth) return null;

    if (echo.payloadType == payloadTypeANONREQ) {
      final completedHops = _matchingOutboundHops(echo);
      if (completedHops == null ||
          completedHops <= _outboundCompletedHops) {
        return null;
      }
      _outboundPayload ??= Uint8List.fromList(echo.payload);
      _outboundCompletedHops = completedHops;
      return _snapshot();
    }

    if (echo.payloadType == payloadTypeRESPONSE) {
      final completedHops = _matchingInboundHops(echo);
      if (completedHops == null) return null;
      final changed = !_responseDetected ||
          completedHops > _inboundCompletedHops;
      if (!changed) return null;

      _inboundPayload ??= Uint8List.fromList(echo.payload);
      _outboundCompletedHops = hopCount;
      _responseDetected = true;
      _inboundCompletedHops = completedHops;
      return _snapshot();
    }

    return null;
  }

  int? _matchingOutboundHops(_RegionRequestEcho echo) {
    if (echo.payload.length < 1 + pubKeySize ||
        echo.payload[0] != targetPublicKey[0] ||
        !listEquals(
          echo.payload.sublist(1, 1 + pubKeySize),
          senderPublicKey,
        ) ||
        (_outboundPayload != null &&
            !listEquals(_outboundPayload, echo.payload))) {
      return null;
    }
    return _matchingCompletedHops(echo, outboundPath);
  }

  int? _matchingInboundHops(_RegionRequestEcho echo) {
    if (echo.payload.length < 2 ||
        echo.payload[0] != senderPublicKey[0] ||
        echo.payload[1] != targetPublicKey[0] ||
        (_inboundPayload != null &&
            !listEquals(_inboundPayload, echo.payload))) {
      return null;
    }
    return _matchingCompletedHops(echo, inboundPath);
  }

  int? _matchingCompletedHops(
    _RegionRequestEcho echo,
    Uint8List expectedPath,
  ) {
    if (echo.remainingHopCount > hopCount) return null;
    final completedHops = hopCount - echo.remainingHopCount;
    final suffixOffset = completedHops * pathHashWidth;
    if (!listEquals(expectedPath.sublist(suffixOffset), echo.remainingPath)) {
      return null;
    }
    return completedHops;
  }

  RegionRequestProgress _snapshot() {
    // Match path tracing: intermediates lead to the target, then the return
    // path mirrors them without adding the local companion as another stage.
    final totalHops = hopCount * 2 + 1;
    final completedHops = _completed
        ? totalHops
        : _responseDetected
        ? hopCount + 1 + _inboundCompletedHops
        : _outboundCompletedHops;
    return RegionRequestProgress(
      completedHops: completedHops,
      totalHops: totalHops,
      outboundCompletedHops: _outboundCompletedHops,
      inboundCompletedHops: _inboundCompletedHops,
      hopCount: hopCount,
    );
  }
}

class _RegionRequestEcho {
  final int payloadType;
  final int pathHashWidth;
  final int remainingHopCount;
  final Uint8List remainingPath;
  final Uint8List payload;

  const _RegionRequestEcho({
    required this.payloadType,
    required this.pathHashWidth,
    required this.remainingHopCount,
    required this.remainingPath,
    required this.payload,
  });

  static _RegionRequestEcho? tryParse(Uint8List frame) {
    try {
      final reader = BufferReader(frame);
      if (reader.readByte() != pushCodeLogRxData || reader.remaining < 4) {
        return null;
      }
      reader.skipBytes(2); // Local SNR and RSSI.

      final header = reader.readByte();
      final routeType = header & 0x03;
      final payloadType = (header >> 2) & 0x0F;
      if ((routeType != 0x02 && routeType != 0x03) ||
          (payloadType != payloadTypeANONREQ &&
              payloadType != payloadTypeRESPONSE)) {
        return null;
      }
      if (routeType == 0x03) {
        if (reader.remaining < 4) return null;
        reader.skipBytes(4);
      }

      final encodedPathLength = reader.readByte();
      final pathHashWidth = ((encodedPathLength >> 6) & 0x03) + 1;
      final remainingHopCount = encodedPathLength & 0x3F;
      final remainingPathLength = remainingHopCount * pathHashWidth;
      if (reader.remaining < remainingPathLength + 2) return null;

      return _RegionRequestEcho(
        payloadType: payloadType,
        pathHashWidth: pathHashWidth,
        remainingHopCount: remainingHopCount,
        remainingPath: Uint8List.fromList(
          reader.readBytes(remainingPathLength),
        ),
        payload: Uint8List.fromList(reader.readRemainingBytes()),
      );
    } on RangeError {
      return null;
    }
  }
}

Uint8List _reversePath(Uint8List path, int hashWidth) {
  if (path.isEmpty || hashWidth <= 0 || path.length % hashWidth != 0) {
    return Uint8List.fromList(path.reversed.toList());
  }
  final reversed = Uint8List(path.length);
  final hops = path.length ~/ hashWidth;
  for (var index = 0; index < hops; index++) {
    final sourceOffset = (hops - index - 1) * hashWidth;
    reversed.setRange(
      index * hashWidth,
      (index + 1) * hashWidth,
      path,
      sourceOffset,
    );
  }
  return reversed;
}
