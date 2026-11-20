// Web search uses the cooperative loop directly, with cancellation checks.
const supportsKeySearchIsolates = false;

class KeySearchExecutor {
  Future<R?> run<A, R>(Future<R?> Function(A) task, A argument) => task(argument);
  void cancel() {}
}
