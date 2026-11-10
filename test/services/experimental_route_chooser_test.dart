import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/path_history.dart';
import 'package:meshcore_open/services/experimental_route_chooser.dart';

final _now = DateTime.utc(2026, 11, 10);

PathRecord _route(
  int hop, {
  int successes = 5,
  int failures = 1,
  DateTime? timestamp,
  RouteEvidence? evidence,
}) => PathRecord(
  hopCount: 1,
  tripTimeMs: 1000,
  timestamp: timestamp ?? _now,
  wasFloodDiscovery: false,
  pathBytes: [hop],
  successCount: successes,
  failureCount: failures,
  adaptiveEvidence: evidence,
);

void main() {
  test('U34: legacy counts seed at most five outcomes and fade in a day', () {
    final route = _route(
      1,
      successes: 100,
      failures: 8,
      timestamp: _now.subtract(const Duration(days: 1)),
    );
    expect(route.toJson().containsKey('stats_at'), isFalse);
    expect(fadedRouteEvidence(route, _now), (success: 2.5, failure: 2.5));
    expect(addRouteEvidence(route, success: false, now: _now),
        (success: 2.5, failure: 3.5, at: _now));
  });

  test('U34: evidence stays bounded and invalid fields fall back to history', () {
    final route = _route(
      1,
      evidence: (success: 15, failure: 1, at: _now),
    );
    final updated = addRouteEvidence(route, success: false, now: _now);
    expect(updated.success + updated.failure, closeTo(16, 1e-12));
    final restored = PathRecord.fromJson(route.toJson());
    expect(restored.adaptiveEvidence, route.adaptiveEvidence);
    final invalid = PathRecord.fromJson({
      ...route.toJson(),
      'recent_success': 'invalid',
    });
    expect(invalid.adaptiveEvidence, isNull);
    expect(invalid.successCount, route.successCount);
  });

  test('U34: hearing uses the whole first hop and expires per radio', () {
    final hearing = ExperimentalRouteHearing()..bindRadio('node-a');
    hearing.observe('a1b2', [0xa1, 0xb2], _now);
    hearing.observe('direct-contact', [0x11, 0x22, 0x33], _now);
    final context = hearing.contextFor('direct-contact', now: _now);
    expect(context.contactHeardDirectly, isTrue);
    expect(context.firstHopHeard!([0xa1, 0xb2, 0x44, 0x55], 2), isTrue);
    expect(context.firstHopHeard!([0xa1, 0x77], 2), isFalse);
    expect(context.firstHopHeard!([0xa1, 0xb2, 0x77], 3), isFalse);

    hearing.bindRadio('node-b');
    final switched = hearing.contextFor('direct-contact', now: _now);
    expect(switched.contactHeardDirectly, isFalse);
    expect(switched.firstHopHeard, isNull);

    hearing.observe('a1b2', [0xa1, 0xb2], _now);
    final expired = hearing.contextFor(
      'direct-contact',
      now: _now.add(const Duration(hours: 2, seconds: 1)),
    );
    expect(expired.firstHopHeard, isNull);
  });

  test('U34: recent hearing and retry diversity shift seeded choices', () {
    final routes = [_route(1), _route(2)];
    int selectionsOfSecond(RouteContext context, bool triedFirst) {
      final random = math.Random(34);
      var second = 0;
      for (var i = 0; i < 256; i++) {
        final picked = pickExperimentalRoute(
          routes,
          random: random,
          now: _now,
          context: context,
          tried: (route) => triedFirst && identical(route, routes.first),
        );
        if (identical(picked, routes.last)) second++;
      }
      return second;
    }

    final neutral = selectionsOfSecond(const RouteContext(), false);
    expect(neutral, inInclusiveRange(60, 196));
    expect(
      selectionsOfSecond(
        RouteContext(firstHopHeard: (path, _) => path.first == 2),
        false,
      ),
      greaterThan(neutral),
    );
    expect(selectionsOfSecond(const RouteContext(), true), greaterThan(neutral));
  });
}
