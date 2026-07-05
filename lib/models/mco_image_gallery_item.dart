import 'dart:typed_data';

import '../helpers/channel_app_data_helper.dart';
import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_v3_codec.dart';

class MCOImageGalleryItem {
  static const String commonGroupId = 'common';

  final String id;
  final DateTime createdAt;
  final String groupId;
  final String? groupName;
  final Uint8List binaryPayload;
  final Uint8List pngBytes;
  final int width;
  final int height;
  final int byteLength;
  final int usedColorCount;
  final int codecVersion;
  final PaletteProfile paletteProfile;
  final bool showPngFallback;

  const MCOImageGalleryItem({
    required this.id,
    required this.createdAt,
    this.groupId = commonGroupId,
    this.groupName,
    required this.binaryPayload,
    required this.pngBytes,
    required this.width,
    required this.height,
    required this.byteLength,
    required this.usedColorCount,
    required this.codecVersion,
    required this.paletteProfile,
    this.showPngFallback = false,
  });

  MCOImageGalleryItem copyWith({
    String? groupId,
    String? groupName,
    bool clearGroupName = false,
    bool? showPngFallback,
  }) {
    return MCOImageGalleryItem(
      id: id,
      createdAt: createdAt,
      groupId: groupId ?? this.groupId,
      groupName: clearGroupName ? null : (groupName ?? this.groupName),
      binaryPayload: binaryPayload,
      pngBytes: pngBytes,
      width: width,
      height: height,
      byteLength: byteLength,
      usedColorCount: usedColorCount,
      codecVersion: codecVersion,
      paletteProfile: paletteProfile,
      showPngFallback: showPngFallback ?? this.showPngFallback,
    );
  }

  bool get isV3 {
    if (codecVersion == ChannelAppDataHelper.mcoImageV3Version) return true;
    final appPayload = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
      binaryPayload,
    );
    return appPayload?.subtypeVersion ==
        ChannelAppDataHelper.mcoImageV3SubtypeVersion;
  }

  String get textPayload => isV3
      ? MCOImageV3Codec.textFromAppPayloadWithoutSender(binaryPayload)
      : MCOImageCodec.textFromBinaryPayload(binaryPayload);

  MCOImage? tryDecodeImage() {
    try {
      return isV3
          ? MCOImageV3Codec().decodeAppPayloadWithoutSender(binaryPayload)
          : MCOImageCodec().decode(textPayload);
    } on MCOImageCodecException {
      return null;
    }
  }
}
