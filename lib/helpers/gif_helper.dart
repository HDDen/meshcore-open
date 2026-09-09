class GifHelper {
  static final RegExp _compactPattern = RegExp(r'^g:([A-Za-z0-9_-]+)$');
  static final RegExp _directUrlPattern = RegExp(
    r'^(?:https?:\/\/)?media\.giphy\.com\/media\/([A-Za-z0-9_-]+)\/giphy\.gif$',
  );
  static final RegExp _pageUrlPattern = RegExp(
    r'^(?:https?:\/\/)?giphy\.com\/gifs\/(?:[^/?]*-)?([A-Za-z0-9_]+)\/?$',
  );

  /// Parse a known GIF format, which can be any of:
  /// g:GIFID
  /// https://media.giphy.com/media/GIFID/giphy.gif
  /// https://giphy.com/gifs/Optional-title-with-dashes-GIFID
  ///
  /// GIFID is a Giphy GIF ID. The https:// is optional (and
  /// can also be http://). The giphy.com/gifs form can also
  /// include a trailing slash.
  ///
  /// Returns null if text is not a valid GIF format
  static String? parseGif(String text) {
    final trimmed = text.trim();
    if (!_couldBeGif(trimmed)) return null;

    final match = _compactPattern.firstMatch(trimmed);
    if (match != null) {
      return match.group(1);
    }
    final directUrlMatch = _directUrlPattern.firstMatch(trimmed);
    if (directUrlMatch != null) {
      return directUrlMatch.group(1);
    }
    // Giphy understands page URLs with just the ID, or any string and a
    // dash before the ID, and redirects to a page with a dash-separated
    // title, a dash, and the ID. IDs in this form *probably* can't
    // contain dashes.
    final pageMatch = _pageUrlPattern.firstMatch(trimmed);
    return pageMatch?.group(1);
  }

  static bool _couldBeGif(String text) {
    if (text.startsWith('g:')) return true;
    final withoutScheme = text.startsWith('https://')
        ? text.substring(8)
        : text.startsWith('http://')
        ? text.substring(7)
        : text;
    return withoutScheme.startsWith('media.giphy.com/media/') ||
        withoutScheme.startsWith('giphy.com/gifs/');
  }

  /// Encode a GIF in a format that parseGif() can parse.
  static String encodeGif(String gifId) {
    return 'g:$gifId';
  }
}
