import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/wardrive_sample_store.dart';

class WardriveCoverageSummary {
  final int total;
  final int good;
  final int fair;
  final int weak;
  final int dead;

  const WardriveCoverageSummary({
    required this.total,
    required this.good,
    required this.fair,
    required this.weak,
    required this.dead,
  });
}

class WardriveCoverageHelper {
  static List<Polygon> buildPolygons(List<WardriveSample> samples) {
    return _buildCells(samples)
        .map((cell) {
          final bounds = cell.bounds;
          if (bounds == null) return null;
          final color = _coverageColor(cell);
          return Polygon(
            // Wardrive coverage is drawn as geohash blocks, matching the
            // standalone app's coverage squares instead of point markers.
            points: [
              LatLng(bounds.south, bounds.west),
              LatLng(bounds.south, bounds.east),
              LatLng(bounds.north, bounds.east),
              LatLng(bounds.north, bounds.west),
            ],
            color: color.withValues(alpha: _coverageOpacity(cell)),
            borderColor: color.withValues(alpha: 0.95),
            borderStrokeWidth: cell.received == 0 && cell.lost > 0 ? 1.5 : 1,
          );
        })
        .whereType<Polygon>()
        .toList();
  }

  static WardriveCoverageSummary buildSummary(List<WardriveSample> samples) {
    final cells = _buildCells(samples);
    var good = 0;
    var fair = 0;
    var weak = 0;
    var dead = 0;
    for (final cell in cells) {
      if (cell.received == 0 && cell.lost > 0) {
        dead++;
      } else {
        final total = cell.received + cell.lost;
        if (total == 0) {
          weak++;
          continue;
        }
        final successRate = cell.received / total;
        if (successRate >= 0.66) {
          good++;
        } else if (successRate >= 0.33) {
          fair++;
        } else {
          weak++;
        }
      }
    }

    return WardriveCoverageSummary(
      total: cells.length,
      good: good,
      fair: fair,
      weak: weak,
      dead: dead,
    );
  }

  static List<_WardriveCoverageCell> _buildCells(List<WardriveSample> samples) {
    final groups = <String, List<WardriveSample>>{};
    for (final sample in samples) {
      // Match the standalone wardrive app: coverage cells are geohash blocks,
      // while individual samples keep their higher-precision geohash.
      final key = _coverageHash(sample);
      groups.putIfAbsent(key, () => <WardriveSample>[]).add(sample);
    }

    return groups.values
        .map((group) {
          final coverageHash = _coverageHash(group.first);
          final bounds = _decodeGeohashBounds(coverageHash);
          final stats = _buildStats(group);
          if (stats.received == 0 && stats.lost == 0) {
            return null;
          }
          return _WardriveCoverageCell(
            bounds: bounds,
            received: stats.received,
            lost: stats.lost,
          );
        })
        .whereType<_WardriveCoverageCell>()
        .toList();
  }

  static _WardriveCoverageStats _buildStats(List<WardriveSample> samples) {
    final sortedSamples = List<WardriveSample>.from(samples)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    var received = 0.0;
    var lost = 0.0;

    for (var i = 0; i < sortedSamples.length; i++) {
      final sample = sortedSamples[i];
      if (sample.pingSuccess == null) continue;

      var weight = 1.0;
      final ageInDays = DateTime.now().difference(sample.timestamp).inDays;
      if (ageInDays > 30) {
        weight = 0.2;
      } else if (ageInDays > 7) {
        weight = 0.5;
      } else if (ageInDays > 1) {
        weight = 0.8;
      }

      final newerSamples = sortedSamples.sublist(0, i > 10 ? 10 : i);
      if (newerSamples.isNotEmpty) {
        var contradictions = 0;
        var agreements = 0;
        for (final newer in newerSamples) {
          if (newer.pingSuccess == null) continue;
          if (newer.pingSuccess != sample.pingSuccess) {
            contradictions++;
          } else {
            agreements++;
          }
        }
        if (contradictions > agreements && contradictions >= 2) {
          weight *= 0.1;
        }
      }

      if (sample.pingSuccess == true) {
        received += weight;
      } else if (sample.pingSuccess == false) {
        lost += weight;
      }
    }

    return _WardriveCoverageStats(received: received, lost: lost);
  }

  static String _coverageHash(WardriveSample sample) {
    const precision = 7;
    if (sample.geohash.length >= precision) {
      return sample.geohash.substring(0, precision);
    }
    return _encodeGeohash(
      sample.latitude,
      sample.longitude,
      precision: precision,
    );
  }

  static String _encodeGeohash(
    double latitude,
    double longitude, {
    required int precision,
  }) {
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    var latMin = -90.0;
    var latMax = 90.0;
    var lonMin = -180.0;
    var lonMax = 180.0;
    var evenBit = true;
    var bit = 0;
    var ch = 0;
    final hash = StringBuffer();

    while (hash.length < precision) {
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

  static _WardriveGeohashBounds? _decodeGeohashBounds(String hash) {
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    var latMin = -90.0;
    var latMax = 90.0;
    var lonMin = -180.0;
    var lonMax = 180.0;
    var evenBit = true;

    for (final rune in hash.toLowerCase().runes) {
      final value = base32.indexOf(String.fromCharCode(rune));
      if (value < 0) return null;
      for (var mask = 16; mask != 0; mask >>= 1) {
        if (evenBit) {
          final mid = (lonMin + lonMax) / 2;
          if ((value & mask) != 0) {
            lonMin = mid;
          } else {
            lonMax = mid;
          }
        } else {
          final mid = (latMin + latMax) / 2;
          if ((value & mask) != 0) {
            latMin = mid;
          } else {
            latMax = mid;
          }
        }
        evenBit = !evenBit;
      }
    }

    return _WardriveGeohashBounds(
      south: latMin,
      west: lonMin,
      north: latMax,
      east: lonMax,
    );
  }

  static Color _coverageColor(_WardriveCoverageCell cell) {
    final total = cell.received + cell.lost;
    if (total == 0) return Colors.grey;
    final successRate = cell.received / total;
    return Color.lerp(
          const Color(0xFFD32F2F),
          const Color(0xFF00C853),
          successRate,
        ) ??
        const Color(0xFF00C853);
  }

  static double _coverageOpacity(_WardriveCoverageCell cell) {
    if (cell.received >= 20) return 0.7;
    if (cell.received >= 10) return 0.5;
    if (cell.received >= 5) return 0.4;
    return 0.3;
  }
}

class _WardriveCoverageCell {
  final _WardriveGeohashBounds? bounds;
  final double received;
  final double lost;

  const _WardriveCoverageCell({
    required this.bounds,
    required this.received,
    required this.lost,
  });
}

class _WardriveCoverageStats {
  final double received;
  final double lost;

  const _WardriveCoverageStats({required this.received, required this.lost});
}

class _WardriveGeohashBounds {
  final double south;
  final double west;
  final double north;
  final double east;

  const _WardriveGeohashBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });
}
