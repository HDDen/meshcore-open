/// Joins concurrent cursor reads and discards pages for a replaced history.
/// The caller merges into its live window so arrivals during I/O are retained.
class HistoryPageLoads<T> {
  final Map<Object, Future<List<T>>> _pending = {};

  Future<List<T>> load({
    required Object key,
    required bool Function() current,
    required Future<List<T>> Function() read,
    required void Function(List<T>) apply,
  }) {
    final existing = _pending[key];
    if (existing != null) {
      return existing;
    }
    late final Future<List<T>> pending;
    pending = Future<List<T>>.sync(read).then((page) {
      if (!current()) {
        return <T>[];
      }
      if (page.isNotEmpty) {
        apply(page);
      }
      return page;
    }).whenComplete(() {
      if (identical(_pending[key], pending)) {
        _pending.remove(key);
      }
    });
    _pending[key] = pending;
    return pending;
  }
}
