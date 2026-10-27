import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ble_peripheral_power_binding.dart';
import 'package:meshcore_open/models/ble_power_options.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  test('profile and restart retain custom modes; disposal removes the listener', () async {
    final settings = AppSettingsService();
    final values = <String>[];
    final binding = BlePeripheralPowerBinding(settings: settings, apply: values.add);
    try {
      expect(values, ['original']);
      await settings.setBlePeripheralLatencyMode(BlePeripheralLatencyMode.high);
      await settings.setBleConnectionPriorityMode(BleConnectionPriorityMode.lowPower);
      expect(values, ['original']); // Off сохраняет свои значения без применения.
      await settings.setPowerSavingProfile(PowerSavingProfile.custom);
      expect(values, ['original', 'high']);
      await settings.setBleConnectionPriorityMode(BleConnectionPriorityMode.high);
      expect(values, ['original', 'high']);
      await settings.setPowerSavingProfile(PowerSavingProfile.maximum);
      await settings.setPowerSavingProfile(PowerSavingProfile.custom);
      expect(values, ['original', 'high', 'original', 'high']);
      final reloaded = AppSettingsService();
      await reloaded.loadSettings();
      expect(reloaded.settings.powerSaving.custom.blePeripheralLatency,
          BlePeripheralLatencyMode.high);
      expect(reloaded.settings.powerSaving.custom.bleConnectionPriority,
          BleConnectionPriorityMode.high);
      final coldValues = <String>[];
      final coldBinding = BlePeripheralPowerBinding(
        settings: reloaded, apply: coldValues.add,
      );
      expect(coldValues, ['high']);
      coldBinding.dispose();
      reloaded.dispose();
    } finally {
      binding.dispose();
    }
    final before = values.length;
    await settings.setBlePeripheralLatencyMode(BlePeripheralLatencyMode.low);
    expect(values, hasLength(before));
    settings.dispose();
  });
}
