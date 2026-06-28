import 'dart:async';
import 'dart:isolate';

typedef CancellableComputeCallback<M, R> = FutureOr<R> Function(M message);

abstract interface class CancellableComputeTask<R> {
  Future<R> get result;

  bool get isCancelled;

  void cancel();
}

class CancellableComputeCancelledException implements Exception {
  final String message;

  const CancellableComputeCancelledException([
    this.message = 'Background computation was cancelled',
  ]);

  @override
  String toString() => 'CancellableComputeCancelledException: $message';
}

CancellableComputeTask<R> startCancellableCompute<M, R>(
  CancellableComputeCallback<M, R> callback,
  M message, {
  String? debugLabel,
}) {
  return _IsolateCancellableComputeTask<M, R>(
    callback,
    message,
    debugLabel: debugLabel,
  );
}

class _CancellableComputeInvocation<M, R> {
  final CancellableComputeCallback<M, R> callback;
  final M message;
  final SendPort resultPort;

  const _CancellableComputeInvocation({
    required this.callback,
    required this.message,
    required this.resultPort,
  });
}

@pragma('vm:entry-point')
Future<void> _runCancellableCompute<M, R>(
  _CancellableComputeInvocation<M, R> invocation,
) async {
  try {
    // Keep M and R intact inside the worker isolate. Erasing the invocation to
    // <dynamic, dynamic> would require a callback such as
    // (List<Request>) => Result to be cast to (dynamic) => dynamic, which Dart
    // correctly rejects because function parameter types are contravariant.
    final R result = await invocation.callback(invocation.message);

    // Send the result normally and then let the worker return naturally.
    invocation.resultPort.send(<Object?>[0, result]);
  } catch (error, stackTrace) {
    try {
      invocation.resultPort.send(<Object?>[
        1,
        error,
        stackTrace.toString(),
      ]);
    } catch (_) {
      // Some exception objects are not transferable between isolates.
      invocation.resultPort.send(<Object?>[
        2,
        error.toString(),
        stackTrace.toString(),
      ]);
    }
  }
}

class _IsolateCancellableComputeTask<M, R>
    implements CancellableComputeTask<R> {
  final Completer<R> _completer = Completer<R>();
  final ReceivePort _resultPort = ReceivePort();
  final ReceivePort _errorPort = ReceivePort();

  Isolate? _isolate;
  bool _isCancelled = false;
  bool _isCleanedUp = false;

  _IsolateCancellableComputeTask(
    CancellableComputeCallback<M, R> callback,
    M message, {
    String? debugLabel,
  }) {
    _resultPort.listen(_handleResultMessage);
    _errorPort.listen(_handleRuntimeError);
    _spawn(callback, message, debugLabel);
  }

  @override
  Future<R> get result => _completer.future;

  @override
  bool get isCancelled => _isCancelled;

  Future<void> _spawn(
    CancellableComputeCallback<M, R> callback,
    M message,
    String? debugLabel,
  ) async {
    try {
      final isolate = await Isolate.spawn<
        _CancellableComputeInvocation<M, R>
      >(
        _runCancellableCompute<M, R>,
        _CancellableComputeInvocation<M, R>(
          callback: callback,
          message: message,
          resultPort: _resultPort.sendPort,
        ),
        onError: _errorPort.sendPort,
        errorsAreFatal: true,
        debugName: debugLabel,
      );

      if (_isCancelled) {
        isolate.kill(priority: Isolate.immediate);
        _cleanup();
        return;
      }

      // The worker may already have returned its result before Isolate.spawn()
      // completes on the caller side. In that case the task is already cleaned.
      if (_isCleanedUp) {
        return;
      }
      _isolate = isolate;
    } catch (error, stackTrace) {
      if (!_completer.isCompleted) {
        _completer.completeError(error, stackTrace);
      }
      _cleanup();
    }
  }

  void _handleResultMessage(Object? message) {
    if (_completer.isCompleted) return;

    if (message is! List<Object?> || message.isEmpty) {
      _completer.completeError(
        StateError('Background isolate returned an invalid response'),
      );
      _cleanup();
      return;
    }

    final status = message.first;
    if (status == 0) {
      if (message.length < 2) {
        _completer.completeError(
          StateError('Background isolate returned no result'),
        );
      } else {
        _completer.complete(message[1] as R);
      }
      _cleanup();
      return;
    }

    if (status == 1) {
      final error = message.length > 1
          ? message[1] ?? StateError('Unknown background error')
          : StateError('Unknown background error');
      final stackTrace = message.length > 2
          ? StackTrace.fromString(message[2].toString())
          : StackTrace.current;
      _completer.completeError(error, stackTrace);
      _cleanup();
      return;
    }

    if (status == 2) {
      final description = message.length > 1
          ? message[1].toString()
          : 'Unknown background error';
      final stackTrace = message.length > 2
          ? StackTrace.fromString(message[2].toString())
          : StackTrace.current;
      _completer.completeError(StateError(description), stackTrace);
      _cleanup();
      return;
    }

    _completer.completeError(
      StateError('Background isolate returned an unknown status: $status'),
    );
    _cleanup();
  }

  void _handleRuntimeError(Object? message) {
    if (_completer.isCompleted) return;

    if (message is List<Object?> && message.length >= 2) {
      _completer.completeError(
        StateError(message[0].toString()),
        StackTrace.fromString(message[1].toString()),
      );
    } else {
      _completer.completeError(
        StateError('Background isolate failed: $message'),
      );
    }
    _cleanup();
  }

  @override
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;

    // A hard kill is used only for explicit cancellation, such as dispose().
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;

    if (!_completer.isCompleted) {
      _completer.completeError(
        const CancellableComputeCancelledException(),
      );
    }
    _cleanup();
  }

  void _cleanup() {
    if (_isCleanedUp) return;
    _isCleanedUp = true;

    // On successful completion the worker is allowed to return naturally.
    // Killing here could race with delivery of the result message.
    _isolate = null;
    _resultPort.close();
    _errorPort.close();
  }
}
