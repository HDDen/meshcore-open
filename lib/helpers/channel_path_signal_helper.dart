import 'dart:convert';
import 'dart:typed_data';

class ChannelPathObservation {
  /// Signal measured by this app's node when this exact route was received.
  /// The reading belongs to the final hop encoded in [pathBytes].
  final Uint8List pathBytes;
  final double? snr;
  final int? rssi;

  const ChannelPathObservation({
    required this.pathBytes,
    this.snr,
    this.rssi,
  });
}

abstract final class ChannelPathSignalHelper {
  static List<ChannelPathObservation> includeReading({
    List<ChannelPathObservation>? observations,
    required Uint8List pathBytes,
    required double? snr,
    required int? rssi,
  }) {
    final merged = List<ChannelPathObservation>.of(
      observations ?? const <ChannelPathObservation>[],
    );
    if (snr == null && rssi == null) return merged;

    for (var i = 0; i < merged.length; i++) {
      final current = merged[i];
      if (!_pathsEqual(current.pathBytes, pathBytes)) continue;
      merged[i] = ChannelPathObservation(
        pathBytes: current.pathBytes,
        snr: current.snr ?? snr,
        rssi: current.rssi ?? rssi,
      );
      return merged;
    }

    merged.add(
      ChannelPathObservation(pathBytes: pathBytes, snr: snr, rssi: rssi),
    );
    return merged;
  }

  static List<ChannelPathObservation> merge(
    List<ChannelPathObservation> existing,
    List<ChannelPathObservation> incoming,
  ) {
    var merged = List<ChannelPathObservation>.of(existing);
    for (final observation in incoming) {
      merged = includeReading(
        observations: merged,
        pathBytes: observation.pathBytes,
        snr: observation.snr,
        rssi: observation.rssi,
      );
    }
    return merged;
  }

  static ChannelPathObservation? find(
    List<ChannelPathObservation> observations,
    Uint8List pathBytes,
  ) {
    for (final observation in observations) {
      if (_pathsEqual(observation.pathBytes, pathBytes)) return observation;
    }
    return null;
  }

  static List<Map<String, Object?>> encode(
    List<ChannelPathObservation> observations,
  ) {
    return [
      for (final observation in observations)
        {
          'pathBytes': base64Encode(observation.pathBytes),
          'snr': observation.snr,
          'rssi': observation.rssi,
        },
    ];
  }

  static List<ChannelPathObservation>? decode(Object? value) {
    if (value is! List<dynamic>) return null;
    return [
      for (final entry in value)
        if (entry is Map<String, dynamic>)
          ChannelPathObservation(
            pathBytes: Uint8List.fromList(
              base64Decode(entry['pathBytes'] as String),
            ),
            snr: (entry['snr'] as num?)?.toDouble(),
            rssi: entry['rssi'] as int?,
          ),
    ];
  }

  static bool _pathsEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
