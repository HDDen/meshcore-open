import 'package:flutter/foundation.dart';

import '../connector/meshcore_protocol.dart';
import 'path_trace_progress_helper.dart';

/// A completed result and the direct echoes already observed during that run.
/// Copies the frame because the connector's shared stream does not own the UI.
class SavedPathTraceResult {
  final Uint8List frame;
  final List<PathTraceObservation> observations;

  SavedPathTraceResult({
    required Uint8List frame,
    List<PathTraceObservation> observations = const [],
  }) : frame = Uint8List.fromList(frame),
       observations = List.unmodifiable(observations);

  /// Caching is stricter than the legacy display parser: a complete reply
  /// must describe the exact request. Never cache a partial or foreign route.
  static bool matchesRequest(
    Uint8List frame, {
    required Uint8List tag,
    required Uint8List route,
    required int hashWidth,
  }) {
    if (frame.length < 12 ||
        frame[0] != pushCodeTraceData ||
        tag.length != 4 ||
        !listEquals(frame.sublist(4, 8), tag) ||
        hashWidth < 1 ||
        hashWidth > 4 ||
        (1 << (frame[3] & 3)) != hashWidth) {
      return false;
    }
    var length = frame[2] == 0xFF ? 0 : frame[2];
    final remaining = frame.length - 12;
    if (length > remaining && (frame[2] & 0xC0) != 0) {
      final packedWidth = ((frame[2] & 0xC0) >> 6) + 1;
      if (packedWidth != hashWidth) return false;
      length = (frame[2] & 0x3F) * packedWidth;
    }
    if (route.isEmpty ||
        length != route.length ||
        length % hashWidth != 0 ||
        remaining < length + length ~/ hashWidth + 1) {
      return false;
    }
    return listEquals(frame.sublist(12, 12 + length), route);
  }
}
