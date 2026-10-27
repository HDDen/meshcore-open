import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/cpu_sleep_options.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';

void main() {
  test('always permits every scenario and foreground without erasing choices', () {
    const individual = CpuSleepOptions(ble: true, wardrive: true);
    final always = individual.copyWith(always: true);
    for (final scenarios in [<String>{}, {'ble', 'proxy'}, {'unknown'}, {'tcp'}]) {
      expect(always.permits(background: false, scenarios: scenarios), isTrue);
    }
    expect(always.copyWith(always: false).toJson(), individual.toJson());
  });

  test('individual choices require background and every active scenario', () {
    const options = CpuSleepOptions(ble: true, proxy: true);
    expect(options.permits(background: true, scenarios: {'ble', 'proxy'}), isTrue);
    for (final scenarios in [<String>{}, {'ble', 'tcp'}, {'unknown'}, {'wardrive'}]) {
      expect(options.permits(background: true, scenarios: scenarios), isFalse);
    }
    expect(options.permits(background: false, scenarios: {'ble'}), isFalse);
  });

  test('all scenario combinations require each selected permission', () {
    const names = ['ble', 'tcp', 'proxy', 'wardrive'];
    for (var allowed = 0; allowed < 16; allowed++) {
      final options = CpuSleepOptions(ble: (allowed & 1) != 0,
        tcp: (allowed & 2) != 0, proxy: (allowed & 4) != 0, wardrive: (allowed & 8) != 0);
      for (var active = 0; active < 16; active++) {
        final scenarios = {for (var i = 0; i < 4; i++) if ((active & (1 << i)) != 0) names[i]};
        expect(options.permits(background: true, scenarios: scenarios),
          active != 0 && (active & ~allowed) == 0);
      }
    }
  });

  test('legacy JSON and malformed flags default off without adding a default key', () {
    for (final value in [null, 1, 'yes', {}, {'always': 1, 'ble': 'true'}]) {
      expect(CpuSleepOptions.fromJson(value).enabled, isFalse);
    }
    expect(PowerSavingOptions.fromJson({}).cpuSleep.enabled, isFalse);
    expect(const PowerSavingOptions().toJson().containsKey('cpu_sleep'), isFalse);
  });

  test('preset CPU permissions and custom survive JSON and profile switching', () {
    const custom = PowerSavingOptions(cpuSleep: CpuSleepOptions(always: true,
      ble: true, tcp: true, proxy: false, wardrive: true));
    const expected = {
      PowerSavingProfile.disabled: CpuSleepOptions(),
      PowerSavingProfile.balanced: CpuSleepOptions(),
      PowerSavingProfile.economical: CpuSleepOptions(ble: true),
      PowerSavingProfile.maximum: CpuSleepOptions(always: true),
      PowerSavingProfile.custom: CpuSleepOptions(always: true,
        ble: true, tcp: true, wardrive: true),
    };
    for (final profile in PowerSavingProfile.values) {
      final restored = PowerSavingSettings.fromJson(
        PowerSavingSettings(profile: profile, custom: custom).toJson());
      expect(restored.custom.toJson(), custom.toJson());
      expect(restored.effective.cpuSleep.toJson(), expected[profile]!.toJson());
      expect(restored.copyWith(profile: PowerSavingProfile.custom).effective.cpuSleep.toJson(),
        custom.cpuSleep.toJson());
    }
  });

  test('unconditional overrides every scenario and preserves protected choices', () {
    const protected = CpuSleepOptions(always: true, ble: true, wardrive: true);
    final unrestricted = protected.copyWith(unconditional: true);
    expect(unrestricted.enabled, isTrue);
    for (final background in [false, true]) {
      for (final scenarios in [<String>{}, {'unknown'}, {'ble', 'tcp', 'proxy', 'wardrive'}]) {
        expect(unrestricted.permits(background: background, scenarios: scenarios), isTrue);
      }
    }
    expect(unrestricted.copyWith(unconditional: false).toJson(), protected.toJson());
    expect(const CpuSleepOptions(unconditional: true).enabled, isTrue);
  });

  test('unconditional is opt-in and custom persists separately from presets', () {
    for (final json in [{}, {'always': true}, {'unconditional': 'true'}, {'unconditional': 1}]) {
      expect(CpuSleepOptions.fromJson(json).unconditional, isFalse);
    }
    expect(const CpuSleepOptions().toJson().containsKey('unconditional'), isFalse);
    const custom = PowerSavingOptions(cpuSleep: CpuSleepOptions(
      unconditional: true, ble: true, proxy: true));
    for (final profile in PowerSavingProfile.values) {
      final restored = PowerSavingSettings.fromJson(
        PowerSavingSettings(profile: profile, custom: custom).toJson());
      expect(restored.custom.cpuSleep.toJson(), custom.cpuSleep.toJson());
      expect(restored.effective.cpuSleep.unconditional, profile == PowerSavingProfile.custom);
      final back = restored.copyWith(profile: PowerSavingProfile.custom).effective.cpuSleep;
      expect(back.unconditional && back.ble && back.proxy, isTrue);
    }
  });
}
