import '../services/app_settings_service.dart';
import '../services/ble_debug_log_service.dart';

/// Применяет профиль только к новым записям; существующий журнал не перестраивает.
class BleLogPowerSettings {
  BleLogPowerSettings({required this.log, required this.settings}) {
    settings.addListener(_sync);
    _sync();
  }

  final BleDebugLogService log;
  final AppSettingsService settings;
  bool _disposed = false;

  void _sync() {
    if (_disposed) return;
    log.setDeferDescriptions(settings.settings.powerSaving.effective.deferBleLogDescriptions);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    settings.removeListener(_sync);
  }
}
