import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../helpers/channel_app_data_helper.dart';
import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_v3_codec.dart';
import '../models/mco_image_gallery_item.dart';
import '../widgets/mco_image_message.dart';
import 'prefs_manager.dart';

class MCOImageGalleryStore {
  static const String _key = 'mco_image_gallery_items';
  static const String _collapsedGroupsKey =
      'mco_image_gallery_collapsed_groups';

  Future<List<MCOImageGalleryItem>> loadItems() async {
    final jsonString = PrefsManager.instance.getString(_key);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      final items = <MCOImageGalleryItem>[];
      var migrated = false;
      for (final entry in jsonList) {
        if (entry is! Map<String, dynamic>) continue;
        final rawGroupId = entry['groupId'];
        if (rawGroupId is! String || rawGroupId.trim().isEmpty) {
          migrated = true;
        }
        final item = _fromJson(entry);
        if (item != null) items.add(item);
      }
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (migrated) {
        unawaited(saveItems(items));
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveItems(List<MCOImageGalleryItem> items) async {
    final jsonList = items.map(_toJson).toList();
    await PrefsManager.instance.setString(_key, jsonEncode(jsonList));
  }

  Future<Set<String>> loadCollapsedGroupIds() async {
    final jsonString = PrefsManager.instance.getString(_collapsedGroupsKey);
    if (jsonString == null || jsonString.isEmpty) return {};
    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList
          .whereType<String>()
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCollapsedGroupIds(Set<String> groupIds) async {
    final jsonList = groupIds
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList()
      ..sort();
    await PrefsManager.instance.setString(
      _collapsedGroupsKey,
      jsonEncode(jsonList),
    );
  }

  Future<MCOImageGalleryItem> createFromText(String text) async {
    final trimmed = text.trimLeft();
    final isV3 = MCOImageV3Codec.isTextPayload(trimmed);
    final binaryPayload = isV3
        ? MCOImageV3Codec.appPayloadWithoutSenderFromText(trimmed)
        : MCOImageCodec.binaryPayloadFromText(trimmed);
    final image = isV3
        ? MCOImageV3Codec().decodeAppPayloadWithoutSender(binaryPayload)
        : MCOImageCodec().decode(
            MCOImageCodec.textFromBinaryPayload(binaryPayload),
          );
    final payloadInfo = isV3
        ? null
        : MCOImageCodec.inspectPayload(
            MCOImageCodec.textFromBinaryPayload(binaryPayload),
          );
    final pngBytes = await MCOImageMessage.renderPngBytes(image, cellSize: 1);
    final now = DateTime.now();
    return MCOImageGalleryItem(
      id: '${now.microsecondsSinceEpoch}',
      createdAt: now,
      groupId: MCOImageGalleryItem.commonGroupId,
      binaryPayload: binaryPayload,
      pngBytes: pngBytes,
      width: image.width,
      height: image.height,
      byteLength: binaryPayload.length,
      usedColorCount: image.pixels.toSet().length,
      codecVersion: isV3
          ? ChannelAppDataHelper.mcoImageV3Version
          : payloadInfo?.version ?? _codecVersionForImage(image),
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
        groupId: MCOImageGalleryItem.commonGroupId,
        clearGroupName: true,
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
      'groupId': item.groupId,
      if (item.groupName != null && item.groupName!.isNotEmpty)
        'groupName': item.groupName,
      'binaryPayload': base64Encode(item.binaryPayload),
      'pngBytes': base64Encode(item.pngBytes),
      'width': item.width,
      'height': item.height,
      'byteLength': item.byteLength,
      'usedColorCount': item.usedColorCount,
      'codecVersion': item.codecVersion,
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
      final codecVersion =
          json['codecVersion'] as int? ??
          _v3CodecVersionForPayload(binaryPayload) ??
          MCOImageCodec.inspectPayload(
            MCOImageCodec.textFromBinaryPayload(binaryPayload),
          )?.version ??
          1;
      final rawGroupId = json['groupId'];
      final rawGroupName = json['groupName'];
      final groupId = rawGroupId is String && rawGroupId.trim().isNotEmpty
          ? rawGroupId.trim()
          : MCOImageGalleryItem.commonGroupId;
      final groupName = rawGroupName is String && rawGroupName.trim().isNotEmpty
          ? rawGroupName.trim()
          : null;
      return MCOImageGalleryItem(
        id: json['id'] as String? ?? '${json['createdAt'] ?? 0}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          json['createdAt'] as int? ?? 0,
        ),
        groupId: groupId,
        groupName: groupName,
        binaryPayload: binaryPayload,
        pngBytes: pngBytes,
        width: json['width'] as int? ?? 0,
        height: json['height'] as int? ?? 0,
        byteLength: json['byteLength'] as int? ?? binaryPayload.length,
        usedColorCount: json['usedColorCount'] as int? ?? 0,
        codecVersion: codecVersion,
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

  int _codecVersionForImage(MCOImage image) {
    return switch (image.encodingVersion) {
      MCOImageEncodingVersion.v1Legacy => 1,
      MCOImageEncodingVersion.v2 => 2,
      MCOImageEncodingVersion.v3 => ChannelAppDataHelper.mcoImageV3Version,
    };
  }

  int? _v3CodecVersionForPayload(Uint8List payload) {
    final appPayload = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
      payload,
    );
    if (appPayload?.subtypeVersion !=
        ChannelAppDataHelper.mcoImageV3SubtypeVersion) {
      return null;
    }
    return ChannelAppDataHelper.mcoImageV3Version;
  }
}
