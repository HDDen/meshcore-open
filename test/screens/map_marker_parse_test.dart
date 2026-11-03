import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/marker_message.dart';

void main() {
  test('parseMarkerText accepts in-range coordinates', () {
    final payload = parseMarkerText('m:45.5,-122.6|Camp|x');
    expect(payload, isNotNull);
    expect(payload!.position.latitude, 45.5);
    expect(payload.position.longitude, -122.6);
    expect(payload.label, 'Camp');
  });

  test('parseMarkerText rejects out-of-range coordinates', () {
    expect(parseMarkerText('m:999,999|x|'), isNull);
    expect(parseMarkerText('m:90.1,0|x|'), isNull);
    expect(parseMarkerText('m:0,-180.5|x|'), isNull);
    expect(parseMarkerText('m:-90,180|edge|'), isNotNull);
  });

  // U06c1 will move this parser into a helper shared with notifications.
  // Freeze the existing grammar before changing its import location.
  test('U06c1 baseline: marker fields preserve trimming and empty labels', () {
    final payload = parseMarkerText('  m:0,-180|  Точка  |  poi  ');
    expect(payload, isNotNull);
    expect(payload!.position.latitude, 0);
    expect(payload.position.longitude, -180);
    expect(payload.label, 'Точка');
    expect(payload.flags, 'poi');
    final unnamed = parseMarkerText('m:-90,180||');
    expect(unnamed, isNotNull);
    expect(unnamed!.label, isEmpty);
    expect(unnamed.flags, isEmpty);
  });

  test('U06c1 baseline: marker parsing permits the existing sender prefix', () {
    final payload = parseMarkerText('Alice: m:45.5,-122.6|Camp|poi');
    expect(payload, isNotNull);
    expect(payload!.label, 'Camp');
    expect(payload.position.latitude, 45.5);
    expect(payload.position.longitude, -122.6);
  });

  test('U06c1 baseline: malformed marker text is not a location', () {
    for (final text in [
      'see you at m:ain street',
      'm:45.5,-122.6|missing-flags',
      'm:--1,0|bad latitude|',
      'm:0,1.2.3|bad longitude|',
      'm:91,0|out of range|',
    ]) {
      expect(parseMarkerText(text), isNull, reason: text);
    }
  });
}
