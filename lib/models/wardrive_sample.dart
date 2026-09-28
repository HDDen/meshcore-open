/// One wardrive measurement and one wardrive session, as the standalone
/// wardrive app and this client exchange them. Pure data: the store keeps
/// them, the map draws them, the upload service posts them.
class WardriveSample {
  final String id;
  final DateTime timestamp;
  final DateTime? phoneLocationAt;
  final double latitude;
  final double longitude;
  final int tag;
  final int nodeType;
  final String publicKeyHex;
  final String? path;
  final String geohash;
  final double? snr;
  final int? rssi;
  final bool? pingSuccess;
  final int? responseTimeMs;
  final String? ductingRisk;
  final String? source;

  const WardriveSample({
    required this.id,
    required this.timestamp,
    required this.phoneLocationAt,
    required this.latitude,
    required this.longitude,
    required this.tag,
    required this.nodeType,
    required this.publicKeyHex,
    required this.path,
    required this.geohash,
    required this.snr,
    required this.rssi,
    required this.pingSuccess,
    required this.responseTimeMs,
    required this.ductingRisk,
    required this.source,
  });

  Map<String, Object?> toJson() {
    // Match the original MeshCore Wardrive export sample shape so files can be
    // exchanged between the standalone wardrive app and this integrated view.
    return {
      'id': id,
      'lat': latitude,
      'lon': longitude,
      'timestamp': timestamp.toIso8601String(),
      'path': path,
      'geohash': geohash,
      'snr': snr,
      'rssi': rssi,
      'pingSuccess': pingSuccess,
      'responseTimeMs': responseTimeMs,
      'ductingRisk': ductingRisk,
      'source': source,
    };
  }

  Map<String, Object?> toStorageJson() {
    final json = toJson();
    json.addAll({
      'phoneLocationAt': phoneLocationAt?.toIso8601String(),
      'tag': tag,
      'nodeType': nodeType,
      'publicKeyHex': publicKeyHex,
    });
    return json;
  }

  static WardriveSample? fromJson(Map<String, Object?> json) {
    final timestamp = DateTime.tryParse(json['timestamp']?.toString() ?? '');
    final latitude =
        (json['lat'] as num?)?.toDouble() ??
        (json['latitude'] as num?)?.toDouble();
    final longitude =
        (json['lon'] as num?)?.toDouble() ??
        (json['longitude'] as num?)?.toDouble();
    final path = json['path']?.toString();
    final publicKeyHex = json['publicKeyHex']?.toString() ?? path ?? '';
    if (timestamp == null || latitude == null || longitude == null) {
      return null;
    }

    final phoneLocationAtText = json['phoneLocationAt']?.toString();
    final geohash =
        json['geohash']?.toString() ?? _geohash(latitude, longitude);
    final tag = (json['tag'] as num?)?.toInt() ?? 0;
    final id =
        json['id']?.toString() ??
        _sampleId(timestamp: timestamp, tag: tag, geohash: geohash);
    final hasPingSuccess = json.containsKey('pingSuccess');
    final isLegacyOpenSample =
        json.containsKey('latitude') || json.containsKey('publicKeyHex');
    bool? pingSuccess;
    if (hasPingSuccess) {
      pingSuccess = json['pingSuccess'] as bool?;
    } else if (isLegacyOpenSample) {
      pingSuccess = true;
    }
    return WardriveSample(
      id: id,
      timestamp: timestamp,
      phoneLocationAt: phoneLocationAtText == null
          ? null
          : DateTime.tryParse(phoneLocationAtText),
      latitude: latitude,
      longitude: longitude,
      tag: tag,
      nodeType: (json['nodeType'] as num?)?.toInt() ?? 0,
      publicKeyHex: publicKeyHex,
      path: path ?? (publicKeyHex.isEmpty ? null : publicKeyHex),
      geohash: geohash,
      snr: (json['snr'] as num?)?.toDouble(),
      rssi: (json['rssi'] as num?)?.toInt(),
      pingSuccess: pingSuccess,
      responseTimeMs: (json['responseTimeMs'] as num?)?.toInt(),
      ductingRisk: json['ductingRisk']?.toString(),
      source: json['source']?.toString(),
    );
  }

