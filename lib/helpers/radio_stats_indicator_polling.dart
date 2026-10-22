import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../connector/meshcore_connector.dart';
import '../services/app_settings_service.dart';
import '../utils/app_route_observer.dart';
import 'ios_presentation_guard.dart';

/// Владелец только визуального индикатора; отправку удерживает коннектор.
class RadioStatsIndicatorPolling with WidgetsBindingObserver, RouteAware {
  RadioStatsIndicatorPolling(this._connector, this._settings) {
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _settings.addListener(_sync);
    _connector.addListener(_sync);
    iosAppPresentationActive.addListener(_sync);
    _sync();
  }

  final MeshCoreConnector _connector;
  final AppSettingsService _settings;
  PageRoute<dynamic>? _route;
  ValueListenable<TickerModeData>? _tickerMode;
  bool _foreground = true;
  bool _routeCurrent = true;
  bool _holding = false;
  bool _disposed = false;

  void updateRoute(BuildContext context) {
    if (_disposed) return;
    final modal = ModalRoute.of(context);
    final route = modal is PageRoute<dynamic> ? modal : null;
    if (!identical(route, _route)) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) {
        appRouteObserver.subscribe(this, route);
      }
    }
    final tickerMode = TickerMode.getValuesNotifier(context);
    if (!identical(tickerMode, _tickerMode)) {
      _tickerMode?.removeListener(_sync);
      _tickerMode = tickerMode..addListener(_sync);
    }
    _setRouteCurrent(modal?.isCurrent ?? true);
  }

  @override
  void didPush() => _setRouteCurrent(true);

  @override
  void didPopNext() => _setRouteCurrent(true);

  @override
  void didPushNext() => _setRouteCurrent(false);

  @override
  void didPop() => _setRouteCurrent(false);

  void _setRouteCurrent(bool current) {
    if (_disposed) return;
    _routeCurrent = current;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    final settings = _settings.settings;
    final pauseHidden = settings.powerSaving.effective.pauseHiddenRadioIndicator;
    final visible = _foreground && _routeCurrent &&
        (_tickerMode?.value.enabled ?? true) && iosAppPresentationActive.value &&
        !settings.hideRadioStatsButton && _connector.isConnected &&
        _connector.supportsCompanionRadioStats;
    final needed = !pauseHidden || visible;
    if (_holding == needed) return;
    _holding = needed;
    if (needed) {
      _connector.acquireRadioStatsPolling();
    } else {
      _connector.releaseRadioStatsPolling();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _tickerMode?.removeListener(_sync);
    _settings.removeListener(_sync);
    _connector.removeListener(_sync);
    iosAppPresentationActive.removeListener(_sync);
    if (_holding) {
      _holding = false;
      _connector.releaseRadioStatsPolling();
    }
  }
}
