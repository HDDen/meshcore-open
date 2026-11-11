import '../l10n/app_localizations.dart';
import 'app_settings.dart';
import 'image_codec_support.dart';
import 'translation_support.dart';

/// The portable display preferences supported by the v1 backup.
class AppSettingsBackup {
  // Upstream treats appSettings as a complete replacement for its preferences.
  static const section = 'mcoaDisplaySettings';

  AppSettingsBackup.fromJson(Map<String, Object?> json)
    : values = Map.unmodifiable({
        for (final key in _booleanKeys)
          if (json[key] case final bool value) key: value,
        if (_themes.contains(json['theme_mode']))
          'theme_mode': json['theme_mode'],
        if (json.containsKey('language_override') &&
            _validLanguage(json['language_override']))
          'language_override': json['language_override'],
        if (UnitSystem.values.any((unit) => unit.value == json['unit_system']))
          'unit_system': json['unit_system'],
        if (json['ui_scale'] case final num scale when scale >= 0.5 && scale <= 2)
          'ui_scale': scale.toDouble(),
      }),
      imageCodecPreset = imageCodecPresetModels
          .where((preset) => preset.id == json['image_codec_selected_model_id'])
          .firstOrNull,
      translationPreset = translationPresetModels
          .where((preset) => preset.id == json['translation_selected_model_id'])
          .firstOrNull;

  factory AppSettingsBackup.capture(AppSettings settings) =>
      AppSettingsBackup.fromJson({
        ..._read(settings),
        'image_codec_selected_model_id': settings.imageCodecSelectedModelId,
        'translation_selected_model_id': settings.translationSelectedModelId,
      });

  final Map<String, Object?> values;
  final ImageCodecModelSpec? imageCodecPreset;
  final TranslationModelRecord? translationPreset;
  bool get isEmpty =>
      values.isEmpty && imageCodecPreset == null && translationPreset == null;

  Map<String, Object?> toJson() => {
    ...values,
    'image_codec_selected_model_id': ?imageCodecPreset?.id,
    'translation_selected_model_id': ?translationPreset?.id,
  };

  static const _themes = {'system', 'light', 'dark'};
  static const _booleanKeys = {
    'ui_scale_apply_to_icons',
    'enable_time_seconds',
    'show_keyboard_hiding_button',
    'jump_to_oldest_unread',
    'show_hops',
    'show_channel_preview_sender',
    'channels_unread_sorting',
    'monochrome_sender_names',
    'show_last_hop_signal',
    'region_on_hops_line',
  };

  static bool _validLanguage(Object? value) =>
      value == null ||
      AppLocalizations.supportedLocales.any((locale) => locale.languageCode == value);

  static Map<String, Object?> _read(AppSettings settings) => {
    'theme_mode': settings.themeMode,
    'language_override': settings.languageOverride,
    'unit_system': settings.unitSystem.value,
    'ui_scale': settings.uiScale,
    'ui_scale_apply_to_icons': settings.uiScaleApplyToIcons,
    'enable_time_seconds': settings.enableTimeSeconds,
    'show_keyboard_hiding_button': settings.showKeyboardHidingButton,
    'jump_to_oldest_unread': settings.jumpToOldestUnread,
    'show_hops': settings.showHops,
    'show_channel_preview_sender': settings.showChannelPreviewSender,
    'channels_unread_sorting': settings.channelsUnreadSorting,
    'monochrome_sender_names': settings.monochromeSenderNames,
    'show_last_hop_signal': settings.showLastHopSignal,
    'region_on_hops_line': settings.regionOnHopsLine,
  };

  AppSettingsBackupPreview preview(AppSettings settings) =>
      AppSettingsBackupPreview._(values, _read(settings));
}

class AppSettingsBackupPreview {
  AppSettingsBackupPreview._(
    Map<String, Object?> values,
    Map<String, Object?> current,
  ) : changes = Map.unmodifiable({
        for (final entry in values.entries)
          if (current[entry.key] != entry.value) entry.key: entry.value,
      }),
      _baseline = current;

  final Map<String, Object?> changes;
  final Map<String, Object?> _baseline;

  /// Rechecks the edited fields and merges them into the current profile.
  AppSettings? applyTo(AppSettings settings) {
    if (changes.isEmpty) return settings;
    final current = AppSettingsBackup._read(settings);
    if (changes.keys.any((key) => current[key] != _baseline[key])) return null;
    final units = changes['unit_system'];
    return settings.copyWith(
      themeMode: changes['theme_mode'] as String?,
      languageOverride: changes.containsKey('language_override')
          ? changes['language_override']
          : settings.languageOverride,
      unitSystem: units == null
          ? null
          : UnitSystem.values.firstWhere((unit) => unit.value == units),
      uiScale: changes['ui_scale'] as double?,
      uiScaleApplyToIcons: changes['ui_scale_apply_to_icons'] as bool?,
      enableTimeSeconds: changes['enable_time_seconds'] as bool?,
      showKeyboardHidingButton: changes['show_keyboard_hiding_button'] as bool?,
      jumpToOldestUnread: changes['jump_to_oldest_unread'] as bool?,
      showHops: changes['show_hops'] as bool?,
      showChannelPreviewSender: changes['show_channel_preview_sender'] as bool?,
      channelsUnreadSorting: changes['channels_unread_sorting'] as bool?,
      monochromeSenderNames: changes['monochrome_sender_names'] as bool?,
      showLastHopSignal: changes['show_last_hop_signal'] as bool?,
      regionOnHopsLine: changes['region_on_hops_line'] as bool?,
    );
  }
}
