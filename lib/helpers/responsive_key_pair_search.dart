import 'dart:async';

/// Crypto futures may finish as microtasks. A chain of them must explicitly
/// yield to event processing so pointer events and Flutter frames can run.
/// The clock is monotonic; generating one candidate is the only indivisible
/// unit, and key generation/matching themselves remain unchanged.
Future<T?> responsiveKeyPairSearch<T>({
  required Future<T> Function() generate,
  required bool Function(T) matches,
  required int maxMilliseconds,
  bool Function()? isCancelled,
  bool yieldToEvents = true,
}) async {
  bool cancelled() => isCancelled?.call() ?? false;
  if (maxMilliseconds <= 0 || cancelled()) return null;
  if (yieldToEvents) await Future<void>.delayed(const Duration(milliseconds: 1));
  final total = Stopwatch()..start();
  final slice = Stopwatch()..start();
  while (!cancelled() && total.elapsedMilliseconds < maxMilliseconds) {
    final candidate = await generate();
    if (cancelled()) return null;
    if (matches(candidate)) return candidate;
    if (yieldToEvents && slice.elapsedMilliseconds >= 4) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      slice.reset();
    }
  }
  return null;
}
