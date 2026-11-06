import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/contact_merge_helper.dart';
import 'package:meshcore_open/helpers/contact_telemetry_location.dart';
import 'package:meshcore_open/models/contact.dart';

final _advert = DateTime.utc(2026, 1, 1);
final _fixAt = DateTime.utc(2026, 1, 2);

Contact _contact({DateTime? advertAt, DateTime? fixAt}) => Contact(
  publicKey: Uint8List.fromList(List<int>.filled(32, 7)),
  name: 'Synthetic GPS contact',
  type: 1,
  pathLength: -1,
  path: Uint8List(0),
  latitude: fixAt == null ? 10 : 20,
  longitude: fixAt == null ? 30 : 40,
  lastSeen: advertAt ?? _advert,
  telemetryFixAt: fixAt,
);

void main() {
  test('GPS selection skips malformed, missing and non-finite fixes', () {
    final entries = <Map<String, dynamic>>[
      {},
      {'values': 'not a map'},
      {'values': {'gps': null}},
      {'values': {'gps': {'latitude': '1', 'longitude': 2}}},
      {'values': {'gps': {'latitude': double.nan, 'longitude': 2}}},
      {'values': {'gps': {'latitude': 1, 'longitude': double.infinity}}},
      {'values': {'gps': {'latitude': 91, 'longitude': 2}}},
      {'values': {'gps': {'latitude': 1, 'longitude': -181}}},
      {'values': {'gps': {'latitude': 0, 'longitude': 0}}},
    ];
    expect(telemetryGpsFix(entries), isNull);
    entries.add({'values': {'gps': {'latitude': 0, 'longitude': 2}}});
    expect(telemetryGpsFix(entries), (latitude: 0.0, longitude: 2.0));
    entries.add({'values': {'gps': {'latitude': 3, 'longitude': 4}}});
    expect(telemetryGpsFix(entries), (latitude: 0.0, longitude: 2.0));
    expect(validTelemetryLocation(-90, 180), isTrue);
    expect(validTelemetryLocation(90, -180), isTrue);
    expect(validTelemetryLocation(2, 0), isTrue);
  });

  test('a refreshed copy of the same advert keeps the GPS fix and clocks', () {
    final previous = _contact(fixAt: _fixAt);
    final incoming = _contact();
    final result = retainContactTelemetryFix(previous, incoming);
    expect(result.latitude, 20);
    expect(result.longitude, 40);
    expect(result.telemetryFixAt, _fixAt);
    expect(result.lastHeard, _fixAt);
    expect(result.lastSeen, _advert);
    expect(result.lastMessageAt, incoming.lastMessageAt);
    expect(result.lastModified, incoming.lastModified);
  });

  test('a newer advert wins even when the phone GPS clock is far ahead', () {
    final previous = _contact(fixAt: DateTime.utc(2036));
    final incoming = _contact(advertAt: _advert.add(const Duration(seconds: 1)));
    expect(retainContactTelemetryFix(previous, incoming), same(incoming));
    expect(incoming.telemetryFixAt, isNull);
    expect(incoming.lastHeard, incoming.lastSeen);
  });

  test('invalid or foreign contact data cannot donate telemetry freshness', () {
    final incoming = _contact();
    final invalid = _contact(fixAt: _fixAt).copyWith(latitude: 0, longitude: 0);
    final foreign = _contact(fixAt: _fixAt).copyWith(
      publicKey: Uint8List.fromList(List<int>.filled(32, 8)),
    );
    expect(retainContactTelemetryFix(invalid, incoming), same(incoming));
    expect(retainContactTelemetryFix(foreign, incoming), same(incoming));
  });

  test('deduplication keeps the latest eligible fix in either input order', () {
    final earlier = _contact(fixAt: _fixAt);
    final laterAt = _fixAt.add(const Duration(seconds: 1));
    final later = _contact(fixAt: laterAt).copyWith(latitude: -1, longitude: -2);
    for (final records in [[earlier, later], [later, earlier]]) {
      final merged = deduplicateContactsByPublicKey(records).single;
      expect(merged.telemetryFixAt, laterAt);
      expect(merged.latitude, -1);
      expect(merged.longitude, -2);
      expect(merged.lastSeen, _advert);
    }
    final newAdvert = _contact(advertAt: _advert.add(const Duration(seconds: 1)));
    for (final records in [[later, newAdvert], [newAdvert, later]]) {
      expect(deduplicateContactsByPublicKey(records).single.telemetryFixAt, isNull);
    }
  });

  test('lastHeard never moves before the advert; copyWith can clear the fix', () {
    final original = _contact(fixAt: _advert.subtract(const Duration(days: 1)));
    expect(original.lastHeard, _advert);
    expect(original.copyWith(name: 'Renamed').telemetryFixAt, original.telemetryFixAt);
    final cleared = original.copyWith(clearTelemetryFix: true);
    expect(cleared.telemetryFixAt, isNull);
    expect(cleared.latitude, original.latitude);
    expect(cleared.lastSeen, original.lastSeen);
  });
}
