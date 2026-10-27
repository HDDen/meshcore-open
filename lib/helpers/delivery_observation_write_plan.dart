/// План изменения списка; SQLite применяет его внутри одной транзакции.
class DeliveryObservationWritePlan {
  const DeliveryObservationWritePlan({
    required this.removePrefixCount,
    required this.append,
  });

  final int removePrefixCount;
  final List<String> append;

  /// Число удаляемых/добавляемых строк, не commits/fsync или физическая запись.
  int get changedRows => removePrefixCount + append.length;
}

/// JSON-строки непрозрачны: сохраняются точные значения, порядок и дубликаты.
DeliveryObservationWritePlan planDeliveryObservationWrite(
  List<String> previous,
  List<String> next,
) {
  var retained = previous.length < next.length ? previous.length : next.length;
  while (retained > 0) {
    final start = previous.length - retained;
    var matches = true;
    for (var i = 0; i < retained; i++) {
      if (previous[start + i] != next[i]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      break;
    }
    retained--;
  }
  return DeliveryObservationWritePlan(
    removePrefixCount: previous.length - retained,
    append: List<String>.unmodifiable(next.skip(retained)),
  );
}
