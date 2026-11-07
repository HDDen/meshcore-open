import 'dart:convert';
import 'dart:typed_data';

import '../helpers/theme_media.dart';
import '../storage/prefs_manager.dart';
import 'chat_background_image_store_base.dart';

ChatBackgroundImageStore createChatBackgroundImageStore() =>
    _PrefsChatBackgroundImageStore();

/// Web: pictures are base64 in preferences (browser local storage). They are
/// small JPEG XL files, so a handful fit comfortably in the storage quota.
class _PrefsChatBackgroundImageStore implements ChatBackgroundImageStore {
  static const _prefix = 'chat_bg_image_';

  @override
  Future<void> write(String id, Uint8List bytes) async {
    if (!isStoredThemeImageId(id)) throw ArgumentError('Invalid background ID');
    final saved = await PrefsManager.instance.setString('$_prefix$id', base64Encode(bytes));
    if (!saved) throw StateError('Could not save chat picture');
  }

  @override
  Future<Uint8List?> read(String id) async {
    if (!isStoredThemeImageId(id)) return null;
    final value = normalizeThemeImageData(
      PrefsManager.instance.getString('$_prefix$id'),
      maxBytes: maxThemeBackgroundBytes,
    );
    return value == null ? null : base64Decode(value);
  }

  @override
  Future<void> delete(String id) async {
    if (isStoredThemeImageId(id)) await PrefsManager.instance.remove('$_prefix$id');
  }

  @override
  Future<Set<String>> listIds() async => PrefsManager.instance
      .getKeys()
      .where((k) => k.startsWith(_prefix))
      .map((k) => k.substring(_prefix.length))
      .where(isStoredThemeImageId)
      .toSet();
}
