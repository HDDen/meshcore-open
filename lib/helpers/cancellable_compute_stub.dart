import 'dart:async';

import 'package:flutter/foundation.dart';

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
  return _FallbackCancellableComputeTask<M, R>(
    callback,
    message,
    debugLabel: debugLabel,
  );
}

class _FallbackCancellableComputeTask<M, R>
    implements CancellableComputeTask<R> {
  final Completer<R> _completer = Completer<R>();
  bool _isCancelled = false;

  _FallbackCancellableComputeTask(
    CancellableComputeCallback<M, R> callback,
    M message, {
    String? debugLabel,
  }) {
    _run(callback, message, debugLabel);
  }

  @override
  Future<R> get result => _completer.future;

  @override
  bool get isCancelled => _isCancelled;

  Future<void> _run(
    CancellableComputeCallback<M, R> callback,
    M message,
    String? debugLabel,
  ) async {
    try {
      final value = await compute(callback, message, debugLabel: debugLabel);
      if (!_completer.isCompleted) {
        _completer.complete(value);
      }
    } catch (error, stackTrace) {
      if (!_completer.isCompleted) {
        _completer.completeError(error, stackTrace);
      }
    }
  }

  @override
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    if (!_completer.isCompleted) {
      _completer.completeError(const CancellableComputeCancelledException());
    }
  }
}
