import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What [PrefsManager.prepareDesktopPreferencesFile] found and did.
enum PreferencesFileRepair {
  /// No file, or an empty one with no copy to restore: the plugin starts
  /// with nothing.
  absent,

  /// The file decodes and a fresh copy of it was taken.
  backedUp,

  /// The file did not decode; it was set aside and the copy put in its place.
  restored,

  /// The file did not decode and there was no copy that does; it was set
  /// aside and the plugin starts with nothing.
  quarantined,
}

/// Singleton wrapper for SharedPreferences to avoid redundant getInstance() calls.
///
/// BEFORE: Every storage operation called SharedPreferences.getInstance()
/// AFTER: Single getInstance() on app startup, reused throughout lifecycle
///
/// This eliminates 30+ redundant platform channel calls across the app.
class PrefsManager {
  PrefsManager._();

  static const String fileName = 'shared_preferences.json';
  static const String backupSuffix = '.bak';

  static SharedPreferences? _instance;

  /// Initialize the cached instance. Call this once during app startup in main().
  static Future<void> initialize() async {
    if (_instance != null) return;
    if (Platform.isWindows || Platform.isLinux) {
      try {
        await prepareDesktopPreferencesFile(
          await getApplicationSupportDirectory(),
        );
      } on MissingPluginException {
        // No path_provider in this process (a unit test): there is no file
        // to look at, and the mock preferences need no repair.
      }
    }
    _instance = await SharedPreferences.getInstance();
  }

  /// On Windows and Linux the plugin keeps the preferences in one JSON file
  /// that it rewrites whole, and not atomically, on every change, so a
  /// launch that ends during a write leaves a cut file, and the plugin then
  /// throws on it. This runs before the plugin opens the file. A file that
  /// decodes is copied to `.bak`, through a temporary file so that the copy
  /// is never cut either. A file that does not decode is set aside as
  /// `.corrupt-<time>`, before the plugin creates its static cache, and the
  /// copy takes its place when it decodes: what is lost is then the changes
  /// since the last launch, not everything. An empty file, a write cut at
  /// its start, is restored the same way and otherwise left to the plugin,
  /// which reads it as nothing.
  static Future<PreferencesFileRepair> prepareDesktopPreferencesFile(
    Directory supportDirectory,
  ) async {
    final file = File(
      '${supportDirectory.path}${Platform.pathSeparator}$fileName',
    );
    final backup = File('${file.path}$backupSuffix');
    if (!await file.exists()) return PreferencesFileRepair.absent;

    final contents = await file.readAsString();
    if (_decodes(contents)) {
      final temporary = File('${backup.path}.tmp');
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(backup.path);
      return PreferencesFileRepair.backedUp;
    }

    String? saved;
    if (await backup.exists()) {
      saved = await backup.readAsString();
      if (!_decodes(saved)) saved = null;
    }
    if (contents.isEmpty && saved == null) return PreferencesFileRepair.absent;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    await file.rename('${file.path}.corrupt-$timestamp');
    if (saved == null) return PreferencesFileRepair.quarantined;
    await backup.copy(file.path);
    return PreferencesFileRepair.restored;
  }

  /// Whether the plugin would read [contents] as its map.
  static bool _decodes(String contents) {
    if (contents.isEmpty) return false;
    try {
      return jsonDecode(contents) is Map;
    } on FormatException {
      return false;
    }
  }

  /// Get the cached SharedPreferences instance.
  /// Throws StateError if initialize() hasn't been called.
  static SharedPreferences get instance {
    if (_instance == null) {
      throw StateError(
        'PrefsManager not initialized. Call PrefsManager.initialize() in main() before use.',
      );
    }
    return _instance!;
  }

  /// For testing: reset the instance
  static void reset() {
    _instance = null;
  }
}
