import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_filtered_row_grouping.dart';

typedef _Row = ({String id, bool filtered, int day, bool unreadAnchor});

_Row _row(String id, {bool filtered = true, int day = 2, bool unread = false}) =>
    (id: id, filtered: filtered, day: day, unreadAnchor: unread);

List<_Row> _group(List<_Row> rows) => groupAdjacentFilteredRows(
  rows,
  isFiltered: (row) => row.filtered,
  canJoin: (newer, older) => newer.day == older.day && !newer.unreadAnchor,
  buildGroup: (members) => _row(members.map((row) => row.id).join('+')),
);

void main() {
  test('groups runs in display order and stops at visible rows', () {
    final rows = [
      _row('7'),
      _row('6'),
      _row('image', filtered: false),
      _row('5'),
      _row('visible', filtered: false),
      _row('4'),
      _row('3'),
    ];
    expect(
      _group(rows).map((row) => row.id),
      ['7+6', 'image', '5', 'visible', '4+3'],
    );
    expect(rows, hasLength(7));
  });

  test('keeps day and unread boundaries between filtered runs', () {
    final rows = [
      _row('6'),
      _row('5', unread: true),
      _row('4'),
      _row('3', day: 1),
      _row('2', day: 1),
    ];
    expect(_group(rows).map((row) => row.id), ['6+5', '4', '3+2']);
  });

  test('reuses the original list when there is nothing to group', () {
    final rows = [_row('visible', filtered: false), _row('single')];
    expect(_group(rows), same(rows));
    final empty = <_Row>[];
    expect(_group(empty), same(empty));
  });
}
