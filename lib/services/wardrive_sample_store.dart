import 'dart:convert';

import '../storage/prefs_manager.dart';

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
  final int? snr;
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
      snr: (json['snr'] as num?)?.toInt(),
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
    required int snr,
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

class WardriveSampleStore {
  static const _samplesKey = 'wardrive_samples_v1';
  static const _sessionsKey = 'wardrive_sessions_v1';
  static const _exportFormat = 'meshcore_wardrive_data';
  static const _maxSamples = 1000;
  static const _maxSessions = 200;

  Future<void> add(WardriveSample sample) async {
    final prefs = PrefsManager.instance;
    final samples = prefs.getStringList(_samplesKey) ?? const <String>[];
    final nextSamples = <String>[
      jsonEncode(sample.toStorageJson()),
      ...samples.take(_maxSamples - 1),
    ];

    // Keep storage bounded for the first porting step; a larger wardrive
    // database can replace this helper without touching protocol parsing.
    await prefs.setStringList(_samplesKey, nextSamples);
  }

  List<WardriveSample> loadRecent({int limit = 100}) {
    final samples = PrefsManager.instance.getStringList(_samplesKey) ?? [];
    return samples
        .take(limit)
        .map(_decodeSample)
        .whereType<WardriveSample>()
        .toList();
  }

  List<WardriveSample> loadAllSamples() {
    return loadRecent(limit: _maxSamples);
  }

  String exportJson({WardriveSession? activeSession}) {
    final sessions = loadSessions();
    if (activeSession != null &&
        !sessions.any(
          (session) => session.startTime == activeSession.startTime,
        )) {
      sessions.insert(0, activeSession);
    }

    return const JsonEncoder.withIndent('  ').convert({
      '_format': _exportFormat,
      '_version': 1,
      'samples': loadRecent(
        limit: _maxSamples,
      ).map((sample) => sample.toJson()).toList(),
      'sessions': sessions.map((session) => session.toJson()).toList(),
    });
  }

  Future<int> importJson(String rawJson) async {
    final importedSamples = _decodeImport(rawJson);
    await _importSessions(rawJson: rawJson);
    if (importedSamples.isEmpty) return 0;

    final prefs = PrefsManager.instance;
    final existingSamples = loadRecent(limit: _maxSamples);
    final knownKeys = existingSamples.map(_sampleKey).toSet();
    final merged = <WardriveSample>[];
    var added = 0;

    for (final sample in importedSamples) {
      if (knownKeys.add(_sampleKey(sample))) {
        merged.add(sample);
        added++;
      }
    }
    merged.addAll(existingSamples);

    await prefs.setStringList(
      _samplesKey,
      merged
          .take(_maxSamples)
          .map((sample) => jsonEncode(sample.toStorageJson()))
          .toList(),
    );
    return added;
  }

  Future<void> clear() async {
    await PrefsManager.instance.remove(_samplesKey);
    await PrefsManager.instance.remove(_sessionsKey);
  }

  int get count {
    return PrefsManager.instance.getStringList(_samplesKey)?.length ?? 0;
  }

  Future<void> addSession(WardriveSession session) async {
    final prefs = PrefsManager.instance;
    final sessions = prefs.getStringList(_sessionsKey) ?? const <String>[];
    final nextSessions = <String>[
      jsonEncode(session.toJson()),
      ...sessions.take(_maxSessions - 1),
    ];
    await prefs.setStringList(_sessionsKey, nextSessions);
  }

  List<WardriveSession> loadSessions() {
    final sessions = PrefsManager.instance.getStringList(_sessionsKey) ?? [];
    return sessions.map(_decodeSession).whereType<WardriveSession>().toList();
  }

  List<WardriveSample> _decodeImport(String rawJson) {
    final decoded = jsonDecode(rawJson);
    final rawSamples = decoded is Map
        ? decoded['samples']
        : decoded is List
        ? decoded
        : null;
    if (rawSamples == null && decoded is Map && decoded['sessions'] is List) {
      return const <WardriveSample>[];
    }
    if (rawSamples is! List) {
      throw const FormatException('Wardrive samples JSON is invalid');
    }

    return rawSamples
        .whereType<Map>()
        .map(
          (entry) => WardriveSample.fromJson(Map<String, Object?>.from(entry)),
        )
        .whereType<WardriveSample>()
        .toList();
  }

  Future<void> _importSessions({required String rawJson}) async {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map || decoded['sessions'] is! List) return;

    final incomingSessions = (decoded['sessions'] as List)
        .whereType<Map>()
        .map(
          (entry) => WardriveSession.fromJson(Map<String, Object?>.from(entry)),
        )
        .whereType<WardriveSession>()
        .toList();
    if (incomingSessions.isEmpty) return;

    final existingSessions = loadSessions();
    final knownStarts = existingSessions
        .map((session) => session.startTime.toIso8601String())
        .toSet();
    final merged = <WardriveSession>[];
    for (final session in incomingSessions) {
      if (knownStarts.add(session.startTime.toIso8601String())) {
        merged.add(session);
      }
    }
    merged.addAll(existingSessions);

    await PrefsManager.instance.setStringList(
      _sessionsKey,
      merged
          .take(_maxSessions)
          .map((session) => jsonEncode(session.toJson()))
          .toList(),
    );
  }

  String _sampleKey(WardriveSample sample) {
    return sample.id;
  }

  WardriveSample? _decodeSample(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return WardriveSample.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  WardriveSession? _decodeSession(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return WardriveSession.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}
