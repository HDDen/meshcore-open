import 'dart:async';

/// Owns one location stream; stopped generations cannot attach late listeners.
class ContinuousLocationSubscription<T> {
  ContinuousLocationSubscription({
    required this.prepare,
    required this.openStream,
    required this.onData,
    required this.onError,
  });

  final Future<void> Function() prepare;
  final Stream<T> Function() openStream;
  final void Function(T) onData;
  final void Function(Object) onError;
  StreamSubscription<T>? _subscription;
  Future<void>? _starting;
  Future<void> _tail = Future<void>.value();
  Object? _generation;
  bool _closed = false;

  bool _current(Object generation) =>
      !_closed && identical(_generation, generation);

  Future<void> start() {
    if (_closed || _subscription != null) return _tail;
    final pending = _starting;
    if (pending != null) return pending;
    final generation = Object();
    _generation = generation;
    return _starting = _tail = _openAfter(_tail, generation);
  }

  Future<void> _openAfter(Future<void> previous, Object generation) async {
    try {
      // Serialize preparation and cancellation, including stop/start races.
      await previous;
      if (!_current(generation)) return;
      await prepare();
      if (!_current(generation)) return;
      _subscription = openStream().listen(
        (value) {
          if (_current(generation)) onData(value);
        },
        onError: (Object error) {
          if (_current(generation)) onError(error);
        },
      );
    } catch (error) {
      if (_current(generation)) onError(error);
    } finally {
      if (_current(generation)) _starting = null;
    }
  }

  Future<void> stop() {
    _generation = null;
    _starting = null;
    final subscription = _subscription;
    _subscription = null;
    return _tail = _closeAfter(_tail, subscription);
  }

  Future<void> _closeAfter(
    Future<void> previous,
    StreamSubscription<T>? subscription,
  ) async {
    await previous;
    try {
      if (subscription != null) await subscription.cancel();
    } catch (error) {
      if (!_closed) onError(error);
    }
  }

  Future<void> close() {
    _closed = true;
    return stop();
  }
}
