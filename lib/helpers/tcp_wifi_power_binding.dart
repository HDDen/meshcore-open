import '../services/app_settings_service.dart';

/// Смена профиля меняет разрешение, не создавая нового владельца транспорта.
class TcpWifiPowerBinding {
  TcpWifiPowerBinding({required this.settings, required this.apply}) {
    settings.addListener(_sync);
    _sync();
  }

  final AppSettingsService settings;
  final void Function(bool releaseAllowed) apply;
  bool? _last;

  void _sync() {
    final next = settings.settings.powerSaving.effective.releaseTcpWifiLock;
    if (_last == next) {
      return;
    }
    _last = next;
    apply(next);
  }

  void dispose() => settings.removeListener(_sync);
}
