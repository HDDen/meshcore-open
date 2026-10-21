import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/telemetry_power.dart';

void main() {
  group('calculated telemetry power', () {
    test('keeps fractional watts and negative current without changing power', () {
      final values = <String, dynamic>{
        'voltage': 3.84,
        'current': -0.011,
        'power': 0,
      };
      expect(calculatedTelemetryPowerWatts(values), closeTo(-0.04224, 1e-10));
      expect(values, {'voltage': 3.84, 'current': -0.011, 'power': 0});
    });

    test('calculation is independent of the transmitted power', () {
      expect(
        calculatedTelemetryPowerWatts({'voltage': 3.84, 'current': 0.5}),
        closeTo(1.92, 1e-10),
      );
      expect(
        calculatedTelemetryPowerWatts({
          'voltage': 3.84,
          'current': 0.5,
          'power': 13,
        }),
        closeTo(1.92, 1e-10),
      );
    });

    test('zero current and integer readings remain valid', () {
      expect(calculatedTelemetryPowerWatts({'voltage': 4, 'current': 0}), 0);
      expect(calculatedTelemetryPowerWatts({'voltage': 4, 'current': 2}), 8);
    });

    test('requires two finite numbers from the same channel map', () {
      for (final values in <Map<String, dynamic>>[
        {},
        {'voltage': 3.84},
        {'current': -0.011},
        {'voltage': '3.84', 'current': -0.011},
        {'voltage': 3.84, 'current': null},
        {'voltage': double.nan, 'current': 1},
        {'voltage': 3.84, 'current': double.infinity},
        {'voltage': double.negativeInfinity, 'current': 1},
        {'voltage': 1e308, 'current': 1e308},
      ]) {
        expect(calculatedTelemetryPowerWatts(values), isNull);
      }
    });
  });
}
