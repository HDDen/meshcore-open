import 'dart:collection';

/// A growable list that can also find an element by its key in O(1).
///
/// The key index is not kept up to date element by element. Every change to
/// the list, whichever method makes it, bumps a version, and the next lookup
/// rebuilds the index from the current contents. So a lookup can never see a
/// stale list, and a burst of changes costs a single rebuild.
///
/// Only the overrides below write to the backing list. Every other mutator
/// [ListBase] provides, from `insert` and `removeAt` to `sort`, is written in
/// terms of the length setter, the index operator and [add], so it bumps the
/// version through them.
///
/// Lookups follow `firstWhere` semantics: when several elements share a key,
/// the first one in list order is returned. Keys must not change while an
/// element is in the list.
class KeyIndexedList<E> extends ListBase<E> {
  KeyIndexedList(this._keyOf);

  final String Function(E element) _keyOf;
  final List<E> _items = <E>[];
  final Map<String, E> _index = <String, E>{};
  int _version = 0;
  int _indexedVersion = -1;

  /// Bumped by every change, whichever method makes it, so a consumer can
  /// tell in O(1) whether the list changed since it last looked.
  int get version => _version;

  /// The first element whose key is [key], or null when there is none.
  E? byKey(String key) {
    if (_indexedVersion != _version) {
      _index.clear();
      for (final item in _items) {
        _index.putIfAbsent(_keyOf(item), () => item);
      }
      _indexedVersion = _version;
    }
    return _index[key];
  }

  // The version is bumped before the backing list is touched, so a change
  // that throws halfway still leaves the index marked stale.

  @override
  int get length => _items.length;

  @override
  set length(int newLength) {
    _version++;
    _items.length = newLength;
  }

  @override
  E operator [](int index) => _items[index];

  @override
  void operator []=(int index, E value) {
    _version++;
    _items[index] = value;
  }

  // ListBase grows a list by assigning its length first, which a list of a
  // non-nullable type does not allow, so adding has to reach the backing list
  // directly.
  @override
  void add(E element) {
    _version++;
    _items.add(element);
  }

  @override
  void addAll(Iterable<E> iterable) {
    _version++;
    _items.addAll(iterable);
  }

  @override
  void removeWhere(bool Function(E element) test) {
    _version++;
    _items.removeWhere(test);
  }

  @override
  void clear() {
    _version++;
    _items.clear();
  }
}
