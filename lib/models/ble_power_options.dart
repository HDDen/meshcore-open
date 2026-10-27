/// Рекомендации ОС, а не точные интервалы радиообмена.
enum BleConnectionPriorityMode { original, balanced, high, lowPower }

enum BlePeripheralLatencyMode { original, low, medium, high }

BleConnectionPriorityMode bleConnectionPriorityFromJson(Object? value) =>
    BleConnectionPriorityMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => BleConnectionPriorityMode.original,
    );

BlePeripheralLatencyMode blePeripheralLatencyFromJson(Object? value) =>
    BlePeripheralLatencyMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => BlePeripheralLatencyMode.original,
    );
