import '../models/app_settings.dart';
import 'mcoa_theme_options.dart';

/// Apply on explicit activation, never continuously while the theme is active.
AppSettings applyMcoaThemePreferences(AppSettings settings, McoaThemeOptions options) =>
    settings.copyWith(
      uiScale: options.uiScalePercent == null ? null : options.uiScalePercent! / 100,
      senderNameScalePercent: options.senderNameScalePercent,
      simplifiedMentions: options.simplifiedMentions,
      hideChannelIndexIndicator: options.showChannelIndices == null
          ? null : !options.showChannelIndices!,
    );
