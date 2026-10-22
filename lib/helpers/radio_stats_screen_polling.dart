import 'package:flutter/widgets.dart';

import '../connector/meshcore_connector.dart';
import '../services/app_settings_service.dart';
import '../utils/app_route_observer.dart';
import 'ios_presentation_guard.dart';

final _screenPollGroups = Expando<_ScreenPollGroup>('radio stats screens');

/// Change only the screen's cadence; retain its normal polling ownership.
class RadioStatsScreenPolling with WidgetsBindingObserver, RouteAware {
  RadioStatsScreenPolling(
    MeshCoreConnector connector,
    this._settings,
  ) {
    _group = _screenPollGroups[connector] ??= _ScreenPollGroup(connector);
    connector.acquireRadioStatsPolling();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    iosAppPresentationActive.addListener(_sync);
    _settings.addListener(_sync);
    _sync();
  }

  final AppSettingsService _settings;
  late final _ScreenPollGroup _group;
  PageRoute<dynamic>? _route;
  bool _foreground = true;
  bool _routeCurrent = true;
  bool? _legacy;
  int? _requested;
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
    final hidden = _settings.settings.powerSaving.effective
        .hiddenRadioStatsIntervalSeconds;
    final legacy = hidden == 1;
    final visible = _foreground && _routeCurrent &&
        iosAppPresentationActive.value;
    final requested = visible ? 1 : hidden;
    if (_legacy == legacy && _requested == requested) return;
    _legacy = legacy;
    _requested = requested;
    _group.update(this, requested, legacy: legacy);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    iosAppPresentationActive.removeListener(_sync);
    _settings.removeListener(_sync);
    _group.remove(this, legacy: _legacy == true);
    _group.connector.releaseRadioStatsPolling();
    if (_group.isEmpty) {
      _group.dispose();
      _screenPollGroups[_group.connector] = null;
    }
  }
}

/// Active screens win over hidden ones. Off/minimum retain legacy pop behavior.
class _ScreenPollGroup {
  _ScreenPollGroup(this.connector) {
    connector.radioStatsPollingOwners.addListener(_ownersChanged);
    connector.addListener(_ownersChanged);
  }

  final MeshCoreConnector connector;
  final _requests = <Object, int>{};
  final _legacyOwners = <Object>{};
  int? _interval;

  bool get isEmpty => _requests.isEmpty;

  void update(Object owner, int seconds, {required bool legacy}) {
    _requests[owner] = seconds;
    if (legacy) {
      _legacyOwners.add(owner);
    } else {
      _legacyOwners.remove(owner);
    }
    // Legacy screen init restarted the timer even if another screen used it.
    _apply(legacy ? 1 : _minimum(), force: legacy);
  }

  void remove(Object owner, {required bool legacy}) {
    _requests.remove(owner);
    _legacyOwners.remove(owner);
    // With power saving off, dispose restored 30 s unconditionally.
    _apply(legacy || isEmpty ? 30 : _minimum(), force: legacy);
  }

  int _minimum() {
    // Retry/ACK/delayed-send work keeps the screen's original fast observations.
    if (connector.hasPendingRadioStatsWork) return 1;
    final requested = _requests.values.reduce((a, b) => a < b ? a : b);
    // A normal indicator/other consumer must still receive its 30 s cadence.
    final hasOtherOwners = connector.radioStatsPollingOwners.value >
        _requests.length;
    return hasOtherOwners && requested > 30 ? 30 : requested;
  }

  void _ownersChanged() {
    if (isEmpty || _legacyOwners.length == _requests.length) return;
    _apply(_minimum());
  }

  void dispose() {
    connector.radioStatsPollingOwners.removeListener(_ownersChanged);
    connector.removeListener(_ownersChanged);
  }

  void _apply(int seconds, {bool force = false}) {
    if (!force && seconds == _interval) return;
    _interval = seconds;
    connector.setPollingInterval(seconds);
  }
}
