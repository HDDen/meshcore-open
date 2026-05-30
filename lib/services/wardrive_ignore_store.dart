import '../storage/prefs_manager.dart';

class WardriveIgnoreStore {
  static const String _ignoredRepeatersKey = 'wardrive_ignored_repeaters_v1';

  Set<String> loadIgnoredRepeaters() {
    return (PrefsManager.instance.getStringList(_ignoredRepeatersKey) ??
            const <String>[])
        .map(normalizeKey)
        .where((key) => key.isNotEmpty)
        .toSet();
  }

  Future<void> setIgnoredRepeater(String publicKeyHex, bool ignored) async {
    final key = normalizeKey(publicKeyHex);
    if (key.isEmpty) return;

    final ignoredKeys = loadIgnoredRepeaters();
    if (ignored) {
      ignoredKeys.add(key);
    } else {
      ignoredKeys.remove(key);
    }
    await PrefsManager.instance.setStringList(
      _ignoredRepeatersKey,
      ignoredKeys.toList()..sort(),
    );
  }

  static String normalizeKey(String key) {
    return key.trim().toUpperCase();
  }

  static bool containsMatchingKey(Set<String> keys, String publicKeyHex) {
    final key = normalizeKey(publicKeyHex);
    if (key.isEmpty) return false;
    return keys.any((ignoredKey) => keysMatch(ignoredKey, key));
  }

  static bool keysMatch(String first, String second) {
    final firstKey = normalizeKey(first);
    final secondKey = normalizeKey(second);
    if (firstKey.isEmpty || secondKey.isEmpty) return false;
    if (firstKey == secondKey) return true;
    final shortest = firstKey.length < secondKey.length
        ? firstKey.length
        : secondKey.length;
    if (shortest < 8) return false;
    return firstKey.startsWith(secondKey) || secondKey.startsWith(firstKey);
  }
}
