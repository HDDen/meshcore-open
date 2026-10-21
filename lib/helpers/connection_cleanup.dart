import 'dart:async';

/// Bound individual asynchronous cleanup steps without abandoning the rest of
/// teardown. Actions must capture old resources: a timeout does not cancel them.
class ConnectionCleanup {
  ConnectionCleanup({this.timeout = defaultTimeout, this.onFailure});

  static const defaultTimeout = Duration(seconds: 3);
  final Duration timeout;
  final void Function(String stage, Object error, StackTrace stack)? onFailure;

  Future<void> run(String stage, Future<void>? Function() action) async {
    try {
      final pending = action();
      if (pending != null) {
        await pending.timeout(timeout);
      }
    } catch (error, stack) {
      onFailure?.call(stage, error, stack);
    }
  }
}
