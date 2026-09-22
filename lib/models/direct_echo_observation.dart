import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One raw copy of a direct message meant for us, heard while the packet was
/// still on its way: the route it had left to travel, in travel order (the
/// next repeater first, the one nearest to us last), and how our radio heard
/// that transmission.
class DirectEchoObservation {
  final Uint8List remainingPath;
  final int pathHashWidth;
  final double? snr;
  final int? rssi;

  DirectEchoObservation({
    required Uint8List remainingPath,
    required int pathHashWidth,
    this.snr,
    this.rssi,
  }) : remainingPath = Uint8List.fromList(remainingPath),
       pathHashWidth = pathHashWidth.clamp(1, 4).toInt();

  int get remainingHopCount => remainingPath.length ~/ pathHashWidth;

  /// The same route read from our end: the hop nearest to us first, the hop
  /// the packet was heard from last. That is the shape a manual route to the
  /// sender takes, so it can be pasted into the path editor as the known tail
  /// of a reply's route — partial, since the route before the heard hop was
  /// already stripped by the time we heard it.
  Uint8List get invertedPath {
    final hops = <List<int>>[];
    for (var i = 0; i + pathHashWidth <= remainingPath.length;
        i += pathHashWidth) {
      hops.add(remainingPath.sublist(i, i + pathHashWidth));
    }
    return Uint8List.fromList([for (final hop in hops.reversed) ...hop]);
  }

  bool hasSamePath(DirectEchoObservation other) =>
      pathHashWidth == other.pathHashWidth &&
      listEquals(remainingPath, other.remainingPath);

  Map<String, Object?> toJson() => {
    'path': base64Encode(remainingPath),
    'width': pathHashWidth,
    'snr': snr,
    'rssi': rssi,
  };

  static DirectEchoObservation? fromJson(Object? json) {
    if (json is! Map) return null;
    final path = json['path'];
    if (path is! String) return null;
    try {
      return DirectEchoObservation(
        remainingPath: base64Decode(path),
        pathHashWidth: (json['width'] as num?)?.toInt() ?? 1,
        snr: (json['snr'] as num?)?.toDouble(),
        rssi: (json['rssi'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, Object?>> encodeList(
    List<DirectEchoObservation> observations,
  ) => [for (final observation in observations) observation.toJson()];

  static List<DirectEchoObservation> decodeList(Object? json) {
    if (json is! List) return const [];
    return [for (final entry in json) ?fromJson(entry)];
  }
}
