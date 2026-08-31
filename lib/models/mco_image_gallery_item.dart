import 'dart:typed_data';

import '../helpers/channel_app_data_helper.dart';
import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_v3_codec.dart';
import '../helpers/mcoimg_v4_codec.dart';
import '../helpers/mcoimg_v4_model.dart';

class MCOImageGalleryItem {
  static const String commonGroupId = 'common';

  final String id;
  final DateTime createdAt;
  final String groupId;
  final String? groupName;
  final String? packFolderName;
  final int? previewMaxSize;
  final Uint8List binaryPayload;

  /// Materialized original bytes, or empty for a lazily loaded pack item. The
  /// legacy name is kept so stored records and existing call sites remain
  /// compatible.
  final Uint8List pngBytes;
  final String originalFileName;
  final List<String> originalRelativePaths;
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
    this.packFolderName,
    this.previewMaxSize,
    required this.binaryPayload,
    required this.pngBytes,
    this.originalFileName = 'mcoimg.png',
    this.originalRelativePaths = const [],
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
    String? packFolderName,
    int? previewMaxSize,
    bool? showPngFallback,
    String? originalFileName,
    List<String>? originalRelativePaths,
    Uint8List? pngBytes,
  }) {
    return MCOImageGalleryItem(
      id: id,
      createdAt: createdAt,
      groupId: groupId ?? this.groupId,
      groupName: clearGroupName ? null : (groupName ?? this.groupName),
      packFolderName: packFolderName ?? this.packFolderName,
      previewMaxSize: previewMaxSize ?? this.previewMaxSize,
      binaryPayload: binaryPayload,
      pngBytes: pngBytes ?? this.pngBytes,
      originalFileName: originalFileName ?? this.originalFileName,
      originalRelativePaths:
          originalRelativePaths ?? this.originalRelativePaths,
      width: width,
      height: height,
      byteLength: byteLength,
      usedColorCount: usedColorCount,
      codecVersion: codecVersion,
      paletteProfile: paletteProfile,
      showPngFallback: showPngFallback ?? this.showPngFallback,
    );
  }

  bool get isPackItem => packFolderName != null && packFolderName!.isNotEmpty;

  bool get originalIsLottie {
    final lower = originalFileName.toLowerCase();
    return lower.endsWith('.lottie.json') || lower.endsWith('.lottie');
  }

  bool get isV3 {
    if (codecVersion == ChannelAppDataHelper.mcoImageV3Version) return true;
    final appPayload = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
      binaryPayload,
    );
    return appPayload?.subtypeVersion ==
        ChannelAppDataHelper.mcoImageV3SubtypeVersion;
  }

  bool get isV4 {
    if (codecVersion == ChannelAppDataHelper.mcoImageV4Version) return true;
    final appPayload = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
      binaryPayload,
    );
    return appPayload?.subtypeVersion ==
        ChannelAppDataHelper.mcoImageV4SubtypeVersion;
  }

  String get textPayload {
    if (isV4) {
      final payload = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
        binaryPayload,
      );
      if (payload == null) {
        throw const MCOImageInvalidPayloadException(
          'Invalid MCOimg v4 gallery payload',
        );
      }
      return const MCOImageV4Codec().textFromBody(payload.body);
    }
    return isV3
        ? MCOImageV3Codec.textFromAppPayloadWithoutSender(binaryPayload)
        : MCOImageCodec.textFromBinaryPayload(binaryPayload);
  }

  MCOImage? tryDecodeImage() {
    try {
      if (isV4) {
        final payload = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
          binaryPayload,
        );
        if (payload == null) return null;
        final decoded = const MCOImageV4Codec().decodeBody(payload.body);
        final background = decoded.document.backgroundColor == null
            ? -1
            : decoded.document.palette[decoded.document.backgroundColor!];
        return MCOImageV4Preview(
          document: decoded.document,
          paletteProfile: decoded.document.paletteProfile,
          pixels: List<int>.filled(
            decoded.document.width * decoded.document.height,
            background,
          ),
          transparentColor: background < 0 ? background : null,
        );
      }
      return isV3
          ? MCOImageV3Codec().decodeAppPayloadWithoutSender(binaryPayload)
          : MCOImageCodec().decode(textPayload);
    } on MCOImageCodecException {
      return null;
    }
  }
}
