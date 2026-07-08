import 'dart:convert';
import 'dart:io';

import '../helpers/mco_image_identity.dart';
import '../storage/mco_image_gallery_store.dart';
import '../storage/prefs_manager.dart';

/// In-memory index "payload identity hash -> original image file" for the
/// installed *.mcoimg.pack sets.
///
/// The index itself is persisted by [MCOImageGalleryStore] (rebuilt on pack
/// install/remove) so packs are never rescanned on the hot path; this service
/// only loads it once and answers lookups when a received MCOimg message is
/// rendered. When the hash of an incoming image matches a pack item, the chat
/// shows the pack's original (png/jpg/gif, possibly animated) instead of the
/// degraded LoRa version.
class McoImagePackOriginals {
  McoImagePackOriginals._();

  static final McoImagePackOriginals instance = McoImagePackOriginals._();

  static const int _hashMemoLimit = 256;

  Map<String, String>? _index;
  Future<void>? _loading;
  final Map<String, String?> _hashByText = {};

  /// Replaces the in-memory index (called by [MCOImageGalleryStore] right
  /// after it rebuilds and persists the table).
  void replaceIndex(Map<String, String> index) {
    _index = Map<String, String>.from(index);
    _loading = null;
  }

  /// Resolves the pack original for a chat MCOimg text payload, or null when
  /// the image is unknown or the original file is gone (caller falls back to
  /// rendering the received LoRa version).
  Future<File?> resolveOriginalForText(String text) async {
    await _ensureLoaded();
    final index = _index;
    if (index == null || index.isEmpty) return null;

    var hash = _hashByText[text];
    if (!_hashByText.containsKey(text)) {
      hash = MCOImageIdentity.hashFromText(text);
      if (_hashByText.length >= _hashMemoLimit) {
        _hashByText.clear();
      }
      _hashByText[text] = hash;
    }
    if (hash == null) return null;

    final relativePath = index[hash];
    if (relativePath == null) return null;

    final packsDir = await MCOImageGalleryStore().packsDirectoryPath();
    final file = File(
      [packsDir, ...relativePath.split('/')].join(Platform.pathSeparator),
    );
    if (!await file.exists()) return null;
    return file;
  }

  Future<void> _ensureLoaded() {
    if (_index != null) return Future.value();
    final pending = _loading;
    if (pending != null) return pending;
    final future = _load();
    _loading = future;
    return future;
  }

  Future<void> _load() async {
    try {
      final jsonString = PrefsManager.instance.getString(
        MCOImageGalleryStore.packOriginalsIndexKey,
      );
      if (jsonString != null && jsonString.isNotEmpty) {
        final decoded = jsonDecode(jsonString);
        if (decoded is Map<String, dynamic>) {
          _index = {
            for (final entry in decoded.entries)
              if (entry.value is String) entry.key: entry.value as String,
          };
          return;
        }
      }
      // No persisted index yet (packs installed by an older build): build it
      // once from the packs on disk.
      await MCOImageGalleryStore().rebuildPackOriginalsIndex();
      _index ??= const {};
    } catch (_) {
      _index = const {};
    } finally {
      _loading = null;
    }
  }
}
