import 'dart:convert';
import 'dart:typed_data';

import '../helpers/mcoimg_codec.dart';
import '../models/mco_image_gallery_item.dart';
import '../widgets/mco_image_message.dart';
import 'prefs_manager.dart';

class MCOImageGalleryStore {
  static const String _key = 'mco_image_gallery_items';

  Future<List<MCOImageGalleryItem>> loadItems() async {
    final jsonString = PrefsManager.instance.getString(_key);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      final items = <MCOImageGalleryItem>[];
      for (final entry in jsonList) {
        if (entry is! Map<String, dynamic>) continue;
        final item = _fromJson(entry);
        if (item != null) items.add(item);
      }
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveItems(List<MCOImageGalleryItem> items) async {
    final jsonList = items.map(_toJson).toList();
    await PrefsManager.instance.setString(_key, jsonEncode(jsonList));
  }

  Future<MCOImageGalleryItem> createFromText(String text) async {
    final trimmed = text.trimLeft();
    final binaryPayload = MCOImageCodec.binaryPayloadFromText(trimmed);
    final image = MCOImageCodec().decode(
      MCOImageCodec.textFromBinaryPayload(binaryPayload),
    );
    final pngBytes = await MCOImageMessage.renderPngBytes(image, cellSize: 1);
    final now = DateTime.now();
    return MCOImageGalleryItem(
      id: '${now.microsecondsSinceEpoch}',
      createdAt: now,
      binaryPayload: binaryPayload,
      pngBytes: pngBytes,
      width: image.width,
      height: image.height,
      byteLength: binaryPayload.length,
      usedColorCount: image.pixels.toSet().length,
      paletteProfile: image.paletteProfile,
    );
  }

  Future<void> addFromText(String text) async {
    final item = await createFromText(text);
    final items = await loadItems();
    final duplicateIndex = items.indexWhere(
      (entry) => _samePayload(entry.binaryPayload, item.binaryPayload),
    );
    if (duplicateIndex >= 0) {
      items[duplicateIndex] = item.copyWith(
        showPngFallback: items[duplicateIndex].showPngFallback,
      );
    } else {
      items.insert(0, item);
    }
    await saveItems(items);
  }

  Map<String, dynamic> _toJson(MCOImageGalleryItem item) {
    return {
      'id': item.id,
      'createdAt': item.createdAt.millisecondsSinceEpoch,
      'binaryPayload': base64Encode(item.binaryPayload),
      'pngBytes': base64Encode(item.pngBytes),
      'width': item.width,
      'height': item.height,
      'byteLength': item.byteLength,
      'usedColorCount': item.usedColorCount,
      'paletteProfile': item.paletteProfile.name,
      'showPngFallback': item.showPngFallback,
    };
  }

  MCOImageGalleryItem? _fromJson(Map<String, dynamic> json) {
    try {
      final profileName = json['paletteProfile'] as String? ?? '';
      final profile = PaletteProfile.values.firstWhere(
        (entry) => entry.name == profileName,
        orElse: () => PaletteProfile.master64,
      );
      final binaryPayload = Uint8List.fromList(
        base64Decode(json['binaryPayload'] as String),
      );
      final pngBytes = Uint8List.fromList(
        base64Decode(json['pngBytes'] as String),
      );
      return MCOImageGalleryItem(
        id: json['id'] as String? ?? '${json['createdAt'] ?? 0}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          json['createdAt'] as int? ?? 0,
        ),
        binaryPayload: binaryPayload,
        pngBytes: pngBytes,
        width: json['width'] as int? ?? 0,
        height: json['height'] as int? ?? 0,
        byteLength: json['byteLength'] as int? ?? binaryPayload.length,
        usedColorCount: json['usedColorCount'] as int? ?? 0,
        paletteProfile: profile,
        showPngFallback: json['showPngFallback'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  bool _samePayload(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}
