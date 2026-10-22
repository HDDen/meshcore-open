/// Удерживает опрос для отправки независимо от наличия экранов и индикаторов.
class RadioStatsSendPolling {
  RadioStatsSendPolling({
    required this.isConnected,
    required this.hasPendingWork,
    required this.acquire,
    required this.release,
  });

  final bool Function() isConnected;
  final bool Function() hasPendingWork;
  final void Function() acquire;
  final void Function() release;
  bool _enabled = false;
  bool _holding = false;
  bool _disposed = false;
  int _operations = 0;

  bool get hasActiveOperations => _operations > 0;

  void setEnabled(bool enabled) {
    _enabled = enabled;
    sync();
  }

  void sync() {
    if (_disposed) return;
    final needed = _enabled && isConnected() &&
        (hasActiveOperations || hasPendingWork());
    if (_holding == needed) return;
    _holding = needed;
    if (needed) {
      acquire();
    } else {
      release();
    }
  }

  Future<void> run(Future<void> Function() operation) async {
    // Подготовка/подпись ещё не обязана присутствовать в очереди сообщений.
    _operations++;
    sync();
    try {
      await operation();
    } finally {
      _operations--;
      sync();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_holding) {
      _holding = false;
      release();
    }
  }
}
