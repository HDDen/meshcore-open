import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/repeater_cli_prefix_pool.dart';

void main() {
  test('services of one connector share tags, different connectors stay independent', () {
    final connector = Object();
    final a = RepeaterCliPrefixPool.forConnector(connector);
    final b = RepeaterCliPrefixPool.forConnector(connector);
    expect(identical(a, b), isTrue);
    expect(a.allocate(Object()), '00|');
    expect(b.allocate(Object()), '01|');
    expect(RepeaterCliPrefixPool.forConnector(Object()).peek(), '00|');
  });

  test('exhaustion does not reuse an active tag and old cleanup cannot release a new owner', () {
    final pool = RepeaterCliPrefixPool.forConnector(Object());
    final owner = Object();
    final token = pool.allocate(owner);
    final allocated = {token};
    for (var i = 1; i < 256; i++) {
      expect(allocated.add(pool.allocate(Object())), isTrue);
    }
    expect(pool.peek, throwsStateError);
    pool.release(token, Object());
    expect(pool.peek, throwsStateError);
    pool.release(token, owner);
    expect(pool.allocate(Object()), token);
    pool.release(token, owner);
    expect(pool.peek, throwsStateError);
  });
}
