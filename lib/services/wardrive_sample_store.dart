import 'dart:convert';

import '../storage/prefs_manager.dart';

class WardriveSample {
  final DateTime timestamp;
  final DateTime? phoneLocationAt;
  final double latitude;
  final double longitude;
  final int tag;
  final int nodeType;
  final String publicKeyHex;
  final int snr;
  final int rssi;
  final int? responseTimeMs;

  const WardriveSample({
    required this.timestamp,
    required this.phoneLocationAt,
    required this.latitude,
    required this.longitude,
    required this.tag,
    required this.nodeType,
    required this.publicKeyHex,
    required this.snr,
    required this.rssi,
    required this.responseTimeMs,
  });

  Map<String, Object?> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'phoneLocationAt': phoneLocationAt?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'tag': tag,
      'nodeType': nodeType,
      'publicKeyHex': publicKeyHex,
      'snr': snr,
      'rssi': rssi,
      'responseTimeMs': responseTimeMs,
    };
  }

  static WardriveSample? fromJson(Map<String, Object?> json) {
    final timestamp = DateTime.tryParse(json['timestamp']?.toString() ?? '');
    final latitude = (json['latitude'] as num?)?.toDouble();
    final longitude = (json['longitude'] as num?)?.toDouble();
    final publicKeyHex = json['publicKeyHex']?.toString();
    if (timestamp == null ||
        latitude == null ||
        longitude == null ||
        publicKeyHex == null ||
        publicKeyHex.isEmpty) {
      return null;
    }

    final phoneLocationAtText = json['phoneLocationAt']?.toString();
    return WardriveSample(
      timestamp: timestamp,
      phoneLocationAt: phoneLocationAtText == null
          ? null
          : DateTime.tryParse(phoneLocationAtText),
      latitude: latitude,
      longitude: longitude,
      tag: (json['tag'] as num?)?.toInt() ?? 0,
      nodeType: (json['nodeType'] as num?)?.toInt() ?? 0,
      publicKeyHex: publicKeyHex,
      snr: (json['snr'] as num?)?.toInt() ?? 0,
      rssi: (json['rssi'] as num?)?.toInt() ?? 0,
      responseTimeMs: (json['responseTimeMs'] as num?)?.toInt(),
    );
  }
}

class WardriveSampleStore {
  static const _samplesKey = 'wardrive_samples_v1';
  static const _maxSamples = 1000;

  Future<void> add(WardriveSample sample) async {
    final prefs = PrefsManager.instance;
    final samples = prefs.getStringList(_samplesKey) ?? const <String>[];
    final nextSamples = <String>[
      jsonEncode(sample.toJson()),
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

  int get count {
    return PrefsManager.instance.getStringList(_samplesKey)?.length ?? 0;
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
}
