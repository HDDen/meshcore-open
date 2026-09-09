import 'dart:collection';

/// Small LRU cache for presentation data derived from immutable message text.
///
/// The caller supplies a stable message key. Reusing that key with changed
/// text replaces the stale value, which also covers edited/pending messages.
class MessageContentCache<T extends Object> {
  MessageContentCache({this.maxEntries = 192})
    : assert(maxEntries > 0, 'maxEntries must be positive');

  final int maxEntries;
  final LinkedHashMap<String, _CachedMessageContent<T>> _entries =
      LinkedHashMap<String, _CachedMessageContent<T>>();

  T resolve({
    required String key,
    required String text,
    required T Function() build,
  }) {
    final cached = _entries.remove(key);
    if (cached != null && cached.text == text) {
      _entries[key] = cached;
      return cached.value;
    }

    final value = build();
    _entries[key] = _CachedMessageContent<T>(text, value);
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return value;
  }

  void clear() => _entries.clear();
}

class _CachedMessageContent<T extends Object> {
  const _CachedMessageContent(this.text, this.value);

  final String text;
  final T value;
}
