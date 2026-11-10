/// Open transcript routes keep their paged history. Only the top route
/// suppresses unread counts, even before the next widget frame.
class ChatRouteRegistry<K> {
  final _routes = <K, Set<bool Function()>>{};

  bool contains(K key) => _routes.containsKey(key);

  bool? isVisible(K key) => _routes[key]?.any((isCurrent) => isCurrent());

  void Function() add(
    K key,
    bool Function() isCurrent, {
    required void Function() onLastClose,
  }) {
    final routes = _routes.putIfAbsent(key, () => {});
    routes.add(isCurrent);
    return () {
      if (!identical(_routes[key], routes) || !routes.remove(isCurrent)) return;
      if (routes.isEmpty) {
        _routes.remove(key);
        onLastClose();
      }
    };
  }

  void clear() => _routes.clear();
}
