/// Разделяет запрос транспорта и разрешение снять собственный Wi-Fi lock.
class TcpWifiLockPolicy {
  TcpWifiLockPolicy({required this.apply});

  final Future<void> Function(bool enabled) apply;
  bool _requested = false;
  bool _releaseAllowed = false;
  Future<void> _tail = Future<void>.value();

  Future<void> request(bool enabled) {
    _requested = enabled;
    return _enqueue();
  }

  Future<void> setReleaseAllowed(bool allowed) {
    if (_releaseAllowed == allowed) {
      return _tail;
    }
    _releaseAllowed = allowed;
    return _enqueue();
  }

  Future<void> _enqueue() {
    final enabled = _requested && !_releaseAllowed;
    // Новый release выполняется после ответа старого acquire, не наоборот.
    final next = _tail.then((_) => apply(enabled));
    // Ошибка видна вызывающему, но не блокирует последующие команды.
    _tail = next.catchError((Object error) {});
    return next;
  }
}
