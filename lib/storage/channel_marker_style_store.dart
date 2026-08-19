import 'dart:convert';

import '../models/channel_marker_style.dart';
import '../utils/app_logger.dart';
import 'prefs_manager.dart';

/// Per-channel marker appearance, kept as one JSON blob per node.
///
/// Keyed by channel name rather than index: indexes shift when channels are
/// added or removed, while the name is also what shared history matches
/// across nodes. Reads are synchronous because the map asks for a style while
/// building every marker.
class ChannelMarkerStyleStore {
  static const String _keyPrefix = 'channel_marker_styles_';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length >= 10 ? value.substring(0, 10) : '';

  String get keyFor => '$_keyPrefix$publicKeyHex';

  static String normalizeChannelName(String name) => name.trim().toLowerCase();

  Map<String, ChannelMarkerStyle> load() {
    if (publicKeyHex.isEmpty) return const {};
    final raw = PrefsManager.instance.getString(keyFor);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          entry.key: ChannelMarkerStyle.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      };
    } catch (e) {
      appLogger.warn('Failed to read channel marker styles: $e');
      return const {};
    }
  }

  Future<void> save(Map<String, ChannelMarkerStyle> styles) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot save marker styles.');
      return;
    }
    if (styles.isEmpty) {
      await PrefsManager.instance.remove(keyFor);
      return;
    }
    final persisted = <String, dynamic>{
      for (final entry in styles.entries) entry.key: entry.value.toJson(),
    };
    await PrefsManager.instance.setString(keyFor, jsonEncode(persisted));
  }
}
