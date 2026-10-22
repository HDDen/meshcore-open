/// Строка вычисляется при первом чтении; после успеха callback освобождается.
class DeferredLogDescription {
  DeferredLogDescription.eager(String value) : _value = value;
  DeferredLogDescription.lazy(String Function() build) : _build = build;

  String? _value;
  String Function()? _build;

  bool get isResolved => _value != null;

  String get value {
    final cached = _value;
    if (cached != null) return cached;
    final result = _build!();
    _value = result;
    _build = null;
    return result;
  }
}
