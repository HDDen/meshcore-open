import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../utils/platform_info.dart';
import '../utils/app_logger.dart';
import 'ios_frame_diagnostics.dart';

final _iosAppPresentationActive = ValueNotifier<bool>(true);

/// Share the existing native activity signal without another channel watcher.
/// True on an unavailable bridge leaves Flutter lifecycle in control.
ValueListenable<bool> get iosAppPresentationActive => _iosAppPresentationActive;

/// Defer UI frames: keep the isolate, timers and transports alive.
/// Native notifications remain useful when a dylib reports a false app state.
mixin IosPresentationFrameGate on RendererBinding {
  bool _iosPresentationAllowed = true;
  final iosFrameDiagnostics = IosFrameDiagnostics();

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    iosFrameDiagnostics.beginFrame(warmUp: rawTimeStamp == null);
    super.handleBeginFrame(rawTimeStamp);
  }

  @override
  bool get sendFramesToEngine =>
      _iosPresentationAllowed && super.sendFramesToEngine;

  @override
  void drawFrame() {
    iosFrameDiagnostics.drawFrame(suppressed: !_iosPresentationAllowed);
    // sendFramesToEngine alone is checked after layout/paint. Skip the UI
    // pipeline before it prepares text while the native scene is inactive.
    // Dirty widgets/render objects remain queued for the normal resume frame.
    if (_iosPresentationAllowed) {
      super.drawFrame();
    }
  }

  void updateIosPresentation(bool allowed) {
    if (_iosPresentationAllowed == allowed) {
      return;
    }
    _iosPresentationAllowed = allowed;
    iosFrameDiagnostics.presentationChanged(allowed);
    appLogger.info(iosFrameDiagnostics.summary, tag: 'iOSFrameStats', noNotify: true);
    // Respect Flutter's own lifecycle/first-frame deferral. Its resume path
    // schedules the frame if it has not resumed when the native event arrives.
    if (allowed) {
      scheduleFrame();
    }
  }
}

String? currentIosFrameDiagnosticsSummary() {
  try {
    final binding = RendererBinding.instance;
    return binding is IosPresentationFrameGate ? binding.iosFrameDiagnostics.summary : null;
  } on FlutterError {
    return null;
  } on TypeError {
    return null;
  }
}

/// One ordered native subscription, with no Dart lifecycle notifications and
/// no retained dependency on an account, widget or connection.
class IosPresentationBridge {
  IosPresentationBridge({
    required this.onPresentationChanged,
    MethodChannel channel = platformChannel,
  }) : _channel = channel;

  static const platformChannel = MethodChannel('mco_advanced/ios_presentation');
  final void Function(bool allowed) onPresentationChanged;
  final MethodChannel _channel;
  int _revision = -1;
  int _epoch = 0;
  bool _started = false;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    _revision = -1;
    final epoch = ++_epoch;
    _channel.setMethodCallHandler((call) async {
      if (_started && epoch == _epoch && call.method == 'presentation') {
        _accept(call.arguments);
      }
    });
    try {
      final snapshot = await _channel.invokeMethod<Object?>('watch')
          .timeout(const Duration(seconds: 3));
      if (_started && epoch == _epoch) {
        // A successful null/malformed reply is also an unavailable bridge.
        // Keep a newer event if it arrived before the initial snapshot.
        if (!_accept(snapshot) && _revision < 0) {
          _unavailable(epoch);
        }
      }
    } on MissingPluginException {
      _unavailable(epoch);
    } on PlatformException {
      _unavailable(epoch);
    } on TimeoutException {
      _unavailable(epoch);
    }
  }

  bool _accept(Object? raw) {
    if (raw is! Map || raw['schema'] != 1 || raw['enabled'] is! bool ||
        raw['active'] is! bool || raw['revision'] is! int) {
      return false;
    }
    final revision = raw['revision'] as int;
    if (revision < 0 || revision <= _revision) {
      return false;
    }
    _revision = revision;
    final allowed = raw['enabled'] == false || raw['active'] == true;
    // Close the gate before logging. Native timestamps diagnose queued delivery;
    // they never decide whether rendering is allowed (wall clocks can change).
    onPresentationChanged(allowed);
    _iosAppPresentationActive.value = raw['active'] as bool;
    final nativeAt = raw['nativeAtUtcMs'];
    final timing = nativeAt is int
        ? ', source=${raw['source']}, nativeAtUtcMs=$nativeAt'
            ', nativeUptimeMs=${raw['nativeUptimeMs']}'
            ', deliveryMs=${DateTime.now().millisecondsSinceEpoch - nativeAt}'
            ', applicationActive=${raw['applicationActive']}'
            ', sceneActive=${raw['sceneActive']}'
        : '';
    final gpu = raw['nativeGpuGuard'] is bool
        ? ', nativeGpuGuard=${raw['nativeGpuGuard']}, gpuDisabled=${raw['gpuDisabled']}'
        : '';
    appLogger.info('Presentation allowed=$allowed, compatibility=${raw['enabled']}, revision=$revision, gate=uiPipeline$gpu$timing',
        tag: 'iOSRendering', noNotify: true);
    return true;
  }

  void _unavailable(int epoch) {
    if (!_started || epoch != _epoch) {
      return;
    }
    // An older Runner must retain ordinary Flutter rendering, not a blank UI.
    _started = false;
    _epoch++;
    _channel.setMethodCallHandler(null);
    onPresentationChanged(true);
    _iosAppPresentationActive.value = true;
    appLogger.warn('Presentation guard unavailable; using Flutter lifecycle',
        tag: 'iOSRendering', noNotify: true);
  }

  Future<void> dispose() async {
    final wasStarted = _started;
    _started = false;
    _epoch++;
    _revision = -1;
    _channel.setMethodCallHandler(null);
    onPresentationChanged(true);
    _iosAppPresentationActive.value = true;
    if (!wasStarted) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('unwatch')
          .timeout(const Duration(seconds: 3));
    } on MissingPluginException {
      // A Runner predating this optional bridge has nothing to release.
    } on PlatformException {
      // Local state is already detached even if the engine is shutting down.
    } on TimeoutException {
      // Cleanup must not hold an exiting isolate indefinitely.
    }
  }
}

class _IosPresentationWidgetsBinding extends WidgetsFlutterBinding
    with IosPresentationFrameGate {
  late final _presentation = IosPresentationBridge(
    onPresentationChanged: updateIosPresentation,
  );

  void startPresentationGuard() => unawaited(_presentation.start());
}

/// Call before other binding initialization. Existing test/integration bindings
/// are preserved; other platforms keep their ordinary WidgetsFlutterBinding.
WidgetsBinding ensureMcoaWidgetsBinding() {
  const enabled = bool.fromEnvironment('MCO_IOS_RENDER_GUARD', defaultValue: true);
  if (!enabled || !PlatformInfo.isIOS) {
    return WidgetsFlutterBinding.ensureInitialized();
  }
  WidgetsBinding? binding;
  try {
    binding = WidgetsBinding.instance;
  } on FlutterError {
    // The uninitialized getter throws FlutterError in debug builds.
  } on TypeError {
    // In release it instead null-checks the not-yet-initialized instance.
  }
  binding ??= _IosPresentationWidgetsBinding();
  if (binding is _IosPresentationWidgetsBinding) {
    binding.startPresentationGuard();
  }
  return binding;
}
