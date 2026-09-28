/// The last value computed for a key, handed back again while the same key
/// is asked for.
///
/// Made for a build method that derives something costly from an input the
/// provider replaces whole at every change, such as the wardrive samples: a
/// list compares by identity, so the list itself is the version, and a
/// record of the list with the few settings the derivation reads is the key.
/// One entry only, since a build asks for one key at a time; a key that
/// differs from the last one, by any field, computes anew.
class LastValueMemo<K, V> {
  K? _key;
  V? _value;
  bool _hasValue = false;

  bool get hasValue => _hasValue;

  V of(K key, V Function() compute) {
    if (_hasValue && key == _key) return _value as V;
    final value = compute();
    _key = key;
    _value = value;
    _hasValue = true;
    return value;
  }

  void clear() {
    _key = null;
    _value = null;
    _hasValue = false;
  }
}
