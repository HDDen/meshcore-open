import 'package:flutter/widgets.dart';

/// Observes route coverage without coupling history retention to visibility.
class ChatRouteActivity {
  ModalRoute<dynamic>? _route;
  bool _wasCurrent = false;
  VoidCallback? _activate;
  VoidCallback? _release;

  bool get _isCurrent => _route?.isCurrent ?? true;

  void updateRoute(ModalRoute<dynamic>? route) {
    _route = route;
    final becameCurrent = !_wasCurrent && _isCurrent;
    _wasCurrent = _isCurrent;
    final activate = _activate;
    if (!becameCurrent || activate == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_activate == activate && _isCurrent) activate();
    });
  }

  void attach({
    required VoidCallback Function(bool Function()) register,
    required VoidCallback activate,
  }) {
    _activate = activate;
    _release = register(() => _isCurrent);
    if (_isCurrent) activate();
  }

  void dispose() {
    _activate = null;
    _release?.call();
    _release = null;
    _route = null;
  }
}
