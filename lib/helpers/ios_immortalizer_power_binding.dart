import 'dart:async';

import 'package:flutter/services.dart';

import '../models/ios_immortalizer_power_options.dart';
import '../services/app_settings_service.dart';
import 'ios_presentation_guard.dart';

/// Отдельный канал параметров, без изменения eligibility/manual override.
class IosImmortalizerPowerBinding {
  IosImmortalizerPowerBinding({required this.settings, required this.channel,
    this.onError, void Function(bool)? applyFramePause})
      : _applyFramePause = applyFramePause ?? setIosFrameSchedulingPause {
    settings.addListener(_sync);
    _sync();
  }
  final AppSettingsService settings;
  final MethodChannel channel;
  final void Function(Object)? onError;
  final void Function(bool) _applyFramePause;
  // Старый Runner и существующие клиенты с default не получают новых вызовов.
  IosImmortalizerPowerOptions? _sent = const IosImmortalizerPowerOptions();
  bool _disposed = false;
  int _revision = 0;

  void _sync() {
    if (_disposed) {
      return;
    }
    final options = settings.settings.powerSaving.effective.iosImmortalizer;
    if (options == _sent) {
      return;
    }
    _sent = options;
    _applyFramePause(options.pauseUiFrames);
    final revision = ++_revision;
    unawaited(channel.invokeMethod<void>('configurePower', options.toNativeArguments())
        .catchError((Object error) {
      if (!_disposed && revision == _revision) {
        _sent = null;
        onError?.call(error);
      }
    }));
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _revision++;
    settings.removeListener(_sync);
    _applyFramePause(false);
    final sent = _sent;
    if (sent == null || !sent.isOriginal) {
      unawaited(channel.invokeMethod<void>('configurePower',
          const IosImmortalizerPowerOptions().toNativeArguments())
          .catchError((Object _) { /* Native controller may already be closed. */ }));
    }
  }
}
