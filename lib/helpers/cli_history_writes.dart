/// Один порядок SQL-записей/очистки и ревизия каждого адреса истории. Старый
/// async callback не восстанавливает удалённое, даже после повторного открытия UI.
class CliHistoryWrites {
  static Future<void>? _tail;
  static final _revisions = <String, int>{};
  static int revision(String scope) => _revisions[scope] ?? 0;

  static Future<T> ordered<T>(Future<T> Function() operation) {
    final previous = _tail;
    final next = previous == null
        ? Future<T>.microtask(operation)
        : previous.then((_) => operation());
    late final Future<void> settled;
    void releaseIdleTail() {
      // Завершённый Future сохраняет свою Zone. Не переносим её в следующую
      // независимую сессию; незавершённую цепочку при этом не сбрасываем.
      if (identical(_tail, settled)) {
        _tail = null;
      }
    }
    settled = next.then<void>((_) => releaseIdleTail(),
      onError: (Object _, StackTrace stack) => releaseIdleTail());
    _tail = settled;
    return next;
  }

  static Future<bool> save(String scope, int expected, Future<void> Function() operation) =>
      ordered(() async {
        if (revision(scope) != expected) {
          return false;
        }
        await operation();
        return true;
      });

  static Future<void> clear(String scope, Future<void> Function() operation) =>
      ordered(() async {
        await operation();
        _revisions[scope] = revision(scope) + 1;
      });
}
