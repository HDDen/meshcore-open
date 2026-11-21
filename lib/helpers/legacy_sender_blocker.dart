/// Pure-Dart runtime opt-in. Persisted rules and message stamps stay untouched
/// while dormant; only the private module's phrase grant enables production use.
class LegacySenderBlocker {
  LegacySenderBlocker._();
  static final instance = LegacySenderBlocker._();
  final _listeners = <void Function()>{};

  bool _enabled = false;
  bool get enabled => _enabled;

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void setEnabled(bool value) {
    if (_enabled == value) { return; }
    _enabled = value;
    for (final listener in _listeners.toList()) {
      if (_listeners.contains(listener)) { listener(); }
    }
  }
}
