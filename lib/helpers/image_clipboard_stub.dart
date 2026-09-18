import 'dart:typed_data';

/// The web build: no picture clipboard. See `image_clipboard_io.dart`.
class ImageClipboard {
  static bool get isSupported => false;

  static Future<bool> write({
    required int width,
    required int height,
    required Uint8List rgba,
    required Uint8List png,
  }) async => false;
}
