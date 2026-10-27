import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';

void main() {
  test('old settings and malformed values keep the legacy write path', () {
    final defaults = const PowerSavingOptions().toJson();
    expect(defaults, isNot(contains('reduce_delivery_observation_writes')));
    for (final value in [null, false, 0, 1, 'true', <String, Object>{}]) {
      final restored = PowerSavingOptions.fromJson({
        'reduce_delivery_observation_writes': value,
      });
      expect(restored.reduceDeliveryObservationWrites, isFalse);
      expect(restored.toJson(), defaults);
    }
  });

  test('round trip and copyWith retain independent settings', () {
    const original = PowerSavingOptions(
      releaseTcpWifiLock: true,
      batteryIntervalSeconds: 300,
    );
    final changed = original.copyWith(reduceDeliveryObservationWrites: true);
    expect(changed.toJson(), {
      ...original.toJson(), 'reduce_delivery_observation_writes': true,
    });
    expect(PowerSavingOptions.fromJson(jsonDecode(jsonEncode(changed.toJson()))).toJson(),
        changed.toJson());
    expect(changed.copyWith(reduceDeliveryObservationWrites: false).toJson(), original.toJson());
    expect(changed.copyWith(gpsIntervalSeconds: 180).reduceDeliveryObservationWrites, isTrue);
  });

  test('all ready profiles keep legacy writes without erasing custom', () {
    for (final profile in PowerSavingProfile.values) {
      final restored = PowerSavingSettings.fromJson(jsonDecode(jsonEncode(
        PowerSavingSettings(profile: profile,
          custom: const PowerSavingOptions(reduceDeliveryObservationWrites: true)).toJson(),
      )));
      expect(restored.custom.reduceDeliveryObservationWrites, isTrue);
      expect(restored.effective.reduceDeliveryObservationWrites,
          profile == PowerSavingProfile.custom);
    }
  });
}
