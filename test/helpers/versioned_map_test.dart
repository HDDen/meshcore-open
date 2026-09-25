import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/versioned_map.dart';

void main() {
  group('VersionedMap', () {
    test('holds what a plain map holds', () {
      final map = VersionedMap<String, int>()..addAll({'a': 1, 'b': 2});
      map['c'] = 3;
      map.remove('a');
      map.update('b', (value) => value + 10);
      expect(map, {'b': 12, 'c': 3});
      expect(map.containsKey('c'), isTrue);
      expect(map.containsKey('a'), isFalse);
    });

    test('moves its version on every write', () {
      final map = VersionedMap<String, int>();
      var last = map.version;
      void expectMoved() {
        expect(map.version, greaterThan(last));
        last = map.version;
      }

      map['a'] = 1;
      expectMoved();
      // Storing the same value again still counts as a write.
      map['a'] = 1;
      expectMoved();
      map.addAll({'b': 2});
      expectMoved();
      map.putIfAbsent('c', () => 3);
      expectMoved();
      map.update('a', (value) => value + 1);
      expectMoved();
      map.remove('b');
      expectMoved();
      map.removeWhere((key, value) => key == 'c');
      expectMoved();
      map.clear();
      expectMoved();
    });

    test('leaves its version alone on reads', () {
      final map = VersionedMap<String, int>()..addAll({'a': 1});
      final version = map.version;
      expect(map['a'], 1);
      expect(map.containsKey('a'), isTrue);
      expect(map.putIfAbsent('a', () => 5), 1);
      expect(map.length, 1);
      expect(Map<String, int>.from(map), {'a': 1});
      expect(map.version, version);
    });
  });
}
