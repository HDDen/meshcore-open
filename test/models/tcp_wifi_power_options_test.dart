import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';

void main() {
  test('old and malformed JSON preserve original Wi-Fi holding', () {
    expect(const PowerSavingOptions().releaseTcpWifiLock, isFalse);
    expect(const PowerSavingOptions().toJson(), isNot(contains('release_tcp_wifi_lock')));
    for (final raw in [null, false, 0, 1, 'true', <String, Object>{}]) {
      final options = PowerSavingOptions.fromJson({'release_tcp_wifi_lock': raw});
      expect(options.releaseTcpWifiLock, isFalse);
      expect(options.toJson(), const PowerSavingOptions().toJson());
    }
    for (final raw in [null, <String, Object>{}, false, 'invalid']) {
      expect(PowerSavingOptions.fromJson(raw).releaseTcpWifiLock, isFalse);
    }
  });

  test('the option round trips and copyWith retains independent settings', () {
    const original = PowerSavingOptions(
      backgroundReconnectIntervalSeconds: 180,
      batteryIntervalSeconds: 300,
      pauseHiddenGifs: true,
    );
    final changed = original.copyWith(releaseTcpWifiLock: true);
    expect(changed.toJson(), {...original.toJson(), 'release_tcp_wifi_lock': true});
    final restored = PowerSavingOptions.fromJson(jsonDecode(jsonEncode(changed.toJson())));
    expect(restored.releaseTcpWifiLock, isTrue);
    expect(restored.toJson(), changed.toJson());
    expect(changed.copyWith(gpsIntervalSeconds: 180).releaseTcpWifiLock, isTrue);
    expect(changed.copyWith(releaseTcpWifiLock: false).toJson(), original.toJson());
  });

  test('all presets retain original holding without erasing custom', () {
    for (final profile in PowerSavingProfile.values) {
      final settings = PowerSavingSettings(
        profile: profile,
        custom: const PowerSavingOptions(releaseTcpWifiLock: true),
      );
      final restored = PowerSavingSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())));
      expect(restored.custom.releaseTcpWifiLock, isTrue);
      expect(restored.effective.releaseTcpWifiLock, profile == PowerSavingProfile.custom);
    }
    final unknown = PowerSavingSettings.fromJson({
      'profile': 'future',
      'custom': {'release_tcp_wifi_lock': true},
    });
    expect(unknown.effective.releaseTcpWifiLock, isFalse);
    expect(unknown.custom.releaseTcpWifiLock, isTrue);
  });
}
