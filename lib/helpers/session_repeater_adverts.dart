/// Public keys of repeaters whose adverts reached the current connection.
class SessionRepeaterAdverts {
  final Set<String> _keys = {};
  int _revision = 0;

  int get revision => _revision;

  bool contains(String publicKeyHex) => _keys.contains(publicKeyHex);

  bool record(String publicKeyHex) {
    if (!_keys.add(publicKeyHex)) return false;
    _revision++;
    return true;
  }

  void clear() {
    if (_keys.isEmpty) return;
    _keys.clear();
    _revision++;
  }
}
