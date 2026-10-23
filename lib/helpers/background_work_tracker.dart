import 'dart:async';

enum BackgroundWorkKind {
  transportSetup,
  transportWrite,
  contactSync,
  channelSync,
  messageSync,
  commandReply,
  radioSend,
  retry,
  receiveAssembly,
  imageTransfer,
  persistence,
  notification,
  location,
  backgroundFeature,
  queuedMessageRequest,
  transportTeardown,
}

/// Неизменяемый снимок учёта, без кадров, адресов и содержимого сообщений.
class BackgroundWorkSnapshot {
  BackgroundWorkSnapshot._(
    this.revision,
    this.isClosed,
    this.activeCount,
    Map<BackgroundWorkKind, int> counts,
  ) : counts = Map.unmodifiable(counts);

  final int revision;
  final bool isClosed;
  final int activeCount;
  final Map<BackgroundWorkKind, int> counts;

  bool get isBusy => activeCount > 0;
  int countFor(BackgroundWorkKind kind) => counts[kind] ?? 0;
}

/// Один владелец освобождает только своё удержание, включая повторный release.
class BackgroundWorkLease {
  BackgroundWorkLease._(this._owner, this.kind);

  BackgroundWorkTracker? _owner;
  final BackgroundWorkKind kind;

  bool get isReleased => _owner == null;

  void release() {
    final owner = _owner;
    if (owner == null) return;
    _owner = null;
    owner._release(kind);
  }
}

/// Только учёт операций: не управляет CPU, транспортами или временем их жизни.
class BackgroundWorkTracker {
  final Map<BackgroundWorkKind, int> _counts = {};
  int _activeCount = 0;
  int _revision = 0;
  bool _closed = false;

  int get activeCount => _activeCount;
  int get revision => _revision;
  bool get isBusy => _activeCount > 0;
  bool get isClosed => _closed;

  BackgroundWorkSnapshot get snapshot =>
      BackgroundWorkSnapshot._(_revision, _closed, _activeCount, _counts);

  BackgroundWorkLease begin(BackgroundWorkKind kind) {
    if (_closed) throw StateError('Background work tracker is closed');
    _counts[kind] = (_counts[kind] ?? 0) + 1;
    _activeCount++;
    _revision++;
    return BackgroundWorkLease._(this, kind);
  }

  Future<T> run<T>(BackgroundWorkKind kind, FutureOr<T> Function() operation) async {
    final lease = begin(kind);
    try {
      return await operation();
    } finally {
      lease.release();
    }
  }

  void _release(BackgroundWorkKind kind) {
    final count = _counts[kind]!;
    if (count == 1) {
      _counts.remove(kind);
    } else {
      _counts[kind] = count - 1;
    }
    _activeCount--;
    _revision++;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _revision++;
    // Запрещаем новые операции, но не объявляем незавершённые выполненными.
    // Их удержания остаются до настоящего завершения или отмены владельцем.
  }
}
