import 'dart:collection';

/// A map that counts its own writes, so a consumer can tell in O(1) whether
/// anything changed since it last looked.
///
/// Only the overrides below write to the backing map. Every other mutator
/// [MapBase] provides, from `addAll` to `update` and `removeWhere`, is written
/// in terms of the index operator and [remove], so it bumps the version
/// through them. The version moves on every write, even one that stores the
/// value already there.
class VersionedMap<K, V> extends MapBase<K, V> {
  final Map<K, V> _entries = <K, V>{};
  int _version = 0;

  /// Bumped by every write, whichever method makes it.
  int get version => _version;

  @override
  V? operator [](Object? key) => _entries[key];

  @override
  void operator []=(K key, V value) {
    _version++;
    _entries[key] = value;
  }

  @override
  V? remove(Object? key) {
    _version++;
    return _entries.remove(key);
  }

  @override
  void clear() {
    _version++;
    _entries.clear();
  }

  // MapBase answers this by walking the keys; the backing map does not.
  @override
  bool containsKey(Object? key) => _entries.containsKey(key);

  @override
  Iterable<K> get keys => _entries.keys;
}
