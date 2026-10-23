import 'dart:async';

/// Bound individual asynchronous cleanup steps without abandoning the rest of
/// teardown. Actions must capture old resources: a timeout does not cancel them.
class ConnectionCleanup {
  ConnectionCleanup({
    this.timeout = defaultTimeout,
    this.onFailure,
    this.runAction,
  });

  static const defaultTimeout = Duration(seconds: 3);
  final Duration timeout;
  final void Function(String stage, Object error, StackTrace stack)? onFailure;
  // Обёртка захватывает исходную операцию до применения timeout.
  final Future<void>? Function(Future<void>? Function())? runAction;

  Future<void> run(String stage, Future<void>? Function() action) async {
    try {
      final pending = runAction == null ? action() : runAction!(action);
      if (pending != null) {
        await pending.timeout(timeout);
      }
    } catch (error, stack) {
      onFailure?.call(stage, error, stack);
    }
  }
}
