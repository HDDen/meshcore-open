import 'dart:math' as math;

import '../models/path_history.dart';

const _evidenceHalfLife = Duration(hours: 24);
const _evidenceCap = 16.0;
const _heardWindow = Duration(hours: 2);
const _maxHeardNeighbours = 128;

class RouteContext {
  const RouteContext({
    this.contactHeardDirectly = false,
    this.firstHopHeard,
    this.radioPath,
  });

  final bool contactHeardDirectly;
  final bool Function(List<int> path, int width)? firstHopHeard;
  final List<int>? radioPath;
}

/// Passive observations from the active radio's adverts.
class ExperimentalRouteHearing {
  String? _radioKey;
  final _heard = <String, ({List<int> prefix, DateTime at})>{};

  void bindRadio(String key) {
    if (_radioKey == key) return;
    _radioKey = key;
    _heard.clear();
  }

  void observe(String identity, List<int> prefix, DateTime now) {
    // Reinsert so the oldest observation is first when the cache is full.
    _heard.remove(identity);
    _heard[identity] = (prefix: prefix, at: now);
    if (_heard.length > _maxHeardNeighbours) {
      _heard.remove(_heard.keys.first);
    }
  }

  RouteContext contextFor(
    String contactKey, {
    required DateTime now,
    List<int>? radioPath,
  }) {
    _heard.removeWhere((_, heard) => now.difference(heard.at) > _heardWindow);
    final prefixes = [for (final heard in _heard.values) heard.prefix];
    return RouteContext(
      contactHeardDirectly: _heard.containsKey(contactKey),
      firstHopHeard: prefixes.isEmpty
          ? null
          : (path, width) => prefixes.any(
              (prefix) => _prefixMatches(prefix, path, width),
            ),
      radioPath: radioPath,
    );
  }
}

({double success, double failure}) fadedRouteEvidence(
  PathRecord record,
  DateTime now,
) {
  final evidence = record.adaptiveEvidence;
  final since = evidence?.at ?? record.timestamp;
  final seconds = since == null ? 0 : now.difference(since).inSeconds;
  final fade = seconds <= 0
      ? 1.0
      : math.pow(0.5, seconds / _evidenceHalfLife.inSeconds).toDouble();
  // Existing histories seed the model with at most five of each outcome.
  return (
    success: (evidence?.success ?? record.successCount.clamp(0, 5).toDouble()) *
        fade,
    failure: (evidence?.failure ?? record.failureCount.clamp(0, 5).toDouble()) *
        fade,
  );
}

RouteEvidence addRouteEvidence(
  PathRecord? record, {
  required bool success,
  required DateTime now,
}) {
  final prior = record == null
      ? (success: 0.0, failure: 0.0)
      : fadedRouteEvidence(record, now);
  final successes = prior.success + (success ? 1 : 0);
  final failures = prior.failure + (success ? 0 : 1);
  final total = successes + failures;
  final scale = total > _evidenceCap ? _evidenceCap / total : 1.0;
  return (success: successes * scale, failure: failures * scale, at: now);
}

/// Sample delivery odds as upstream does, with soft penalties for an
/// unheard first hop or a route already tried for this message.
PathRecord pickExperimentalRoute(
  List<PathRecord> routes, {
  required math.Random random,
  required DateTime now,
  required RouteContext context,
  required bool Function(PathRecord) tried,
}) {
  assert(routes.isNotEmpty);
  int? fastest;
  for (final route in routes) {
    final trip = route.tripTimeMs;
    if (trip > 0 && (fastest == null || trip < fastest)) fastest = trip;
  }
  final candidates = routes.map((route) {
    final stats = fadedRouteEvidence(route, now);
    final speed = fastest == null || route.tripTimeMs <= 0
        ? 0.6
        : (fastest / route.tripTimeMs).clamp(0.0, 1.0);
    final weight = (0.85 + 0.15 * speed) * _contextFactor(route, context);
    final mean = (stats.success + 1) / (stats.success + stats.failure + 2);
    return (route: route, stats: stats, weight: weight, rank: mean * weight);
  }).toList()..sort((a, b) {
    final byRank = b.rank.compareTo(a.rank);
    if (byRank != 0) return byRank;
    final aTrip = a.route.tripTimeMs == 0 ? 999999 : a.route.tripTimeMs;
    final bTrip = b.route.tripTimeMs == 0 ? 999999 : b.route.tripTimeMs;
    if (aTrip != bTrip) return aTrip.compareTo(bTrip);
    final aTime = a.route.timestamp?.millisecondsSinceEpoch ?? 0;
    final bTime = b.route.timestamp?.millisecondsSinceEpoch ?? 0;
    return bTime.compareTo(aTime);
  });

  PathRecord? best;
  var bestScore = -1.0;
  for (final candidate in candidates) {
    final odds = _sampleBeta(
      random,
      candidate.stats.success + 1,
      candidate.stats.failure + 1,
    );
    final score =
        odds * candidate.weight * (tried(candidate.route) ? 0.5 : 1.0);
    if (score > bestScore) {
      bestScore = score;
      best = candidate.route;
    }
  }
  return best!;
}

double _contextFactor(PathRecord route, RouteContext context) {
  final path = route.pathBytes;
  final radioPath = context.radioPath;
  final radioBonus =
      radioPath != null &&
          radioPath.length == path.length &&
          _prefixMatches(radioPath, path, path.length)
      ? 1.05
      : 1.0;
  final firstHopHeard = context.firstHopHeard;
  if (firstHopHeard == null) return radioBonus;
  final fits = route.hopCount == 0
      ? context.contactHeardDirectly
      : firstHopHeard(path, path.length ~/ route.hopCount);
  return radioBonus * (fits ? 1.15 : 0.6);
}

bool _prefixMatches(List<int> a, List<int> b, int width) {
  if (a.length < width || b.length < width) return false;
  for (var i = 0; i < width; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

double _sampleBeta(math.Random random, double a, double b) {
  final x = _sampleGamma(random, a);
  final y = _sampleGamma(random, b);
  final total = x + y;
  return total <= 0 ? 0.5 : x / total;
}

// Marsaglia–Tsang gamma sampler. Beta parameters here are evidence plus one.
double _sampleGamma(math.Random random, double shape) {
  final d = shape - 1 / 3;
  final c = 1 / math.sqrt(9 * d);
  while (true) {
    double x;
    double v;
    do {
      final u1 = 1 - random.nextDouble();
      final u2 = random.nextDouble();
      x = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
      v = 1 + c * x;
    } while (v <= 0);
    v = v * v * v;
    final u = random.nextDouble();
    if (u < 1 - 0.0331 * x * x * x * x) return d * v;
    if (math.log(u) < 0.5 * x * x + d * (1 - v + math.log(v))) return d * v;
  }
}
