import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/ios_immortalizer_power_options.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';

void main() {
  const original = IosImmortalizerPowerOptions();
  const custom = IosImmortalizerPowerOptions(
    pauseUiFrames: true, leanHooks: true, withoutAudio: true,
    useOutputSampleRate: true, audioBufferMilliseconds: 200, loopSeconds: 10,
  );

  test('old and malformed preferences preserve original behavior', () {
    for (final raw in [null, false, 'true', 1, <String, Object>{}]) {
      expect(IosImmortalizerPowerOptions.fromJson(raw), original);
    }
    expect(IosImmortalizerPowerOptions.fromJson({
      'pause_ui_frames': 'true', 'lean_hooks': 1, 'without_audio': false,
      'audio_buffer_milliseconds': 100.0, 'loop_seconds': '10',
    }), original);
    expect(const PowerSavingOptions().toJson().containsKey('ios_immortalizer'), isFalse);
  });

  test('normalization is shared by JSON and copyWith; native units are milliseconds', () {
    for (final entry in {-1: 0, 0: 0, 9: 0, 10: 10, 99: 90, 200: 200, 201: 200}.entries) {
      expect(IosImmortalizerPowerOptions.fromJson({
        'audio_buffer_milliseconds': entry.key,
      }).audioBufferMilliseconds, entry.value);
      expect(original.copyWith(audioBufferMilliseconds: entry.key)
          .audioBufferMilliseconds, entry.value);
    }
    expect(original.copyWith(loopSeconds: 0).loopSeconds, 1);
    expect(original.copyWith(loopSeconds: 99).loopSeconds, 10);
    expect(IosImmortalizerPowerOptions.fromJson(custom.toJson()), custom);
    expect(custom.hashCode, IosImmortalizerPowerOptions.fromJson(custom.toJson()).hashCode);
    expect(custom.toNativeArguments(), {
      'schema': 1, 'pauseUiFrames': true, 'leanHooks': true,
      'withoutAudio': true, 'useOutputSampleRate': true,
      'audioBufferMilliseconds': 200, 'loopSeconds': 10,
    });
  });

  test('all presets stay original and retain custom settings across persistence', () {
    var settings = const PowerSavingSettings(profile: PowerSavingProfile.custom,
      custom: PowerSavingOptions(iosImmortalizer: custom, gpsIntervalSeconds: 180));
    for (final profile in PowerSavingProfile.values) {
      settings = PowerSavingSettings.fromJson(jsonDecode(jsonEncode(
        settings.copyWith(profile: profile).toJson(),
      )));
      expect(settings.custom.iosImmortalizer, custom);
      expect(settings.effective.iosImmortalizer,
          profile == PowerSavingProfile.custom ? custom : original);
      expect(settings.custom.gpsIntervalSeconds, 180);
    }
    final enabledAudio = custom.copyWith(withoutAudio: false);
    expect(enabledAudio.audioBufferMilliseconds, 200);
    expect(enabledAudio.loopSeconds, 10);
    expect(enabledAudio.useOutputSampleRate, isTrue);
  });
}
