import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/ble_power_options.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';

void main() {
  test('old JSON and invalid modes retain the exact original policy', () {
    for (final raw in [null, '', 'future', true, 1, <String, Object>{}]) {
      final options = PowerSavingOptions.fromJson({
        'ble_connection_priority': raw, 'ble_peripheral_latency': raw,
      });
      expect(options.bleConnectionPriority, BleConnectionPriorityMode.original);
      expect(options.blePeripheralLatency, BlePeripheralLatencyMode.original);
      expect(options.toJson().containsKey('ble_connection_priority'), isFalse);
      expect(options.toJson().containsKey('ble_peripheral_latency'), isFalse);
    }
  });

  test('every pair round trips and unrelated settings survive copyWith', () {
    for (final priority in BleConnectionPriorityMode.values) {
      for (final latency in BlePeripheralLatencyMode.values) {
        final options = const PowerSavingOptions(gpsIntervalSeconds: 180)
            .copyWith(bleConnectionPriority: priority, blePeripheralLatency: latency);
        final restored = PowerSavingOptions.fromJson(jsonDecode(jsonEncode(options.toJson())));
        expect(restored.bleConnectionPriority, priority);
        expect(restored.blePeripheralLatency, latency);
        expect(restored.gpsIntervalSeconds, 180);
        expect(restored.copyWith(pauseHiddenGifs: true).bleConnectionPriority, priority);
      }
    }
  });

  test('presets select Android priority and preserve custom and iOS latency', () {
    const custom = PowerSavingOptions(
      bleConnectionPriority: BleConnectionPriorityMode.high,
      blePeripheralLatency: BlePeripheralLatencyMode.high,
    );
    for (final profile in PowerSavingProfile.values) {
      final settings = PowerSavingSettings(profile: profile, custom: custom);
      expect(settings.effective.bleConnectionPriority,
          switch (profile) {
            PowerSavingProfile.economical => BleConnectionPriorityMode.balanced,
            PowerSavingProfile.maximum => BleConnectionPriorityMode.lowPower,
            PowerSavingProfile.custom => custom.bleConnectionPriority,
            _ => BleConnectionPriorityMode.original,
          });
      expect(settings.effective.blePeripheralLatency,
          profile == PowerSavingProfile.custom ? custom.blePeripheralLatency
              : BlePeripheralLatencyMode.original);
      final restored = PowerSavingSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())));
      expect(restored.copyWith(profile: PowerSavingProfile.custom).effective.toJson(),
          custom.toJson());
    }
  });
}
