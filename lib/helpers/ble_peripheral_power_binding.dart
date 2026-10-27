import '../services/app_settings_service.dart';

/// Передаёт выбранную рекомендацию адаптеру для следующих подключений.
class BlePeripheralPowerBinding {
  BlePeripheralPowerBinding({
    required this.settings,
    required this.apply,
  }) {
    settings.addListener(_sync);
    _sync();
  }

  final AppSettingsService settings;
  final void Function(String mode) apply;
  String? _last;

  void _sync() {
    final next = settings.settings.powerSaving.effective.blePeripheralLatency.name;
    if (next == _last) {
      return;
    }
    _last = next;
    apply(next);
  }

  void dispose() => settings.removeListener(_sync);
}
