import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/key_indexed_list.dart';

class _Item {
  _Item(this.key, this.tag);

  final String key;
  final int tag;
}

KeyIndexedList<_Item> _list() => KeyIndexedList<_Item>((item) => item.key);

void main() {
  group('KeyIndexedList.byKey', () {
    test('finds nothing in an empty list or under an unknown key', () {
      final list = _list();
      expect(list.byKey('a'), isNull);
      list.add(_Item('a', 1));
      expect(list.byKey('b'), isNull);
    });

    test('returns the first element under a key, as firstWhere does', () {
      final first = _Item('a', 1);
      final list = _list()..addAll([_Item('b', 2), first, _Item('a', 3)]);
      expect(list.byKey('a'), same(first));
    });

    test('follows every kind of change without a stale answer', () {
      final list = _list();
      final a1 = _Item('a', 1);
      list.add(a1);
      expect(list.byKey('a'), same(a1));

      final a2 = _Item('a', 2);
      list[0] = a2;
      expect(list.byKey('a'), same(a2));

      final b = _Item('b', 3);
      list.insert(0, b);
      expect(list.byKey('b'), same(b));

      list.removeAt(0);
      expect(list.byKey('b'), isNull);

      list.removeWhere((item) => item.key == 'a');
      expect(list.byKey('a'), isNull);

      list.addAll([_Item('c', 4), _Item('d', 5)]);
      list.length = 1;
      expect(list.byKey('c')?.tag, 4);
      expect(list.byKey('d'), isNull);

      list.clear();
      expect(list.byKey('c'), isNull);
    });

    test('a burst of changes is seen by the next lookup', () {
      final list = _list();
      for (var i = 0; i < 100; i++) {
        list.add(_Item('k$i', i));
      }
      list.sort((x, y) => y.tag.compareTo(x.tag));
      list.removeRange(0, 50);
      expect(list.byKey('k99'), isNull);
      expect(list.byKey('k49')?.tag, 49);
    });
  });

  group('KeyIndexedList.version', () {
    test('moves on every change and not on lookups', () {
      final list = _list();
      var last = list.version;
      void expectMoved() {
        expect(list.version, greaterThan(last));
        last = list.version;
      }

      list.add(_Item('a', 1));
      expectMoved();
      list[0] = _Item('a', 2);
      expectMoved();
      list.insert(0, _Item('b', 3));
      expectMoved();
      list.removeWhere((item) => item.key == 'b');
      expectMoved();
      list.clear();
      expectMoved();
      expect(list.byKey('a'), isNull);
      expect(list.version, last);
    });
  });
}
