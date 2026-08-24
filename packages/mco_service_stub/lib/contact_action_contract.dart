import 'package:flutter/foundation.dart';

@immutable
class McoContactActionPath {
  const McoContactActionPath({
    required this.bytes,
    required this.hashByteWidth,
    this.snr,
    this.rssi,
  });

  final List<int> bytes;
  final int hashByteWidth;
  final double? snr;
  final int? rssi;
}

@immutable
class McoContactActionMessage {
  const McoContactActionMessage({
    required this.senderName,
    required this.receivedAt,
    required this.isOutgoing,
    required this.paths,
  });

  final String senderName;
  final DateTime receivedAt;
  final bool isOutgoing;
  final List<McoContactActionPath> paths;
}

@immutable
class McoContactActionNode {
  const McoContactActionNode({
    required this.publicKey,
    required this.latitude,
    required this.longitude,
    required this.lastSeen,
  });

  final List<int> publicKey;
  final double latitude;
  final double longitude;
  final DateTime lastSeen;
}

@immutable
class McoContactActionEstimate {
  const McoContactActionEstimate({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.anchorLatitudes,
    required this.anchorLongitudes,
  });

  final String label;
  final double latitude;
  final double longitude;
  final List<double> anchorLatitudes;
  final List<double> anchorLongitudes;
}

typedef McoContactActionLoader =
    Future<List<McoContactActionMessage>> Function();
typedef McoContactActionNodeLoader = List<McoContactActionNode> Function();
typedef McoContactActionTraceOpener =
    Future<void> Function(List<int> pathBytes, int hashByteWidth);
typedef McoContactActionEstimateOpener =
    Future<void> Function(McoContactActionEstimate estimate);
