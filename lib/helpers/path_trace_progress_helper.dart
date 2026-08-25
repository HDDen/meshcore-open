import 'package:flutter/foundation.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

/// One TRACE retransmission heard directly by the companion's radio.
///
/// [routeSnr] was measured by [relayHash] when it received the packet from
/// [previousHopHash]. [localSnr] and [localRssi] describe a separate link: how
/// the companion heard the retransmission made by [relayHash].
class PathTraceObservation {
  final int stageNumber;
  final int totalStages;
  final int outboundStages;
  final Uint8List relayHash;
  final Uint8List? previousHopHash;
  final List<double> accumulatedRouteSnr;
  final double routeSnr;
  final double localSnr;
  final int localRssi;
  final Duration elapsed;
  final Duration? sincePreviousObservation;

  const PathTraceObservation({
    required this.stageNumber,
    required this.totalStages,
    required this.outboundStages,
    required this.relayHash,
    required this.previousHopHash,
    required this.accumulatedRouteSnr,
    required this.routeSnr,
    required this.localSnr,
    required this.localRssi,
    required this.elapsed,
    required this.sincePreviousObservation,
  });

  bool get isReturnPath => stageNumber > outboundStages;
}

/// Matches raw RX-log frames to one active TRACE request and extracts the
/// progress already accumulated in the TRACE packet.
class PathTraceProgressTracker {
  static const int _routeMask = 0x03;
  static const int _routeDirect = 0x02;
  static const int _routeTransportDirect = 0x03;
  static const int _traceHeaderLength = 9;

  final Uint8List expectedTag;
  final Uint8List route;
  final int hashWidth;
  final int outboundStages;
  final DateTime startedAt;

  Duration? _lastObservationElapsed;

  PathTraceProgressTracker({
    required Uint8List expectedTag,
    required Uint8List route,
    required this.hashWidth,
    required this.outboundStages,
    required this.startedAt,
  }) : expectedTag = Uint8List.fromList(expectedTag),
       route = Uint8List.fromList(route);

  int get totalStages => hashWidth <= 0 ? 0 : route.length ~/ hashWidth;

  PathTraceObservation? parse(Uint8List frame, {DateTime? observedAt}) {
    try {
      if (hashWidth <= 0 || hashWidth > 4 || totalStages == 0) return null;
      final reader = BufferReader(frame);
      if (reader.readByte() != pushCodeLogRxData || reader.remaining < 4) {
        return null;
      }

      final localSnr = reader.readInt8() / 4.0;
      final localRssi = reader.readInt8();
      final packetHeader = reader.readByte();
      final routeType = packetHeader & _routeMask;
      final payloadType = (packetHeader >> 2) & 0x0F;
      if ((routeType != _routeDirect && routeType != _routeTransportDirect) ||
          payloadType != payloadTypeTRACE) {
        return null;
      }
      if (routeType == _routeTransportDirect) {
        reader.skipBytes(4);
      }

      final pathLengthByte = reader.readByte();
      final pathEntryWidth = ((pathLengthByte >> 6) & 0x03) + 1;
      // TRACE always stores one signed SNR byte per completed stage in path.
      if (pathEntryWidth != 1) return null;
      final completedStages = pathLengthByte & 0x3F;
      if (completedStages == 0 || completedStages > totalStages) return null;
      final accumulatedSnr = reader.readBytes(completedStages);

      if (reader.remaining < _traceHeaderLength) return null;
      final tag = reader.readBytes(4);
      if (!listEquals(tag, expectedTag)) return null;
      reader.skipBytes(4); // auth
      final flags = reader.readByte();
      if ((1 << (flags & 0x03)) != hashWidth) return null;
      if (reader.remaining != route.length) return null;
      final packetRoute = reader.readRemainingBytes();
      if (!listEquals(packetRoute, route)) return null;

      final routeOffset = (completedStages - 1) * hashWidth;
      final relayHash = route.sublist(routeOffset, routeOffset + hashWidth);
      final previousHopHash = completedStages > 1
          ? route.sublist(routeOffset - hashWidth, routeOffset)
          : null;
      final now = observedAt ?? DateTime.now();
      final elapsed = now.difference(startedAt);
      final previousElapsed = _lastObservationElapsed;
      _lastObservationElapsed = elapsed;
      final observationGap = previousElapsed == null
          ? null
          : elapsed - previousElapsed;

      return PathTraceObservation(
        stageNumber: completedStages,
        totalStages: totalStages,
        outboundStages: outboundStages.clamp(1, totalStages).toInt(),
        relayHash: Uint8List.fromList(relayHash),
        previousHopHash: previousHopHash == null
            ? null
            : Uint8List.fromList(previousHopHash),
        accumulatedRouteSnr: List<double>.unmodifiable(
          accumulatedSnr.map((value) => value.toSigned(8) / 4.0),
        ),
        routeSnr: accumulatedSnr.last.toSigned(8) / 4.0,
        localSnr: localSnr,
        localRssi: localRssi,
        elapsed: elapsed.isNegative ? Duration.zero : elapsed,
        sincePreviousObservation: observationGap == null
            ? null
            : observationGap.isNegative
            ? Duration.zero
            : observationGap,
      );
    } on RangeError {
      return null;
    }
  }
}
