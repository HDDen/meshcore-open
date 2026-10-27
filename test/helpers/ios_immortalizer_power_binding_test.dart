import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ios_immortalizer_power_binding.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/ios_immortalizer_power_options.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';

class _Settings extends ChangeNotifier implements AppSettingsService {
  @override
  AppSettings settings = AppSettings();

  void select(PowerSavingProfile profile, [IosImmortalizerPowerOptions? options]) {
    final previous = settings.powerSaving;
    settings = settings.copyWith(powerSaving: previous.copyWith(profile: profile,
      custom: previous.custom.copyWith(iosImmortalizer: options)));
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final messenger = TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  const channel = MethodChannel('mco_test/ios_immortalizer_power');
  const original = IosImmortalizerPowerOptions();
  const custom = IosImmortalizerPowerOptions(pauseUiFrames: true,
    audioBufferMilliseconds: 100, loopSeconds: 4);
  late _Settings settings;
  late List<MethodCall> calls;
  late List<bool> framePauses;
  late List<Object> errors;
  IosImmortalizerPowerBinding? binding;
  Future<void> drain() => Future<void>.delayed(Duration.zero);
  void start() {
    binding = IosImmortalizerPowerBinding(settings: settings, channel: channel,
      applyFramePause: framePauses.add, onError: errors.add);
  }

  setUp(() {
    settings = _Settings();
    calls = [];
    errors = [];
    framePauses = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() async {
    binding?.dispose();
    binding = null;
    await drain();
    messenger.setMockMethodCallHandler(channel, null);
    settings.dispose();
  });

  test('original options add no native call; profiles release and retain custom', () async {
    start();
    await drain();
    expect(calls, isEmpty);
    settings.select(PowerSavingProfile.custom, custom);
    settings.select(PowerSavingProfile.custom);
    await drain();
    expect(calls.single.method, 'configurePower');
    expect(calls.single.arguments, custom.toNativeArguments());
    settings.select(PowerSavingProfile.maximum);
    await drain();
    expect(calls.last.arguments, original.toNativeArguments());
    settings.select(PowerSavingProfile.disabled);
    settings.select(PowerSavingProfile.custom);
    await drain();
    expect(calls.length, 3);
    expect(calls.last.arguments, custom.toNativeArguments());
    expect(framePauses, [true, false, true]);
    expect(settings.settings.powerSaving.custom.iosImmortalizer, custom);
    binding!.dispose();
    binding!.dispose();
    await drain();
    expect(calls.length, 4);
    expect(calls.last.arguments, original.toNativeArguments());
    expect(framePauses.last, isFalse);
    settings.select(PowerSavingProfile.custom, custom.copyWith(loopSeconds: 9));
    await drain();
    expect(calls.length, 4);
    expect(errors, isEmpty);
  });

  test('a current native failure permits retry and a stale failure cannot roll back newer values', () async {
    final oldReply = Completer<Object?>();
    var attempt = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      attempt++;
      if (attempt == 1) {
        return oldReply.future;
      }
      if (attempt == 2) {
        throw PlatformException(code: 'unavailable');
      }
      return null;
    });
    start();
    settings.select(PowerSavingProfile.custom, custom);
    await drain();
    settings.select(PowerSavingProfile.custom, custom.copyWith(loopSeconds: 7));
    await drain();
    expect(errors.length, 1);
    settings.select(PowerSavingProfile.custom);
    await drain();
    expect(calls.length, 3);
    oldReply.completeError(PlatformException(code: 'old'));
    await drain();
    expect(errors.length, 1);
    settings.select(PowerSavingProfile.custom);
    await drain();
    expect(calls.length, 3);
    expect((calls.last.arguments as Map)['loopSeconds'], 7);
  });
}
