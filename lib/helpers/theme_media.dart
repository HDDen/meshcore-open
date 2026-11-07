import 'dart:convert';

const int maxThemeIconBytes = 128 * 1024;
const int maxThemeBackgroundBytes = 2 * 1024 * 1024;
const String kThemeAssetDir = 'assets/themes/';

final _themeAssetPath = RegExp(r'^assets/themes/[a-z0-9_-]+/[a-z0-9_-]+\.jxl$');
final _storedImageId = RegExp(r'^[a-zA-Z0-9_-]{1,80}$');

/// Bundled theme images use paths within the theme asset directory.
bool isThemeAssetPath(Object? value) =>
    value is String && _themeAssetPath.hasMatch(value);

/// IDs form a single filename component in the local image store.
bool isStoredThemeImageId(Object? value) =>
    value is String && _storedImageId.hasMatch(value);

/// Validates a base64 payload and its decoded size without allocating pixels
/// or a decoded byte buffer. Used while loading theme metadata.
String? normalizeThemeImageData(Object? value, {required int maxBytes}) {
  final maxEncodedLength = ((maxBytes + 2) ~/ 3) * 4;
  if (value is! String || value.isEmpty || value.length > maxEncodedLength) {
    return null;
  }
  try {
    final normalized = base64.normalize(value);
    final padding = normalized.endsWith('==') ? 2 : (normalized.endsWith('=') ? 1 : 0);
    final decodedLength = normalized.length ~/ 4 * 3 - padding;
    if (decodedLength <= 0 || decodedLength > maxBytes) return null;
    if (padding > 0) {
      // normalize checks the alphabet and padding placement. The decoder
      // also requires the unused bits of the final digit to be zero.
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      final digit = alphabet.indexOf(normalized[normalized.length - padding - 1]);
      final unusedBits = padding == 2 ? 0x0F : 0x03;
      if (digit < 0 || (digit & unusedBits) != 0) return null;
    }
    return normalized;
  } on FormatException {
    return null;
  }
}
