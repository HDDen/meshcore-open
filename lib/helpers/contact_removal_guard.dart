/// Prevents implicit ADD_UPDATE_CONTACT writes while deletion awaits the node.
/// A node/contact pair is held only for the lifetime of its removal futures.
class ContactRemovalGuard {
  final Map<(String, String), int> _pending = {};

  bool isRemoving(String nodeKey, String contactKey) =>
      _pending.containsKey((nodeKey, contactKey));

  Future<void> run({
    required String nodeKey,
    required String contactKey,
    required Future<void> Function() operation,
  }) async {
    final key = (nodeKey, contactKey);
    _pending[key] = (_pending[key] ?? 0) + 1;
    try {
      await operation();
    } finally {
      final remaining = _pending[key]! - 1;
      if (remaining == 0) {
        _pending.remove(key);
      } else {
        _pending[key] = remaining;
      }
    }
  }
}
