/// Groups runs in display order and keeps the original list if none exist.
List<T> groupAdjacentFilteredRows<T>(
  List<T> rows, {
  required bool Function(T row) isFiltered,
  required bool Function(T newer, T older) canJoin,
  required T Function(List<T> members) buildGroup,
}) {
  List<T>? grouped;
  var index = 0;
  while (index < rows.length) {
    final start = index++;
    if (index < rows.length && isFiltered(rows[start])) {
      while (index < rows.length &&
          isFiltered(rows[index]) &&
          canJoin(rows[index - 1], rows[index])) {
        index++;
      }
    }
    if (index - start > 1) {
      grouped ??= rows.sublist(0, start);
      grouped.add(buildGroup(rows.sublist(start, index)));
    } else {
      grouped?.add(rows[start]);
    }
  }
  return grouped ?? rows;
}
