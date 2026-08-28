import 'package:flutter/foundation.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

class DirectMessageEcho {
  final int destinationHash;
  final int sourceHash;
  final int pathHashWidth;
  final int remainingHopCount;
  final Uint8List remainingPath;
  final Uint8List payload;

  const DirectMessageEcho({
    required this.destinationHash,
    required this.sourceHash,
    required this.pathHashWidth,
    required this.remainingHopCount,
    required this.remainingPath,
    required this.payload,
  });

  static DirectMessageEcho? tryParse(Uint8List frame) {
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
          payloadType != payloadTypeTXTMSG) {
        return null;
      }
      if (routeType == 0x03) {
        if (reader.remaining < 4) return null;
        reader.skipBytes(4);
      }

      final encodedPathLength = reader.readByte();
      final pathHashWidth = ((encodedPathLength >> 6) & 0x03) + 1;
      final remainingHopCount = encodedPathLength & 0x3F;
      final remainingPathBytes = remainingHopCount * pathHashWidth;
      if (reader.remaining < remainingPathBytes + 2) return null;

      final remainingPath = reader.readBytes(remainingPathBytes);
      final payload = reader.readRemainingBytes();
      return DirectMessageEcho(
        destinationHash: payload[0],
        sourceHash: payload[1],
        pathHashWidth: pathHashWidth,
        remainingHopCount: remainingHopCount,
        remainingPath: Uint8List.fromList(remainingPath),
        payload: Uint8List.fromList(payload),
      );
    } on RangeError {
      return null;
    }
  }
}

class DirectMessageProgressTracker {
  final String messageId;
  final int attemptIndex;
  final int destinationHash;
  final int sourceHash;
  final int pathHashWidth;
  final Uint8List route;
  final List<Uint8List> rejectedPayloads;

  Uint8List? _boundPayload;

  DirectMessageProgressTracker({
    required this.messageId,
    required this.attemptIndex,
    required this.destinationHash,
    required this.sourceHash,
    required this.pathHashWidth,
    required Uint8List route,
    List<Uint8List> rejectedPayloads = const [],
  }) : route = Uint8List.fromList(route),
       rejectedPayloads = rejectedPayloads
           .map((payload) => Uint8List.fromList(payload))
           .toList(growable: false);

  int get hopCount => route.length ~/ pathHashWidth;
  bool get isBound => _boundPayload != null;
  Uint8List? get boundPayload => _boundPayload == null
      ? null
      : Uint8List.fromList(_boundPayload!);

  int? matchingStage(DirectMessageEcho echo) {
    if (echo.destinationHash != destinationHash ||
        echo.sourceHash != sourceHash ||
        echo.pathHashWidth != pathHashWidth ||
        echo.remainingHopCount >= hopCount) {
      return null;
    }
    if (_boundPayload != null && !listEquals(_boundPayload, echo.payload)) {
      return null;
    }
    if (rejectedPayloads.any((payload) => listEquals(payload, echo.payload))) {
      return null;
    }

    final completedHops = hopCount - echo.remainingHopCount;
    final suffixOffset = completedHops * pathHashWidth;
    if (suffixOffset < 0 || suffixOffset > route.length) return null;
    if (!listEquals(route.sublist(suffixOffset), echo.remainingPath)) {
      return null;
    }
    return completedHops;
  }

  void bind(DirectMessageEcho echo) {
    _boundPayload ??= Uint8List.fromList(echo.payload);
  }
}