  static WardriveSample fromDiscovery({
    required DateTime timestamp,
    required DateTime? phoneLocationAt,
    required double latitude,
    required double longitude,
    required int tag,
    required int nodeType,
    required String publicKeyHex,
    required double snr,
    required int rssi,
    required int? responseTimeMs,
  }) {
    final geohash = _geohash(latitude, longitude);
    return WardriveSample(
      id: _sampleId(timestamp: timestamp, tag: tag, geohash: geohash),
      timestamp: timestamp,
      phoneLocationAt: phoneLocationAt,
      latitude: latitude,
      longitude: longitude,
      tag: tag,
      nodeType: nodeType,
      publicKeyHex: publicKeyHex,
      path: publicKeyHex.toUpperCase(),
      geohash: geohash,
      snr: snr,
      rssi: rssi,
      pingSuccess: true,
      responseTimeMs: responseTimeMs,
      ductingRisk: null,
      source: null,
    );
  }

  static WardriveSample fromDiscoveryFailure({
    required DateTime timestamp,
    required DateTime? phoneLocationAt,
    required double latitude,
    required double longitude,
    required int tag,
  }) {
    final geohash = _geohash(latitude, longitude);
    return WardriveSample(
      id: _sampleId(timestamp: timestamp, tag: tag, geohash: geohash),
      timestamp: timestamp,
      phoneLocationAt: phoneLocationAt,
      latitude: latitude,
      longitude: longitude,
      tag: tag,
      nodeType: 0,
      publicKeyHex: '',
      path: null,
      geohash: geohash,
      snr: null,
      rssi: null,
      pingSuccess: false,
      responseTimeMs: null,
      ductingRisk: null,
      source: null,
    );
  }

  static String _sampleId({
    required DateTime timestamp,
    required int tag,
    required String geohash,
  }) {
    return '${timestamp.millisecondsSinceEpoch}_${tag.toRadixString(16).padLeft(8, '0')}_$geohash';
  }

  static String _geohash(double latitude, double longitude) {
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    var latMin = -90.0;
    var latMax = 90.0;
    var lonMin = -180.0;
    var lonMax = 180.0;
    var evenBit = true;
    var bit = 0;
    var ch = 0;
    final hash = StringBuffer();

    while (hash.length < 8) {
      if (evenBit) {
        final mid = (lonMin + lonMax) / 2;
        if (longitude >= mid) {
          ch = (ch << 1) + 1;
          lonMin = mid;
        } else {
          ch <<= 1;
          lonMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (latitude >= mid) {
          ch = (ch << 1) + 1;
          latMin = mid;
        } else {
          ch <<= 1;
          latMax = mid;
        }
      }
      evenBit = !evenBit;

      if (++bit == 5) {
        hash.write(base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return hash.toString();
  }
}

class WardriveSession {
  final DateTime startTime;
  final DateTime? endTime;
  final double distanceMeters;
  final int sampleCount;
  final int pingCount;
  final int successCount;
  final String? notes;

  const WardriveSession({
    required this.startTime,
    required this.endTime,
    required this.distanceMeters,
    required this.sampleCount,
    required this.pingCount,
    required this.successCount,
    required this.notes,
  });

  Map<String, Object?> toJson() {
    return {
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'distanceMeters': distanceMeters,
      'sampleCount': sampleCount,
      'pingCount': pingCount,
      'successCount': successCount,
      'notes': notes,
    };
  }

  static WardriveSession? fromJson(Map<String, Object?> json) {
    final startTime = DateTime.tryParse(json['startTime']?.toString() ?? '');
    if (startTime == null) return null;

    final endTimeText = json['endTime']?.toString();
    return WardriveSession(
      startTime: startTime,
      endTime: endTimeText == null ? null : DateTime.tryParse(endTimeText),
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0.0,
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
      pingCount: (json['pingCount'] as num?)?.toInt() ?? 0,
      successCount: (json['successCount'] as num?)?.toInt() ?? 0,
      notes: json['notes']?.toString(),
    );
  }
}
