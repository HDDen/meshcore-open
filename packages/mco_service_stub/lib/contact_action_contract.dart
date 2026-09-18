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
class McoContactLocationCandidate {
  const McoContactLocationCandidate({
    required this.publicKey,
    required this.name,
    required this.contactType,
    required this.pathBytes,
    required this.lastSeen,
    this.pathHashByteWidth,
    this.latitude,
    this.longitude,
  });

  final List<int> publicKey;
  final String name;
  final int contactType;
  final List<int> pathBytes;
  final DateTime lastSeen;
  final int? pathHashByteWidth;
  final double? latitude;
  final double? longitude;

  bool get hasRealLocation {
    const epsilon = 1e-6;
    final lat = latitude ?? 0.0;
    final lon = longitude ?? 0.0;
    return (lat.abs() > epsilon || lon.abs() > epsilon) &&
        lat >= -90.0 &&
        lat <= 90.0 &&
        lon >= -180.0 &&
        lon <= 180.0;
  }
}

@immutable
class McoEstimatedContactLocation {
  const McoEstimatedContactLocation({
    required this.publicKeyHex,
    required this.name,
    required this.contactType,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
    required this.anchorPublicKeys,
    required this.anchorLatitudes,
    required this.anchorLongitudes,
    required this.highConfidence,
  });

  final String publicKeyHex;
  final String name;
  final int contactType;
  final double latitude;
  final double longitude;
  final DateTime updatedAt;
  final List<List<int>> anchorPublicKeys;
  final List<double> anchorLatitudes;
  final List<double> anchorLongitudes;
  final bool highConfidence;

  /// An estimate for a repeater nobody has named: [publicKeyHex] holds the hop
  /// prefix it left in message routes, at most the four bytes of the widest
  /// path hash, and [name] the same prefix as hop lists print it.
  bool get isPrefixOnly => publicKeyHex.length <= 8;

  Map<String, Object?> toJson() => {
    'publicKeyHex': publicKeyHex,
    'name': name,
    'contactType': contactType,
    'latitude': latitude,
    'longitude': longitude,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'anchorPublicKeys': anchorPublicKeys,
    'anchorLatitudes': anchorLatitudes,
    'anchorLongitudes': anchorLongitudes,
    'highConfidence': highConfidence,
  };

  static McoEstimatedContactLocation? fromJson(Object? value) {
    if (value is! Map) return null;
    final publicKeyHex = value['publicKeyHex'];
    final name = value['name'];
    final contactType = value['contactType'];
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    final updatedAt = value['updatedAt'];
    final anchorPublicKeys = value['anchorPublicKeys'];
    final anchorLatitudes = value['anchorLatitudes'];
    final anchorLongitudes = value['anchorLongitudes'];
    final highConfidence = value['highConfidence'];
    if (publicKeyHex is! String ||
        name is! String ||
        contactType is! int ||
        latitude is! num ||
        longitude is! num ||
        updatedAt is! int ||
        anchorPublicKeys is! List ||
        anchorLatitudes is! List ||
        anchorLongitudes is! List ||
        highConfidence is! bool) {
      return null;
    }
    final parsedKeys = <List<int>>[];
    for (final item in anchorPublicKeys) {
      if (item is! List) return null;
      final bytes = <int>[];
      for (final byte in item) {
        if (byte is! int || byte < 0 || byte > 255) return null;
        bytes.add(byte);
      }
      parsedKeys.add(List<int>.unmodifiable(bytes));
    }
    final parsedLats = <double>[];
    for (final item in anchorLatitudes) {
      if (item is! num) return null;
      parsedLats.add(item.toDouble());
    }
    final parsedLons = <double>[];
    for (final item in anchorLongitudes) {
      if (item is! num) return null;
      parsedLons.add(item.toDouble());
    }
    if (parsedKeys.length != parsedLats.length ||
        parsedKeys.length != parsedLons.length) {
      return null;
    }
    return McoEstimatedContactLocation(
      publicKeyHex: publicKeyHex.toLowerCase(),
      name: name,
      contactType: contactType,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
      anchorPublicKeys: List<List<int>>.unmodifiable(parsedKeys),
      anchorLatitudes: List<double>.unmodifiable(parsedLats),
      anchorLongitudes: List<double>.unmodifiable(parsedLons),
      highConfidence: highConfidence,
    );
  }
}

@immutable
class McoContactActionEstimate {
  const McoContactActionEstimate({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.anchorPublicKeys,
    required this.anchorLatitudes,
    required this.anchorLongitudes,
  });

  final String label;
  final double latitude;
  final double longitude;
  final List<List<int>> anchorPublicKeys;
  final List<double> anchorLatitudes;
  final List<double> anchorLongitudes;
}

typedef McoContactActionLoader =
    Future<List<McoContactActionMessage>> Function({
      bool Function()? isCancelled,
    });
typedef McoContactActionNodeLoader = List<McoContactActionNode> Function();
typedef McoContactActionTraceOpener =
    Future<void> Function(List<int> pathBytes, int hashByteWidth);
typedef McoContactActionEstimateOpener =
    Future<void> Function(McoContactActionEstimate estimate);
