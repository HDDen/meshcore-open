import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../utils/app_route_observer.dart';
import 'ios_presentation_guard.dart';

/// Ограничивает только показ GIF; lifecycle транспорта не меняется.
class GifPlaybackVisibility with WidgetsBindingObserver, RouteAware {
  GifPlaybackVisibility({required this.onChanged});

  final VoidCallback onChanged;
  PageRoute<dynamic>? _route;
  ValueListenable<TickerModeData>? _tickerMode;
  Key _visibilityKey = UniqueKey();
  bool _enabled = false;
  bool _visible = false;
  bool _foreground = true;
  bool _routeCurrent = true;
  bool _lastAllowed = true;
  bool _updating = false;
  bool _disposed = false;

  bool get allowed => !_enabled || (_visible && _foreground && _routeCurrent &&
      (_tickerMode?.value.enabled ?? true) && iosAppPresentationActive.value);

  void updateContext(BuildContext context, {required bool enabled}) {
    if (_disposed) {
      return;
    }
    _updating = true;
    if (_enabled != enabled) {
      _enabled = enabled;
      if (enabled) {
        _visible = false;
        _visibilityKey = UniqueKey();
        final state = WidgetsBinding.instance.lifecycleState;
        _foreground = state == null || state == AppLifecycleState.resumed;
        WidgetsBinding.instance.addObserver(this);
        iosAppPresentationActive.addListener(_sync);
      } else {
        _detach();
      }
    }
    if (enabled) {
      final modal = ModalRoute.of(context);
      final route = modal is PageRoute<dynamic> ? modal : null;
      if (!identical(route, _route)) {
        appRouteObserver.unsubscribe(this);
        _route = route;
        if (route != null) {
          appRouteObserver.subscribe(this, route);
        }
      }
      _routeCurrent = modal?.isCurrent ?? true;
      final tickerMode = TickerMode.getValuesNotifier(context);
      if (!identical(tickerMode, _tickerMode)) {
        _tickerMode?.removeListener(_sync);
        _tickerMode = tickerMode..addListener(_sync);
      }
    }
    _updating = false;
    _sync();
  }

  Widget wrap(Widget child) {
    if (!_enabled) {
      return child;
    }
    final key = _visibilityKey;
    return VisibilityDetector(
      key: key,
      onVisibilityChanged: (info) {
        if (_disposed || !_enabled || key != _visibilityKey) {
          return;
        }
        _visible = info.visibleFraction > 0;
        _sync();
      },
      child: TickerMode(enabled: allowed, child: child),
    );
  }

  void _sync() {
    if (_disposed || _updating) {
      return;
    }
    final next = allowed;
    if (_lastAllowed == next) {
      return;
    }
    _lastAllowed = next;
    onChanged();
  }

  void _setRouteCurrent(bool current) {
    _routeCurrent = current;
    _sync();
  }

  @override
  void didPush() => _setRouteCurrent(true);
  @override
  void didPopNext() => _setRouteCurrent(true);
  @override
  void didPushNext() => _setRouteCurrent(false);
  @override
  void didPop() => _setRouteCurrent(false);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _detach() {
    WidgetsBinding.instance.removeObserver(this);
    iosAppPresentationActive.removeListener(_sync);
    appRouteObserver.unsubscribe(this);
    _route = null;
    _tickerMode?.removeListener(_sync);
    _tickerMode = null;
    VisibilityDetectorController.instance.forget(_visibilityKey);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _detach();
  }
}

/// Снятие listener останавливает анимацию, handle защищает поток от imageCache.evict.
class GifImageSubscription {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageStreamCompleterHandle? _handle;
  bool _listening = false;

  bool get hasStream => _stream != null;

  void bind(ImageStream stream, ImageStreamListener listener) {
    clear();
    _stream = stream;
    _listener = listener;
  }

  void setPlaying(bool playing) {
    final stream = _stream;
    final listener = _listener;
    if (stream == null || listener == null || playing == _listening) {
      return;
    }
    if (playing) {
      final handle = _handle;
      _handle = null;
      _listening = true;
      stream.addListener(listener);
      handle?.dispose();
    } else {
      _handle ??= stream.completer?.keepAlive();
      _listening = false;
      stream.removeListener(listener);
    }
  }

  void clear() {
    final stream = _stream;
    final listener = _listener;
    _stream = null;
    _listener = null;
    if (_listening && stream != null && listener != null) {
      _listening = false;
      stream.removeListener(listener);
    }
    _handle?.dispose();
    _handle = null;
  }
}
