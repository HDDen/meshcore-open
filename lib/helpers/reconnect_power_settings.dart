import 'package:flutter/widgets.dart';

import 'ios_presentation_guard.dart';

/// Фон приложения, независимо от маршрутов и видимости отдельных виджетов.
class ReconnectPowerSettings with WidgetsBindingObserver {
  ReconnectPowerSettings({required this.onChanged}) {
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _background = !_foreground || !iosAppPresentationActive.value;
    WidgetsBinding.instance.addObserver(this);
    iosAppPresentationActive.addListener(_sync);
  }

  final void Function() onChanged;
  late bool _foreground;
  late bool _background;
  int _intervalSeconds = 30;
  bool _disposed = false;

  bool get background => _background;
  int get intervalSeconds => _intervalSeconds;

  void setInterval(int seconds) {
    if (_disposed || seconds == _intervalSeconds) {
      return;
    }
    _intervalSeconds = seconds;
    onChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) {
      return;
    }
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (_disposed) {
      return;
    }
    final next = !_foreground || !iosAppPresentationActive.value;
    if (_background != next) {
      _background = next;
      onChanged();
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    iosAppPresentationActive.removeListener(_sync);
  }
}
