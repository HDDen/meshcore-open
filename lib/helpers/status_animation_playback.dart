import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart' show BuildContext, VoidCallback, Widget;

import '../models/power_saving_settings.dart';
import 'gif_playback.dart';

/// Управляет только тикером статусного индикатора, не состоянием отправки.
class StatusAnimationPlayback {
  StatusAnimationPlayback({
    required this.controller,
    required this.onChanged,
    this.reverse = false,
  });

  final AnimationController controller;
  final VoidCallback onChanged;
  final bool reverse;
  GifPlaybackVisibility? _visibility;
  bool _requested = false;
  bool _displayed = true;
  bool _pauseHidden = false;
  bool _staticPresentation = false;
  bool _updating = false;
  bool _disposed = false;

  bool get staticPresentation => _staticPresentation;

  void updateContext(
    BuildContext context, {
    required PowerSavingOptions options,
    required bool requested,
    bool displayed = true,
  }) {
    if (_disposed) {
      return;
    }
    _updating = true;
    _requested = requested;
    _displayed = displayed;
    _pauseHidden = options.pauseHiddenStatusAnimations;
    _staticPresentation = options.disableContinuousStatusAnimations;
    if (_pauseHidden && !_staticPresentation && requested && displayed) {
      // Используем существующий наблюдатель route/viewport/lifecycle/native.
      _visibility ??= GifPlaybackVisibility(onChanged: _visibilityChanged);
      _visibility!.updateContext(context, enabled: true);
    } else {
      _visibility?.dispose();
      _visibility = null;
    }
    _updating = false;
    _syncController();
  }

  Widget wrap(Widget child) => _visibility?.wrap(child) ?? child;

  void _visibilityChanged() {
    if (_disposed) {
      return;
    }
    _syncController();
    if (!_updating) {
      onChanged();
    }
  }

  void _syncController() {
    final play = _requested && !_staticPresentation &&
        (!_pauseHidden || (_displayed && (_visibility?.allowed ?? false)));
    if (play) {
      if (!controller.isAnimating) {
        controller.repeat(reverse: reverse);
      }
    } else {
      if (controller.isAnimating) {
        controller.stop();
      }
      // Пауза сохраняет фазу; завершение статуса начинает следующий с нуля.
      if (!_requested && controller.value != 0) {
        controller.value = 0;
      }
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _visibility?.dispose();
    _visibility = null;
  }
}
