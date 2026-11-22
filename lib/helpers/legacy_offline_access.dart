import 'package:flutter/foundation.dart';

/// Disabled unless the private module grants the independent legacy level.
class LegacyOfflineAccess extends ChangeNotifier {
  LegacyOfflineAccess._();
  static final instance = LegacyOfflineAccess._();
  bool _enabled = false;
  bool get enabled => _enabled;
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }
}
