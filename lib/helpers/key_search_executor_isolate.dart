import 'dart:async';
import 'dart:isolate';

const supportsKeySearchIsolates = true;

/// Owns at most one batch. Cancellation completes the caller immediately and
/// kills the worker, including a worker whose spawn handshake is still pending.
class KeySearchExecutor {
  _OperationBase? _active;

  Future<R?> run<A, R>(Future<R?> Function(A) task, A argument) {
    cancel();
    final operation = _Operation<A, R>(task, argument);
    _active = operation;
    operation.start();
    return operation.result.whenComplete(() {
      if (identical(_active, operation)) _active = null;
    });
  }

  void cancel() {
    _active?.cancel();
    _active = null;
  }
}

abstract class _OperationBase {
  void cancel();
}

class _Work<A, R> {
  _Work(this.task, this.argument, this.reply);
  final Future<R?> Function(A) task;
  final A argument;
  final SendPort reply;
}

Future<void> _runWorker<A, R>(_Work<A, R> work) async {
  try {
    final result = await work.task(work.argument);
    work.reply.send([0, result]);
  } catch (error, stack) {
    work.reply.send([1, error.toString(), stack.toString()]);
  }
}

class _Operation<A, R> implements _OperationBase {
  _Operation(this.task, this.argument);
  final Future<R?> Function(A) task;
  final A argument;
  final _result = Completer<R?>();
  final _port = ReceivePort();
  Isolate? _worker;
  bool _done = false;

  Future<R?> get result => _result.future;

  void start() {
    _port.listen((Object? message) {
      if (_done) return;
      if (message is List && message.length == 2 && message[0] == 0) {
        _finish(message[1] as R?);
      } else if (message is List) {
        final explicit = message.length == 3 && message[0] == 1;
        final error = explicit ? message[1] : (message.isNotEmpty ? message[0] : 'Key search worker failed');
        final stack = explicit ? message[2] : (message.length > 1 ? message[1] : '');
        _fail(StateError('$error'), StackTrace.fromString('$stack'));
      } else {
        _fail(StateError('Key search worker exited before replying'), StackTrace.current);
      }
    });
    unawaited(_spawn());
  }

  Future<void> _spawn() async {
    try {
      final worker = await Isolate.spawn<_Work<A, R>>(
        _runWorker<A, R>, _Work(task, argument, _port.sendPort),
        onError: _port.sendPort, onExit: _port.sendPort, errorsAreFatal: true,
      );
      if (_done) {
        worker.kill(priority: Isolate.immediate);
      } else {
        _worker = worker;
      }
    } catch (error, stack) {
      if (!_done) _fail(error, stack);
    }
  }

  void _cleanUp() {
    _done = true;
    _port.close();
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
  }

  void _finish(R? value) {
    if (_done) return;
    _cleanUp();
    _result.complete(value);
  }

  void _fail(Object error, StackTrace stack) {
    if (_done) return;
    _cleanUp();
    _result.completeError(error, stack);
  }

  @override
  void cancel() => _finish(null);
}
