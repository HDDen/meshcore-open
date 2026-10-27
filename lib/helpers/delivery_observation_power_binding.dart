import '../services/app_settings_service.dart';

/// Применяет только effective-флаг, не сбрасывая сохранённый custom.
class DeliveryObservationPowerBinding {
  DeliveryObservationPowerBinding({required this.settings, required this.apply}) {
    settings.addListener(_sync);
    _sync();
  }

  final AppSettingsService settings;
  final void Function(bool enabled) apply;
  bool? _last;

  void _sync() {
    final next = settings.settings.powerSaving.effective.reduceDeliveryObservationWrites;
    if (_last == next) {
      return;
    }
    _last = next;
    apply(next);
  }

  void dispose() => settings.removeListener(_sync);
}
