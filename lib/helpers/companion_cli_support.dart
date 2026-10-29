/// DEVICE_INFO содержит отдельно код протокола и строку версии прошивки.
/// Не угадываем поддержку по одному коду: форки могут использовать его раньше.
final _firmwareNumberFragments = RegExp(r'[0-9]+(?:\.[0-9]+)*');

bool supportsCompanionCliFirmware({
  required int? protocolCode,
  required String? version,
}) {
  if (protocolCode == null || protocolCode < 14 || version == null) {
    return false;
  }

  // Первый проход: извлекаем числовые фрагменты независимо от имени форка,
  // префикса v и суффиксов .dev/-rc. Точки между цифрами сохраняют компоненты.
  final fragments = [
    for (final match in _firmwareNumberFragments.allMatches(version)) match.group(0)!,
  ];
  for (final fragment in fragments) {
    // Второй проход: одиночные числа (nRF52, номер сборки) не являются версией.
    final components = fragment.split('.');
    if (components.length < 2) {
      continue;
    }
    final major = int.tryParse(components[0]);
    final minor = int.tryParse(components[1]);
    if (major == null || minor == null) {
      return false;
    }
    // Это номера компонентов, не float: 1.100 новее 1.18, а 1.9 — старее.
    // Берём первый фрагмент major.minor, чтобы поздний номер сборки не мог
    // включить CLI у явно старой прошивки. Patch для порога 1.18 не нужен.
    return major > 1 || (major == 1 && minor >= 18);
  }
  return false;
}
