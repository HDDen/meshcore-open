import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton wrapper for SharedPreferences to avoid redundant getInstance() calls.
///
/// BEFORE: Every storage operation called SharedPreferences.getInstance()
/// AFTER: Single getInstance() on app startup, reused throughout lifecycle
///
/// This eliminates 30+ redundant platform channel calls across the app.
class PrefsManager {
  PrefsManager._();

  static SharedPreferences? _instance;

  /// Initialize the cached instance. Call this once during app startup in main().
  static Future<void> initialize() async {
    if (_instance != null) return;
    if (Platform.isWindows) {
      await _quarantineCorruptWindowsPreferences();
    }
    _instance = await SharedPreferences.getInstance();
  }

  static Future<bool> _quarantineCorruptWindowsPreferences() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final preferencesFile = File(
      '${supportDirectory.path}${Platform.pathSeparator}shared_preferences.json',
    );
    if (!await preferencesFile.exists()) return false;

    final contents = await preferencesFile.readAsString();
    if (contents.isEmpty) return false;
    try {
      jsonDecode(contents);
      return false;
    } on FormatException {
      // Quarantine below, before SharedPreferences creates its static cache.
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    await preferencesFile.rename('${preferencesFile.path}.corrupt-$timestamp');
    return true;
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
