import '../services/app_settings_service.dart';
import '../storage/legacy_key_migration.dart';
import '../storage/prefs_manager.dart';
import 'review_radio.dart';

/// Muted channel names as they were when review mode started. Persisted so an
/// interrupted session (crash, app killed) is still undone on the next launch.
const _savedMutedChannelsKey = 'review_mode_saved_muted_channels';

/// Deletes every persisted per-radio preference written while review mode was
/// active. All per-radio stores (contacts, channels, messages, unread counts,
/// channel/contact settings, regions, discovery cache, path history, ...) embed
/// the first 10 hex characters of the radio's public key in their key, so the
/// simulated radio's fixed prefix identifies exactly its data and nothing else.
Future<void> clearReviewModeData() async {
  final prefs = PrefsManager.instance;
  final prefix = ReviewRadio.storagePrefix;
  final keys = prefs.getKeys().where((key) => key.contains(prefix)).toList();
  for (final key in keys) {
    await prefs.remove(key);
  }
}

/// Starts a review session from a clean slate.
///
/// The simulated radio's scope never adopts legacy unscoped keys, so real
/// radio data cannot be pulled into it. Channel mutes are app-wide and keyed
/// by channel name (muting the simulated "Public" would mute the real one),
/// so the current mutes are saved for [endReviewModeSession] to put back.
Future<void> beginReviewModeSession(AppSettingsService? settings) async {
  scopesWithoutLegacyMigration.add(ReviewRadio.storagePrefix);
  await clearReviewModeData();
  final prefs = PrefsManager.instance;
  // An earlier interrupted session's record holds the real pre-review state.
  if (settings != null && !prefs.containsKey(_savedMutedChannelsKey)) {
    await prefs.setStringList(
      _savedMutedChannelsKey,
      settings.settings.mutedChannels.toList(),
    );
  }
}

/// Deletes the review session's data and restores the channel mutes saved by
/// [beginReviewModeSession]. Also called at startup to finish a session that
/// was interrupted; it does nothing when no session was left behind.
Future<void> endReviewModeSession(AppSettingsService? settings) async {
  await clearReviewModeData();
  final prefs = PrefsManager.instance;
  final savedMutes = prefs.getStringList(_savedMutedChannelsKey);
  if (savedMutes == null || settings == null) return;
  await settings.updateSettings(
    settings.settings.copyWith(mutedChannels: savedMutes.toSet()),
  );
  await prefs.remove(_savedMutedChannelsKey);
}
