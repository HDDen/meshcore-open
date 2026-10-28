/// DEVICE_INFO содержит отдельно код протокола и строку версии прошивки.
/// Не угадываем поддержку по одному коду: форки могут использовать его раньше.
final _firmwareVersion = RegExp(
  r'^v?(\d+)\.(\d+)(?:\.(\d+))?(?:[-+_ ].*)?$',
  caseSensitive: false,
);

bool supportsCompanionCliFirmware({
  required int? protocolCode,
  required String? version,
}) {
  if (protocolCode == null || protocolCode < 14 || version == null) {
    return false;
  }
  final match = _firmwareVersion.firstMatch(version.trim());
  if (match == null) {
    return false;
  }
  final major = int.tryParse(match.group(1)!);
  final minor = int.tryParse(match.group(2)!);
  if (major == null || minor == null) {
    return false;
  }
  return major > 1 || (major == 1 && minor >= 18);
}
