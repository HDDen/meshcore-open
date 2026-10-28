/// Общие активные XX| tags app CLI services одного connector. Префиксный ответ
/// старой консоли не должен завершать запрос другого management-экрана.
class RepeaterCliPrefixPool {
  static final _pools = Expando<RepeaterCliPrefixPool>();
  factory RepeaterCliPrefixPool.forConnector(Object connector) =>
      _pools[connector] ??= RepeaterCliPrefixPool._();
  RepeaterCliPrefixPool._();

  int _counter = 0;
  final _owners = <String, Object>{};
  String _token(int value) => '${value.toRadixString(16).padLeft(2, '0').toUpperCase()}|';

  String peek() {
    for (var i = 0; i < 256; i++) {
      final token = _token((_counter + i) & 0xff);
      if (!_owners.containsKey(token)) { return token; }
    }
    throw StateError('All repeater CLI request identifiers are in use');
  }

  String allocate(Object owner) {
    final token = peek();
    _counter = int.parse(token.substring(0, 2), radix: 16) + 1;
    _owners[token] = owner;
    return token;
  }

  void release(String token, Object owner) {
    if (identical(_owners[token], owner)) { _owners.remove(token); }
  }
}
